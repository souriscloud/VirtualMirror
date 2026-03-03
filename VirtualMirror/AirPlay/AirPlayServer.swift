import Foundation
import Network
import os

class AirPlayServer {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayServer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: AirPlayConnection] = [:]
    private let connectionQueue = DispatchQueue(label: "cloud.souris.virtualmirror.server.connections")
    private weak var manager: AirPlayManager?

    init(manager: AirPlayManager) {
        self.manager = manager
    }

    func start(port: UInt16) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid port: \(port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Server listening on port \(port)")
            case .failed(let error):
                self?.logger.error("Server failed: \(error)")
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
        connectionQueue.sync {
            for conn in connections.values {
                conn.close()
            }
            connections.removeAll()
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
        connectionQueue.sync {
            if !connections.isEmpty {
                logger.info("Closing \(self.connections.count) existing connection(s) for new session")
                for conn in connections.values {
                    conn.close()
                }
                connections.removeAll()
            }
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
            self?.connectionQueue.sync {
                self?.connections.removeValue(forKey: id)
            }
        }

        connection.start()
        logger.info("New connection from \(String(describing: nwConnection.endpoint))")
    }
}
