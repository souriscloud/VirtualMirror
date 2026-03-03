import Foundation
import Network
import os

class AirPlayConnection {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayConnection")
    private let connection: NWConnection
    private weak var manager: AirPlayManager?
    var onClose: (() -> Void)?

    private var buffer = Data()

    // Handlers
    private let pairSetupHandler = PairSetupHandler()
    private let pairVerifyHandler = PairVerifyHandler()
    private let fairPlayHandler = FairPlayHandler()

    // Mirror stream
    private var mirrorStreamReceiver: MirrorStreamReceiver?
    private var videoStreamPort: UInt16 = 47100
    private var timingPort: UInt16 = 47102
    private var audioStreamPort: UInt16 = 47103
    private var audioControlPort: UInt16 = 47104

    // Audio stream
    private var audioStreamReceiver: AudioStreamReceiver?

    // Volume level — pushed from AirPlayManager via AirPlayServer.setVolume()
    private var currentVolume: Float = 1.0

    // Event/timing listeners
    private var ntpTimingServer: NTPTimingServer?

    // FairPlay-decrypted key from session SETUP (raw, before SHA-512 derivation)
    private var fairplayKey: Data?
    // Raw eiv from session SETUP — used as AES-CBC IV for audio decryption
    private var sessionEIV: Data?
    // Monotonic request counter for protocol sequence logging
    private var requestSequence: UInt64 = 0

