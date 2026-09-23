import Foundation
import Network
import dnssd
import os

class AirPlayServer {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayServer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AirPlayConnection] = [:]
    private let connectionQueue = DispatchQueue(label: "cloud.souris.virtualmirror.server.connections")
    private weak var manager: AirPlayManager?

    /// Called (once, from a network queue) if the listener can't be created or
    /// fails, e.g. the port is taken or Local Network access is denied.
    var onFailure: ((NWError) -> Void)?

    init(manager: AirPlayManager) {
        self.manager = manager
    }

    func start(port: UInt16) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid port: \(port)")
                onFailure?(.posix(.EINVAL))
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create listener: \(error)")
            onFailure?(error as? NWError ?? .posix(.EINVAL))
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Server listening on port \(port)")
            case .failed(let error):
                self?.logger.error("Server failed: \(error)")
                self?.onFailure?(error)
            case .waiting(let error):
                // Usually transient, except a Local Network privacy denial,
                // which won't resolve until the user changes the setting.
                self?.logger.warning("Server waiting: \(error)")
                if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
                    self?.onFailure?(error)
                }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] nwConnection in
            self?.handleNewConnection(nwConnection)
        }

        listener?.start(queue: .global(qos: .userInteractive))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        closeAllConnections()
    }

    /// Closes every control connection. Each connection still reports its own
    /// end of session to the manager: `close()` keeps it alive until it has.
    func closeAllConnections() {
        let closing = connectionQueue.sync {
            let all = Array(connections.values)
            connections.removeAll()
            return all
        }
        for conn in closing {
            conn.close()
        }
    }

    /// Pushes volume level to all active connections.
    func setVolume(_ volume: Float) {
        connectionQueue.sync {
            for conn in connections.values {
                conn.setVolume(volume)
            }
        }
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        // Single-device mode: close any existing connections before accepting a new one.
        // This handles the case where an iPhone reconnects (rotation, lock/unlock) and
        // the old connection hasn't fully torn down yet.
        if connectionQueue.sync(execute: { !connections.isEmpty }) {
            logger.info("Closing existing connection(s) for new session")
            closeAllConnections()
        }

        let connection = AirPlayConnection(
            connection: nwConnection,
            manager: manager
        )
        let id = ObjectIdentifier(connection)
        connectionQueue.sync {
            connections[id] = connection
        }

        connection.onClose = { [weak self] in
            _ = self?.connectionQueue.sync {
                self?.connections.removeValue(forKey: id)
            }
        }

        connection.start()
        logger.info("New connection from \(String(describing: nwConnection.endpoint))")
    }
}
