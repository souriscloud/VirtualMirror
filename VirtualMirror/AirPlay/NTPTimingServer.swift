import Foundation
import Network
import os

/// AirPlay NTP-like timing server.
/// Handles both:
/// 1. Responding to timing requests from the iPhone (passive)
/// 2. Actively sending timing requests to the iPhone every 3 seconds (active)
class NTPTimingServer {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "NTPTiming")
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var activeSyncTimer: DispatchSourceTimer?
    private var sequenceNumber: UInt16 = 0
    let port: UInt16

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid NTP port: \(self.port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create NTP listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.logger.info("NTP timing server ready on port \(self?.port ?? 0)")
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener?.start(queue: .global(qos: .userInteractive))
    }

    /// Start actively sending NTP timing requests to the iPhone's timing port.
    /// This is critical for keeping the AirPlay session alive.
    func startActiveSync(remoteHost: NWEndpoint.Host, remotePort: UInt16) {
        logger.info("Starting active NTP sync to \(String(describing: remoteHost)):\(remotePort)")

        guard let nwPort = NWEndpoint.Port(rawValue: remotePort) else {
            logger.error("Invalid remote NTP port: \(remotePort)")
            return
        }

        let connection = NWConnection(
            host: remoteHost,
            port: nwPort,
            using: .udp
        )
        self.activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.info("NTP active sync connection ready")
                self.startTimingRequestLoop()
            case .failed(let error):
                self.logger.error("NTP active sync failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInteractive))
    }

    func stop() {
        activeSyncTimer?.cancel()
        activeSyncTimer = nil
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Active NTP Sync (send requests to iPhone)

    private func startTimingRequestLoop() {
        // Send first request immediately
        sendTimingRequest()

        // Then every 3 seconds
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 3, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            self?.sendTimingRequest()
        }
        timer.resume()
        self.activeSyncTimer = timer
    }

    private func sendTimingRequest() {
        guard let connection = activeConnection else { return }

        // Build a 32-byte NTP timing request (matches RPiPlay format)
        // Bytes 0-1: RTP header (0x80, 0xd2 = version 2, payload type 210)
        // Bytes 2-3: sequence number (big-endian)
        // Bytes 4-23: zeros
        // Bytes 24-31: transmit timestamp (our send time)
        var request = Data(count: 32)
        request[0] = 0x80
        request[1] = 0xd2

        let seq = sequenceNumber
        sequenceNumber &+= 1
        request[2] = UInt8(seq >> 8)
        request[3] = UInt8(seq & 0xFF)

        // Put our transmit timestamp at offset 24
        let now = currentNTPTimestamp()
        withUnsafeBytes(of: now.bigEndian) { ptr in
            request[24..<32] = Data(ptr)
        }

        connection.send(content: request, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("NTP request send error: \(error)")
                return
            }
        })

        // Receive the response
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data, data.count >= 32 {
                self?.logger.debug("NTP response received: \(data.count) bytes")
            }
            if let error = error {
                self?.logger.debug("NTP response error: \(error)")
            }
        }
    }

    // MARK: - Passive NTP (respond to iPhone's requests)

    private func handleConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receiveTimingRequest(on: conn)
            }
        }
        conn.start(queue: .global(qos: .userInteractive))
    }

    private func receiveTimingRequest(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, data.count >= 32 {
                let receiveTime = self.currentNTPTimestamp()
                let response = self.buildTimingResponse(request: data, receiveTime: receiveTime)
                conn.send(content: response, completion: .contentProcessed { _ in })
            }

            if !isComplete && error == nil {
                self.receiveTimingRequest(on: conn)
            }
        }
    }

    private func buildTimingResponse(request: Data, receiveTime: UInt64) -> Data {
        // AirPlay timing packet: 32 bytes
        // Response format:
        //   Bytes 0-7:   copy from request (marker/RTP header)
        //   Bytes 8-15:  origin timestamp = client's T1 (from request bytes 24-31)
        //   Bytes 16-23: receive timestamp = our time when we got the request (T2)
        //   Bytes 24-31: transmit timestamp = our time when we send the response (T3)

        var response = Data(count: 32)

        // Copy marker bytes (0-7) from request
        response[0..<8] = request[0..<8]

        // Origin timestamp (bytes 8-15) = client's transmit timestamp from request (bytes 24-31)
        response[8..<16] = request[24..<32]

        // Our receive timestamp (bytes 16-23) — captured when packet arrived
        withUnsafeBytes(of: receiveTime.bigEndian) { ptr in
            response[16..<24] = Data(ptr)
        }

        // Our transmit timestamp (bytes 24-31) — captured now, at send time
        let transmitTime = currentNTPTimestamp()
        withUnsafeBytes(of: transmitTime.bigEndian) { ptr in
            response[24..<32] = Data(ptr)
        }

        return response
    }

    /// Returns current time as an NTP timestamp (64-bit: upper 32 = seconds since 1900, lower 32 = fraction)
    private func currentNTPTimestamp() -> UInt64 {
        let ntpEpochOffset: UInt64 = 2208988800
        let now = Date().timeIntervalSince1970
        let seconds = UInt64(now) + ntpEpochOffset
        let fraction = UInt64((now - Double(UInt64(now))) * Double(UInt32.max))
        return (seconds << 32) | fraction
    }
}