    init(connection: NWConnection, manager: AirPlayManager?) {
        self.connection = connection
        self.manager = manager
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Connection ready")
                self?.receiveData()
            case .failed(let error):
                self?.logger.error("Connection failed: \(error)")
                self?.close()
            case .cancelled:
                self?.logger.info("Connection cancelled")
                self?.manager?.didDisconnect()
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInteractive))
    }

    func close() {
        connection.cancel()
        shutdownAllResources()
    }

    /// Sets the audio volume on the active audio stream receiver.
    func setVolume(_ volume: Float) {
        currentVolume = volume
        audioStreamReceiver?.volume = volume
    }

    /// Full shutdown: stops all listeners, receivers, and helper services.
    /// Called when the control connection itself is closing.
    private func shutdownAllResources() {
        mirrorStreamReceiver?.stop()
        mirrorStreamReceiver = nil
        audioStreamReceiver?.stop()
        audioStreamReceiver = nil
        ntpTimingServer?.stop()
        ntpTimingServer = nil
    }

    /// Resets stream data connections but keeps listeners alive for re-SETUP.
    /// Called on TEARDOWN to allow the same connection to set up new streams
    /// (e.g. after rotation/lock).
    private func resetStreamResources() {
        mirrorStreamReceiver?.resetStream()
        audioStreamReceiver?.resetStream()
        ntpTimingServer?.stop()
        ntpTimingServer = nil
    }

    private func receiveData() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                self.logger.info("Connection closed by remote")
                self.close()
                return
            }

            if let error = error {
                self.logger.error("Receive error: \(error)")
                self.close()
                return
            }

            self.receiveData()
        }
    }

    private func processBuffer() {
        while !buffer.isEmpty {
            switch HTTPParser.parse(data: buffer) {
            case .needsMore:
                return
            case .parsed(let request, let consumed):
                buffer = Data(buffer.dropFirst(consumed))
                handleRequest(request)
            }
        }
    }

    private func handleRequest(_ request: HTTPRequest) {
        logger.debug(">>> \(request.method) \(request.path) (\(request.body.count) bytes) [seq=\(self.requestSequence)]")
        requestSequence += 1

        switch (request.method, request.path) {
        case ("GET", "/info"):
            handleInfo(request)

        case ("POST", "/pair-setup"):
            handlePairSetup(request)

        case ("POST", "/pair-verify"):
            handlePairVerify(request)

        case ("POST", "/fp-setup"):
            handleFPSetup(request)

        case ("SETUP", _):
            handleSetup(request)

        case ("RECORD", _):
            handleRecord(request)

        case ("TEARDOWN", _):
            handleTeardown(request)

        case ("SET_PARAMETER", _):
            handleSetParameter(request)

        case ("GET_PARAMETER", _):
            handleGetParameter(request)

        case ("POST", "/feedback"):
            sendResponse(HTTPResponse.ok(cseq: request.cseq))

        case ("POST", "/command"):
            sendResponse(HTTPResponse.ok(cseq: request.cseq))

        case ("POST", "/audioMode"):
            sendResponse(HTTPResponse.ok(cseq: request.cseq))

        case ("FLUSH", _):
            sendResponse(HTTPResponse.ok(cseq: request.cseq, isRTSP: true))

        case ("OPTIONS", _):
            let headers = [
                "Public": "SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER, POST, GET"
            ]
            sendResponse(HTTPResponse.build(headers: headers, cseq: request.cseq, isRTSP: true))

        default:
            logger.warning("Unhandled: \(request.method) \(request.path)")
            sendResponse(HTTPResponse.ok(cseq: request.cseq))
        }
    }

    // MARK: - Request Handlers

    private func handleInfo(_ request: HTTPRequest) {
        // The iPhone sends three variants of GET /info:
        // 1. With Content-Type: application/x-apple-binary-plist body containing
        //    {"qualifier": ["txtAirPlay"]} — respond with ONLY the TXT record data
        // 2. With CSeq but no body — respond with full /info plist
        // 3. No CSeq (Bluetooth LE) — not relevant for us
        //
        // UxPlay: if content_type is set, return only txtAirPlay/txtRAOP, then skip
        // all other fields. This is critical for the iPhone's initial discovery.

        if let contentType = request.contentType,
           contentType.contains("application/x-apple-binary-plist"),
           !request.body.isEmpty {
            // Parse qualifier from request body
            if let plist = try? PropertyListSerialization.propertyList(from: request.body, options: [], format: nil) as? [String: Any],
               let qualifier = plist["qualifier"] as? [String],
               let firstQualifier = qualifier.first {
                logger.debug("GET /info with qualifier: \(firstQualifier)")
                let body = AirPlayConfig.infoQualifierResponseData(qualifier: firstQualifier)
                sendResponse(HTTPResponse.okBplist(cseq: request.cseq, body: body))
                return
            }
        }

        logger.debug("GET /info (full response)")
        let body = AirPlayConfig.infoResponseData()
        sendResponse(HTTPResponse.okBplist(cseq: request.cseq, body: body))
    }

    private func handlePairSetup(_ request: HTTPRequest) {
        logger.debug("POST /pair-setup (\(request.body.count) bytes)")
        let responseData = pairSetupHandler.handle(requestBody: request.body)
        sendResponse(HTTPResponse.ok(
            cseq: request.cseq,
            body: responseData,
            contentType: "application/octet-stream"
        ))
    }

    private func handlePairVerify(_ request: HTTPRequest) {
        logger.debug("POST /pair-verify (\(request.body.count) bytes)")
        let responseData = pairVerifyHandler.handle(requestBody: request.body)
        sendResponse(HTTPResponse.ok(
            cseq: request.cseq,
            body: responseData,
            contentType: "application/octet-stream"
        ))
    }

    private func handleFPSetup(_ request: HTTPRequest) {
        logger.debug("POST /fp-setup (\(request.body.count) bytes)")
        let responseData = fairPlayHandler.handle(requestBody: request.body)
        sendResponse(HTTPResponse.ok(
            cseq: request.cseq,
            body: responseData,
            contentType: "application/octet-stream"
        ))
    }

    private func handleSetup(_ request: HTTPRequest) {
        logger.info("SETUP (\(request.body.count) bytes)")

        guard !request.body.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: request.body, options: [], format: nil) as? [String: Any] else {
            logger.error("SETUP: failed to parse plist")
            sendResponse(HTTPResponse.build(status: 400, statusText: "Bad Request", cseq: request.cseq, isRTSP: true))
            return
        }

        let keys = plist.keys.sorted().joined(separator: ", ")
        logger.debug("SETUP keys: \(keys)")

        // UxPlay processes ekey/eiv AND streams sequentially in the same handler,
        // building a single response dict. We match this behavior: both phases
        // contribute to the same response dictionary.
        var responsePlist: [String: Any] = [:]

        // Phase 1: session key exchange (if ekey/eiv present)
        let hasSessionData = plist["ekey"] is Data || plist["eiv"] is Data
        if hasSessionData {
            processSessionSetup(plist: plist)
            responsePlist["eventPort"] = 0
            responsePlist["timingPort"] = Int(timingPort)
            logger.info("Session SETUP processed (eventPort=0, timingPort=\(self.timingPort))")
        }

        // Phase 2: stream setup (if streams present)
        if let streams = plist["streams"] as? [[String: Any]] {
            let responseStreams = processStreamSetup(plist: plist, streams: streams)
            responsePlist["streams"] = responseStreams
        }

        if responsePlist.isEmpty {
            logger.warning("SETUP with neither ekey/eiv nor streams")
            sendResponse(HTTPResponse.ok(cseq: request.cseq, isRTSP: true))
        } else {
            let responseData = try! PropertyListSerialization.data(fromPropertyList: responsePlist, format: .binary, options: 0)
            sendResponse(HTTPResponse.okBplist(cseq: request.cseq, body: responseData, isRTSP: true))
        }
    }

    /// Process session key exchange (ekey/eiv). Does NOT send a response.
    private func processSessionSetup(plist: [String: Any]) {
        logger.debug("Session SETUP (event/timing channel)")

        // Reset any existing stream connections from a previous session
        // (handles reconnection after rotation/lock/unlock).
        // Keeps listeners alive to avoid port reuse race conditions.
        resetStreamResources()

        // Start NTP listener fresh for this session
        // Note: UxPlay does NOT use an event port in mirror/audio mode (eventPort=0).
        // We start NTP only; no event listener.
        ntpTimingServer = NTPTimingServer(port: timingPort)
        ntpTimingServer?.start()

        // Extract and decrypt the FairPlay key from ekey
        if let ekey = plist["ekey"] as? Data {
            if let decryptedKey = fairPlayHandler.decryptStreamKey(ekey: ekey) {
                self.fairplayKey = decryptedKey
                logger.debug("FairPlay key decrypted (\(decryptedKey.count) bytes)")
            } else {
                logger.error("Failed to decrypt FairPlay key")
            }
        }

        // Extract eiv — used as the AES-CBC IV for audio decryption
        if let eiv = plist["eiv"] as? Data {
            self.sessionEIV = eiv
            logger.debug("eiv extracted (\(eiv.count) bytes)")
        }

        // Extract device name for UI state
        if let name = plist["name"] as? String {
            logger.info("Device: \(name)")
            manager?.didStartConnecting(deviceName: name)
        }

        // Read the iPhone's timing port and start active NTP sync
        if let remoteTimingPort = plist["timingPort"] as? Int {
            if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, _) = remoteEndpoint {
                ntpTimingServer?.startActiveSync(remoteHost: host, remotePort: UInt16(remoteTimingPort))
            }
        }

        // Start audio listener eagerly during session SETUP (like UxPlay's raop_rtp_init).
        // UxPlay creates the audio RTP object during session SETUP, before any stream SETUP.
        // This ensures the UDP port is listening before the iPhone might send audio.
        if audioStreamReceiver == nil {
            audioStreamReceiver = AudioStreamReceiver(port: audioStreamPort, controlPort: audioControlPort)
        }
        audioStreamReceiver?.resetStream()
        audioStreamReceiver?.start()
        logger.debug("Audio listener started eagerly on port \(self.audioStreamPort)")
    }

    /// Process stream configuration. Returns the response streams array.
    private func processStreamSetup(plist: [String: Any], streams: [[String: Any]]) -> [[String: Any]] {
        var responseStreams: [[String: Any]] = []

        for stream in streams {
            let type = stream["type"] as? Int ?? -1

            if type == 110 {
                // Screen mirroring stream — extract streamConnectionID for key derivation
                var streamConnectionID: UInt64 = 0
                if let connID = stream["streamConnectionID"] as? UInt64 {
                    streamConnectionID = connID
                } else if let connID = stream["streamConnectionID"] as? Int64 {
                    streamConnectionID = UInt64(bitPattern: connID)
                } else if let connID = stream["streamConnectionID"] as? Int {
                    streamConnectionID = UInt64(connID)
                }
                startMirrorStream(streamConnectionID: streamConnectionID)
                responseStreams.append([
                    "type": 110,
                    "dataPort": Int(videoStreamPort),
                ] as [String: Any])
            } else if type == 96 {
                // Audio stream
                startAudioStream(streamInfo: stream)
                responseStreams.append([
                    "type": 96,
                    "dataPort": Int(audioStreamPort),
                    "controlPort": Int(audioControlPort),
                ] as [String: Any])
            } else {
                logger.warning("Unknown stream type: \(type)")
            }
        }

        logger.info("Stream SETUP: videoPort=\(self.videoStreamPort), audioPort=\(self.audioStreamPort)")
        return responseStreams
    }

    private func handleRecord(_ request: HTTPRequest) {
        logger.info("Handling RECORD - mirroring started!")
        manager?.didStartMirroring()
        let headers = [
            "Audio-Latency": "11025",
            "Audio-Jack-Status": "connected; type=analog"
        ]
        sendResponse(HTTPResponse.build(status: 200, headers: headers, cseq: request.cseq, isRTSP: true))
    }

    private func handleSetParameter(_ request: HTTPRequest) {
        // SET_PARAMETER can contain volume, progress, metadata, etc.
        if let contentType = request.contentType {
            logger.debug("SET_PARAMETER content-type: \(contentType)")
        }
        sendResponse(HTTPResponse.ok(cseq: request.cseq, isRTSP: true))
    }

    private func handleGetParameter(_ request: HTTPRequest) {
        // GET_PARAMETER body contains the parameter name(s) to query
        let paramName = String(data: request.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        logger.debug("GET_PARAMETER: '\(paramName)'")

        var responseBody = ""
        if paramName.contains("volume") {
            responseBody = "volume: 0.500000\r\n"
        }
        // Respond with the parameter value
        sendResponse(HTTPResponse.ok(
            cseq: request.cseq,
            body: Data(responseBody.utf8),
            contentType: responseBody.isEmpty ? nil : "text/parameters",
            isRTSP: true
        ))
    }

    private func handleTeardown(_ request: HTTPRequest) {
        logger.info("TEARDOWN")

        // Parse the TEARDOWN body — it may specify which streams to tear down
        if let plist = try? PropertyListSerialization.propertyList(from: request.body, options: [], format: nil) as? [String: Any] {
            if let streams = plist["streams"] as? [[String: Any]] {
                // Selective teardown: only reset the specified stream types
                for stream in streams {
                    let type = stream["type"] as? Int ?? -1
                    logger.debug("Tearing down stream type: \(type)")
                    if type == 110 {
                        mirrorStreamReceiver?.resetStream()
                    } else if type == 96 {
                        audioStreamReceiver?.resetStream()
                    }
                }
            } else {
                // Full teardown — reset all stream resources but keep listeners
                resetStreamResources()
            }
        } else {
            // No body or unparseable — reset everything
            resetStreamResources()
        }

        // Do NOT call manager?.didDisconnect() here — the control connection is still alive.
        // The sender will issue a new SETUP after rotation/lock. didDisconnect() is called
        // when the NWConnection itself closes (in the .cancelled state handler).
        sendResponse(HTTPResponse.ok(cseq: request.cseq, isRTSP: true))
    }

    // MARK: - Mirror Stream

    private func startMirrorStream(streamConnectionID: UInt64) {
        guard let manager = manager else { return }

        logger.debug("startMirrorStream: connID=\(streamConnectionID), fpKey=\(self.fairplayKey != nil), ecdh=\(self.pairVerifyHandler.derivedSharedSecret != nil))")

        // Reset the video decoder so it can accept new codec parameters
        manager.videoDecoder.reset()

        // Create receiver lazily (keeps listener alive across rotation)
        if mirrorStreamReceiver == nil {
            mirrorStreamReceiver = MirrorStreamReceiver(port: videoStreamPort, videoDecoder: manager.videoDecoder)
        }

        // Reset any existing data connection, then configure new encryption keys
        mirrorStreamReceiver?.resetStream()

        let ecdhSecret = pairVerifyHandler.derivedSharedSecret
        if ecdhSecret == nil {
            logger.warning("No ECDH secret from pair-verify — decryption will fail")
        }

        mirrorStreamReceiver?.configureEncryption(
            fairplayKey: fairplayKey,
            ecdhSecret: ecdhSecret,
            streamConnectionID: streamConnectionID
        )

        // start() is idempotent — no-ops if listener is already running
        mirrorStreamReceiver?.start()
        logger.debug("Mirror stream receiver started on port \(self.videoStreamPort)")
    }

    // MARK: - Audio Stream

    private func startAudioStream(streamInfo: [String: Any]) {
        // Create receiver lazily (keeps listener alive across rotation)
        if audioStreamReceiver == nil {
            audioStreamReceiver = AudioStreamReceiver(port: audioStreamPort, controlPort: audioControlPort)
        }

        // Apply current volume
        audioStreamReceiver?.volume = currentVolume

        // Reset any existing data connection, then configure for new stream
        audioStreamReceiver?.resetStream()

        let ecdhSecret = pairVerifyHandler.derivedSharedSecret
        audioStreamReceiver?.configure(
            streamInfo: streamInfo,
            fairplayKey: fairplayKey,
            ecdhSecret: ecdhSecret,
            eiv: sessionEIV
        )

        // start() is idempotent — no-ops if listener is already running
        audioStreamReceiver?.start()
        logger.debug("Audio stream receiver started on port \(self.audioStreamPort)")
    }

    // MARK: - Send Response

    private func sendResponse(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Send error: \(error)")
            }
        })
    }
}
