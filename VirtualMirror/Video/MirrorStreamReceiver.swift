import Foundation
import Network
import CryptoKit
import os

class MirrorStreamReceiver {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "MirrorStream")
    private var listener: NWListener?
    private var connection: NWConnection?
    private let port: UInt16
    private let videoDecoder: VideoDecoder
    private var videoDecryptor = VideoDecryptor()
    private var buffer = Data()

    // Packet header size
    private static let headerSize = 128

    // Generation counter: incremented on every resetStream() / new connection.
    // Pending receiveData callbacks from stale connections compare their captured
    // generation against the current value and bail out if mismatched.
    private var connectionGeneration: UInt64 = 0

    // Stored encryption parameters — needed to recreate the decryptor when the
    // iPhone resets the CTR counter mid-stream (e.g. on rotation without TEARDOWN).
    private var currentDecryptKey: Data?
    private var currentDecryptIV: Data?

    // Video stream state tracking
    private var videoStreamSuspended = false

    init(port: UInt16, videoDecoder: VideoDecoder) {
        self.port = port
        self.videoDecoder = videoDecoder
    }

    /// Configures encryption keys for the current stream.
    /// Can be called again after a stream reset (rotation) with new keys.
    func configureEncryption(fairplayKey: Data?, ecdhSecret: Data?, streamConnectionID: UInt64) {
        if let fpKey = fairplayKey, let ecdh = ecdhSecret {
            let (derivedKey, derivedIV) = deriveMirrorKeys(fairplayKey: fpKey, ecdhSecret: ecdh, streamConnectionID: streamConnectionID)
            currentDecryptKey = derivedKey
            currentDecryptIV = derivedIV
            resetDecryptor()
            logger.info("Mirror AES key and IV derived for streamConnectionID=\(streamConnectionID)")
        } else {
            currentDecryptKey = nil
            currentDecryptIV = nil
            videoDecryptor = VideoDecryptor()
            logger.warning("Missing fairplayKey or ecdhSecret — video will not be decrypted")
        }
    }

    /// Recreates the AES-CTR decryptor with the stored key/IV, resetting the counter to 0.
    /// Called when codec data arrives mid-stream (rotation) because the iPhone resets
    /// its encryption counter when the stream parameters change.
    private func resetDecryptor() {
        videoDecryptor = VideoDecryptor()
        if let key = currentDecryptKey, let iv = currentDecryptIV {
            videoDecryptor.configure(key: key, iv: iv)
        }
    }

    /// Resets the stream for a new session (rotation/reconnect).
    /// Closes the current data connection and clears the buffer, but
    /// keeps the listener alive so the new connection can bind immediately.
    func resetStream() {
        connectionGeneration &+= 1
        connection?.cancel()
        connection = nil
        buffer = Data()
        packetCount = 0
        currentDecryptKey = nil
        currentDecryptIV = nil
        videoDecryptor = VideoDecryptor()
        videoStreamSuspended = false
        logger.info("Mirror stream reset (gen=\(self.connectionGeneration), listener kept alive)")
    }

    func start() {
        guard listener == nil else {
            logger.debug("Mirror stream listener already running on port \(self.port)")
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid mirror stream port: \(self.port)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            logger.error("Failed to create mirror stream listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Mirror stream listener ready on port \(self?.port ?? 0)")
            case .failed(let error):
                self?.logger.error("Mirror stream listener failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] nwConnection in
            self?.handleMirrorConnection(nwConnection)
        }

        listener?.start(queue: .global(qos: .userInteractive))
    }

    /// Derive the actual AES-128-CTR key and IV for mirror stream decryption.
    private func deriveMirrorKeys(fairplayKey: Data, ecdhSecret: Data, streamConnectionID: UInt64) -> (key: Data, iv: Data) {
        // Step 1: eaeskey = SHA-512(fairplayKey[16] || ecdhSecret[32]), take first 16 bytes
        var hasher1 = SHA512()
        hasher1.update(data: fairplayKey)
        hasher1.update(data: ecdhSecret)
        let eaeskey = Data(hasher1.finalize().prefix(16))

        // Step 2: decrypt_key = SHA-512("AirPlayStreamKey{connID}" || eaeskey[16]), take first 16 bytes
        var hasher2 = SHA512()
        let skeyString = "AirPlayStreamKey\(streamConnectionID)"
        hasher2.update(data: Data(skeyString.utf8))
        hasher2.update(data: eaeskey)
        let decryptKey = Data(hasher2.finalize().prefix(16))

        // Step 3: decrypt_iv = SHA-512("AirPlayStreamIV{connID}" || eaeskey[16]), take first 16 bytes
        var hasher3 = SHA512()
        let sivString = "AirPlayStreamIV\(streamConnectionID)"
        hasher3.update(data: Data(sivString.utf8))
        hasher3.update(data: eaeskey)
        let decryptIV = Data(hasher3.finalize().prefix(16))

        return (decryptKey, decryptIV)
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        buffer = Data()
    }

    private func handleMirrorConnection(_ nwConnection: NWConnection) {
        // Bump generation to invalidate any pending receiveData callbacks
        connectionGeneration &+= 1
        let gen = connectionGeneration

        // Close any existing data connection (rotation/lock-unlock case)
        if connection != nil {
            logger.debug("Replacing existing mirror data connection (gen=\(gen))")
            connection?.cancel()
            connection = nil
            buffer = Data()
        }

        logger.info("Mirror stream connection accepted (gen=\(gen))")
        self.connection = nwConnection

        nwConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.debug("Mirror stream connection ready (gen=\(gen))")
                self.receiveData(generation: gen)
            case .failed(let error):
                self.logger.error("Mirror stream connection failed: \(error)")
            case .cancelled:
                self.logger.debug("Mirror stream connection cancelled")
            default:
                break
            }
        }

        nwConnection.start(queue: .global(qos: .userInteractive))
    }

    private func receiveData(generation: UInt64) {
        guard generation == connectionGeneration else {
            logger.debug("Discarding stale receiveData callback (gen=\(generation), current=\(self.connectionGeneration))")
            return
        }

        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            // Check generation again — resetStream() may have fired between
            // the receive call and this callback.
            guard generation == self.connectionGeneration else {
                self.logger.debug("Discarding stale receive data (gen=\(generation), current=\(self.connectionGeneration))")
                return
            }

            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                self.logger.info("Mirror stream ended")
                return
            }

            if let error = error {
                self.logger.error("Mirror stream receive error: \(error)")
                return
            }

            self.receiveData(generation: generation)
        }
    }

    private var packetCount = 0

    private func processBuffer() {
        while buffer.count >= MirrorStreamReceiver.headerSize {
            // Read the 128-byte packet header
            let payloadSize = buffer.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(as: UInt32.self).littleEndian
            }
            // Type is a single byte at offset 4; byte 5 is flags (0x10 = keyframe/IDR)
            let payloadType: UInt8 = buffer[buffer.startIndex + 4]
            let payloadFlags: UInt8 = buffer[buffer.startIndex + 5]
            // Byte 6: codec sub-flags for type 1 packets
            //   0x16/0x1e = normal h264/h265 SPS+PPS (stream active)
            //   0x56/0x5e = h264/h265 SPS+PPS (stream suspending, client sleeping)
            let codecSubFlags: UInt8 = buffer[buffer.startIndex + 6]

            let totalPacketSize = MirrorStreamReceiver.headerSize + Int(payloadSize)

            // Sanity check - if payload is unreasonably large, our parsing is probably wrong
            if payloadSize > 10_000_000 {
                logger.error("Unreasonable payload size: \(payloadSize) - header parsing may be wrong. Dumping first 64 bytes:")
                let dump = buffer.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.error("\(dump)")
                buffer.removeAll()
                return
            }

            guard buffer.count >= totalPacketSize else {
                return
            }

            // Extract NTP timestamp (bytes 8-15)
            let ntpTimestamp = buffer.withUnsafeBytes { ptr -> UInt64 in
                ptr.load(fromByteOffset: 8, as: UInt64.self).bigEndian
            }

            // Extract payload
            let payloadStart = buffer.startIndex + MirrorStreamReceiver.headerSize
            let payloadEnd = payloadStart + Int(payloadSize)
            let payload = Data(buffer[payloadStart..<payloadEnd])

            // Consume this packet from the buffer
            buffer = Data(buffer[payloadEnd...])
            packetCount += 1

            // Process based on type
            switch payloadType {
            case 0:
                // Video data — always feed to decoder. VideoToolbox recovers on
                // next IDR; dropping frames caused permanent freezes after unlock.
                handleVideoPayload(payload, timestamp: ntpTimestamp)
            case 1:
                // Codec data (SPS/PPS) — check for suspend/resume
                handleCodecData(payload, codecSubFlags: codecSubFlags, timestamp: ntpTimestamp)
            case 2:
                logger.debug("Mirror stream heartbeat")
            case 5:
                // Control/notification packet — skip
                break
            default:
                logger.info("Unknown mirror packet type: \(payloadType), size: \(payloadSize)")
            }
        }
    }

    private func handleVideoPayload(_ payload: Data, timestamp: UInt64) {
        guard !payload.isEmpty else { return }

        // Decrypt if configured
        let decrypted: Data
        if videoDecryptor.isConfigured {
            decrypted = videoDecryptor.decrypt(data: payload)
        } else {
            decrypted = payload
        }

        // Always feed frames to the decoder — VideoToolbox handles missing
        // references (logs errors but recovers on next IDR). Dropping frames
        // (e.g. NAL forbidden_zero_bit check, IDR gating) caused permanent
        // freezes after lock/unlock because the iPhone doesn't send IDR.
        videoDecoder.decodeVideoData(decrypted, timestamp: timestamp)
    }

    private func handleCodecData(_ payload: Data, codecSubFlags: UInt8, timestamp: UInt64) {
        logger.info("Received codec data: \(payload.count) bytes, subFlags=0x\(String(codecSubFlags, radix: 16))")
        guard payload.count >= 8 else {
            logger.error("Codec data too short")
            return
        }

        // Detect video stream suspend/resume (UxPlay raop_rtp_mirror.c)
        // Byte 6 of the 128-byte header (codecSubFlags):
        //   0x16/0x1e = normal h264/h265 SPS+PPS (stream active/resuming)
        //   0x56/0x5e = h264/h265 SPS+PPS (stream suspending, client sleeping)
        let isSuspending = (codecSubFlags == 0x56 || codecSubFlags == 0x5e)

        if isSuspending {
            if !videoStreamSuspended {
                videoStreamSuspended = true
                logger.info("Video stream SUSPENDED (client sleeping/locked)")
            }
            // Still configure the decoder — the SPS/PPS is valid and we'll need
            // it when the stream resumes. NOT returning here prevents state from
            // getting stuck if the resume flag doesn't match our expectations.
        } else {
            if videoStreamSuspended {
                videoStreamSuspended = false
                logger.info("Video stream RESUMED (client unlocked), subFlags=0x\(String(codecSubFlags, radix: 16))")
            }
        }

        // Do NOT reset the decryptor here. The iPhone's AES-CTR counter is
        // continuous across the entire TCP stream — it does NOT reset when
        // new codec data (rotation/lock) arrives. Only the video decoder
        // needs to be reconfigured with the new SPS/PPS.
        videoDecoder.configureWithAVCC(payload)
    }
}
