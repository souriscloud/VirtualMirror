import Foundation
import Darwin
import CommonCrypto
import CryptoKit
import AudioToolbox
import os

/// Receives RTP audio packets over UDP from the AirPlay sender,
/// decrypts them (AES-128-CBC, per-packet with session eiv), decodes AAC to PCM,
/// and plays the audio through the system output.
///
/// Uses raw POSIX UDP sockets (not NWListener) because the AirPlay audio protocol
/// sends independent datagrams from potentially varying source ports. NWListener's
/// connection-per-endpoint model loses packets after the initial "no-data" marker.
///
/// Two UDP sockets are used (matching UxPlay's architecture):
///   - Data socket (port 47103): receives RTP audio packets
///   - Control socket (port 47104): receives sync/timing packets from the iPhone
///     and sends resend requests back. The iPhone sends type 0x54 sync packets here
///     before real audio data flows on the data port.
class AudioStreamReceiver {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AudioStream")

    // Data socket (receives RTP audio packets)
    private var dataSocket: Int32 = -1
    private var dataReadSource: DispatchSourceRead?
    let port: UInt16

    // Control socket (receives sync packets, sends resend requests)
    private var controlSocket: Int32 = -1
    private var controlReadSource: DispatchSourceRead?
    let controlPort: UInt16

    private let audioDecoder = AudioDecoder()
    private let audioPlayer = AudioPlayer()

    /// Volume level (0.0 = silent, 1.0 = full). Forwarded to AudioPlayer.
    var volume: Float = 1.0 {
        didSet {
            audioPlayer.volume = volume
        }
    }

    // Audio stream parameters (from SETUP plist)
    private var samplesPerFrame: UInt32 = 480
    private var channels: UInt32 = 2
    private var sampleRate: Float64 = 44100

    // Encryption — AES-128-CBC per-packet (key from SHA-512, IV from session eiv)
    private var decryptKey: Data?
    private var decryptIV: Data?
    private var isEncrypted = false

    private var packetCount = 0
    private var controlPacketCount = 0
    
    // Sync state — the iPhone sends type 0x54 sync packets on the control port.
    // UxPlay gates audio playback on receiving the first sync.
    private var initialSyncReceived = false

    // Remote control address — learned from the first control packet's source address.
    // Used to send resend requests back to the iPhone.
    private var remoteControlAddr: sockaddr_storage?
    private var remoteControlAddrLen: socklen_t = 0

    // AAC-ELD "no data" marker: the first packets in a stream carry this
    // 4-byte payload instead of actual audio. UxPlay skips them.
    private static let noDataMarker = Data([0x00, 0x68, 0x34, 0x00])

    // RTP sequence number deduplication — with redundantAudio=2, the iPhone sends
    // every packet 3 times (pattern: 0 0 1 0 1 2 1 2 3 ...). UxPlay handles this
    // in raop_buffer_enqueue() with a 32-entry ring buffer indexed by seqnum % 32
    // and a "filled" flag. We use the same approach.
    private static let seqBufferSize = 32
    private var seqBuffer = [Bool](repeating: false, count: 32)
    private var seqBufferBase: UInt16 = 0  // lowest seqnum currently in the buffer window
    private var seqBufferInitialized = false

    init(port: UInt16, controlPort: UInt16) {
        self.port = port
        self.controlPort = controlPort
    }

    /// Configures the audio stream from the SETUP plist stream dictionary.
    /// Audio uses AES-128-CBC with:
    ///   key = SHA-512(fairplayKey || ecdhSecret)[0..15]
    ///   iv  = eiv from session SETUP (raw, 16 bytes)
    func configure(streamInfo: [String: Any], fairplayKey: Data?, ecdhSecret: Data?, eiv: Data?) {
        // Extract audio parameters
        if let ct = streamInfo["ct"] as? Int {
            logger.debug("Audio compression type: \(ct)")
        }
        if let spf = streamInfo["spf"] as? Int {
            self.samplesPerFrame = UInt32(spf)
        }
        if let sr = streamInfo["sr"] as? Int {
            self.sampleRate = Float64(sr)
        }
        if let ch = streamInfo["channels"] as? Int {
            self.channels = UInt32(ch)
        }

        let audioFormat = streamInfo["audioFormat"] as? Int ?? 0x40000
        logger.debug("Audio format: 0x\(String(audioFormat, radix: 16))")

        // Determine the codec type.
        // ct=8 / audioFormat=0x1000000 = AAC-ELD (Enhanced Low Delay), spf=480
        // ct=4 / audioFormat=0x40000   = AAC-ELD (alternate flag)
        // ct=2 / audioFormat=0x20000   = ALAC (Apple Lossless), spf=352
        let codecType: AudioFormatID
        switch audioFormat {
        case 0x40000, 0x1000000:
            codecType = kAudioFormatMPEG4AAC_ELD
        case 0x10000:
            codecType = kAudioFormatMPEG4AAC
        case 0x20000:
            codecType = kAudioFormatAppleLossless
        default:
            codecType = kAudioFormatMPEG4AAC_ELD
            logger.warning("Unknown audio format 0x\(String(audioFormat, radix: 16)), defaulting to AAC-ELD")
        }

        audioDecoder.configure(codecType: codecType, sampleRate: sampleRate, channels: channels, samplesPerFrame: samplesPerFrame)
        audioPlayer.configure(sampleRate: sampleRate, channels: channels)

        // Derive audio decryption key using SHA-512 (same hash as video key derivation chain)
        if let fpKey = fairplayKey, let ecdh = ecdhSecret, let iv = eiv, iv.count >= 16 {
            let key = deriveAudioKey(fairplayKey: fpKey, ecdhSecret: ecdh)
            self.decryptKey = key
            self.decryptIV = iv.prefix(16)
            self.isEncrypted = true
            logger.info("Audio AES-CBC key derived, eiv set (\(iv.count) bytes)")
        } else {
            logger.warning("Missing fairplayKey, ecdhSecret, or eiv — audio will not be decrypted")
        }
    }

    /// Resets the stream for a new session (rotation/reconnect).
    /// Keeps sockets alive but resets dispatch sources, decoder, and player.
    func resetStream() {
        dataReadSource?.cancel()
        dataReadSource = nil
        controlReadSource?.cancel()
        controlReadSource = nil
        packetCount = 0
        controlPacketCount = 0
        initialSyncReceived = false
        remoteControlAddr = nil
        remoteControlAddrLen = 0
        seqBuffer = [Bool](repeating: false, count: AudioStreamReceiver.seqBufferSize)
        seqBufferBase = 0
        seqBufferInitialized = false
        audioPlayer.stop()
        audioDecoder.stop()
        decryptKey = nil
        decryptIV = nil
        isEncrypted = false
        logger.info("Audio stream reset (listener kept alive)")
    }

    /// Starts both UDP socket listeners. Idempotent — no-ops if already running.
    func start() {
        startDataSocket()
        startControlSocket()
    }

    private func startDataSocket() {
        guard dataSocket == -1 else {
            logger.debug("Audio data socket already open on port \(self.port)")
            if dataReadSource == nil {
                startDataReadSource()
            }
            return
        }

        dataSocket = createUDPSocket(port: port)
        guard dataSocket >= 0 else {
            logger.error("Failed to create audio data socket on port \(self.port)")
            return
        }

        startDataReadSource()
        logger.info("Audio stream listener ready on port \(self.port)")
    }

    private func startControlSocket() {
        guard controlSocket == -1 else {
            logger.debug("Audio control socket already open on port \(self.controlPort)")
            if controlReadSource == nil {
                startControlReadSource()
            }
            return
        }

        controlSocket = createUDPSocket(port: controlPort)
        guard controlSocket >= 0 else {
            logger.error("Failed to create audio control socket on port \(self.controlPort)")
            return
        }

        startControlReadSource()
        logger.info("Audio control listener ready on port \(self.controlPort)")
    }

    /// Creates a non-blocking IPv6 dual-stack UDP socket bound to the given port.
    private func createUDPSocket(port: UInt16) -> Int32 {
        let sock = Darwin.socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            logger.error("Failed to create UDP socket: errno=\(errno)")
            return -1
        }

        // Non-blocking mode — required for DispatchSource.makeReadSource
        let flags = fcntl(sock, F_GETFL)
        fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        // Allow address reuse
        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Allow IPv4-mapped IPv6 addresses (dual-stack)
        var v6Only: Int32 = 0
        setsockopt(sock, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))

        // Increase receive buffer to 256KB to avoid dropping datagrams
        var rcvBuf: Int32 = 256 * 1024
        setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &rcvBuf, socklen_t(MemoryLayout<Int32>.size))

        // Bind to the port on all interfaces
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind UDP socket to port \(port): errno=\(errno)")
            Darwin.close(sock)
            return -1
        }

        return sock
    }

    // MARK: - Dispatch Source Management

    private func startDataReadSource() {
        guard dataSocket >= 0 else { return }
        let source = DispatchSource.makeReadSource(
            fileDescriptor: dataSocket,
            queue: .global(qos: .userInteractive)
        )
        source.setEventHandler { [weak self] in self?.readDataPackets() }
        source.setCancelHandler { [weak self] in self?.logger.debug("Audio data dispatch source cancelled") }
        source.resume()
        dataReadSource = source
    }

    private func startControlReadSource() {
        guard controlSocket >= 0 else { return }
        let source = DispatchSource.makeReadSource(
            fileDescriptor: controlSocket,
            queue: .global(qos: .userInteractive)
        )
        source.setEventHandler { [weak self] in self?.readControlPackets() }
        source.setCancelHandler { [weak self] in self?.logger.debug("Audio control dispatch source cancelled") }
        source.resume()
        controlReadSource = source
    }

    // MARK: - Reading Packets

    /// Reads all available UDP datagrams from the data socket.
    private func readDataPackets() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var recvErrorCount = 0
        while true {
            let bytesRead = recv(dataSocket, &buffer, buffer.count, 0)
            if bytesRead <= 0 {
                let err = errno
                if bytesRead < 0 && err != EAGAIN && err != EWOULDBLOCK {
                    recvErrorCount += 1
                    if recvErrorCount <= 5 {
                        logger.error("Audio data recv error: errno=\(err) (\(String(cString: strerror(err))))")
                    }
                }
                break
            }
            let data = Data(buffer.prefix(bytesRead))
            processRTPPacket(data)
        }
    }

    /// Reads all available UDP datagrams from the control socket.
    private func readControlPackets() {
        var buffer = [UInt8](repeating: 0, count: 256)
        var saddr = sockaddr_storage()
        var saddrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)

        while true {
            let bytesRead = withUnsafeMutablePointer(to: &saddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    recvfrom(controlSocket, &buffer, buffer.count, 0, sockPtr, &saddrLen)
                }
            }
            guard bytesRead > 0 else { break }

            // Learn the remote control address from the first packet
            if remoteControlAddr == nil {
                remoteControlAddr = saddr
                remoteControlAddrLen = saddrLen
                logger.info("Audio control: learned remote address from first packet")
            }

            let data = Data(buffer.prefix(bytesRead))
            processControlPacket(data)
        }
    }

    /// Full shutdown: stops sockets, dispatch sources, decoder, and player.
    func stop() {
        dataReadSource?.cancel()
        dataReadSource = nil
        controlReadSource?.cancel()
        controlReadSource = nil
        if dataSocket >= 0 {
            Darwin.close(dataSocket)
            dataSocket = -1
        }
        if controlSocket >= 0 {
            Darwin.close(controlSocket)
            controlSocket = -1
        }
        audioPlayer.stop()
        audioDecoder.stop()
        decryptKey = nil
        decryptIV = nil
        isEncrypted = false
    }

    // MARK: - Control Packet Processing

    private func processControlPacket(_ data: Data) {
        guard data.count >= 4 else { return }

        // Control packet format:
        //   Byte 0: flags (0x90 = first sync, 0x80 = subsequent)
        //   Byte 1: type (with high bit potentially set: type = byte1 & 0x7F)
        //           0x54 (0xD4 & 0x7F) = sync packet
        //           0x56 (0xD6 & 0x7F) = resent data packet
        //           0x55 (0xD5 & 0x7F) = resend request (from us)
        let type = data[data.startIndex + 1] & 0x7F
        controlPacketCount += 1

        switch type {
        case 0x54:
            // Sync packet — contains RTP timestamp and NTP time reference
            processSyncPacket(data)

        case 0x56:
            // Resent data packet — the actual RTP audio data starts at byte 4
            if data.count > 4 {
                let rtpData = Data(data.suffix(from: data.startIndex + 4))
                processRTPPacket(rtpData)
            }

        default:
            if controlPacketCount <= 3 {
                logger.debug("Audio control: unknown type 0x\(String(type, radix: 16)), \(data.count) bytes")
            }
        }
    }

    private func processSyncPacket(_ data: Data) {
        // Sync packet layout (20 bytes):
        //   Bytes 0-1: header (flags + type)
        //   Bytes 2-3: extension (sequence)
        //   Bytes 4-7: RTP timestamp (sync point, big-endian uint32)
        //   Bytes 8-15: Remote NTP timestamp (big-endian uint64)
        //   Bytes 16-19: Next RTP timestamp (big-endian uint32)
        guard data.count >= 20 else {
            logger.warning("Audio sync packet too short: \(data.count) bytes")
            return
        }

        let isFirst = (data[data.startIndex] & 0x10) != 0

        if !initialSyncReceived {
            initialSyncReceived = true
            logger.info("Audio: initial sync received (first=\(isFirst)) — audio playback enabled")
        } else if controlPacketCount <= 5 {
            logger.debug("Audio sync packet (first=\(isFirst))")
        }
    }

    // MARK: - RTP Audio Packet Processing

    private func processRTPPacket(_ data: Data) {
        // RTP header is 12 bytes minimum:
        //   Byte 0:    V=2, P, X, CC
        //   Byte 1:    M, PT (payload type)
        //   Bytes 2-3: Sequence number (big-endian uint16)
        //   Bytes 4-7: Timestamp
        //   Bytes 8-11: SSRC
        guard data.count >= 12 else { return }

        // Extract RTP sequence number for deduplication (bytes 2-3, big-endian)
        let seqNum = UInt16(data[data.startIndex + 2]) << 8 | UInt16(data[data.startIndex + 3])

        // Deduplicate: with redundantAudio=2, every packet is sent 3 times.
        // Use a 32-entry ring buffer (same as UxPlay's raop_buffer) to track
        // which sequence numbers we've already processed.
        if isDuplicateSeqNum(seqNum) {
            return
        }

        let headerByte0 = data[data.startIndex]
        let csrcCount = Int(headerByte0 & 0x0F)
        let hasExtension = (headerByte0 & 0x10) != 0

        var headerSize = 12 + csrcCount * 4

        // Handle RTP header extension
        if hasExtension {
            guard data.count >= headerSize + 4 else { return }
            let extensionLength = data.withUnsafeBytes { ptr -> Int in
                Int(ptr.load(fromByteOffset: headerSize + 2, as: UInt16.self).bigEndian) * 4
            }
            headerSize += 4 + extensionLength
        }

        guard data.count > headerSize else { return }

        let audioData = Data(data.suffix(from: data.startIndex + headerSize))

        // Skip "no data" marker packets (AAC-ELD initial packets)
        if audioData.count == 4 && audioData == AudioStreamReceiver.noDataMarker {
            if packetCount < 5 {
                logger.debug("Audio RTP: skipping no-data marker packet")
            }
            packetCount += 1
            return
        }

        // Also skip empty or header-only packets (12 bytes total = no payload)
        if audioData.isEmpty {
            packetCount += 1
            return
        }

        // Decrypt using AES-128-CBC (per-packet, with session eiv)
        var decryptedData = audioData
        if isEncrypted {
            decryptedData = decryptAudio(data: audioData)
        }

        packetCount += 1

        // Decode AAC to PCM
        if let pcm = audioDecoder.decode(aacData: decryptedData, samplesPerFrame: samplesPerFrame) {
            audioPlayer.play(pcmData: pcm)
        } else if packetCount <= 5 {
            logger.warning("Audio decode returned nil for packet #\(self.packetCount - 1)")
        }
    }

    // MARK: - Sequence Number Deduplication

    /// Returns true if this seqNum has already been processed (duplicate).
    /// Uses a 32-entry ring buffer matching UxPlay's raop_buffer approach.
    /// The buffer tracks a sliding window of sequence numbers. When a new seqnum
    /// arrives that's ahead of the window, the window slides forward and old
    /// entries are cleared.
    private func isDuplicateSeqNum(_ seqNum: UInt16) -> Bool {
        if !seqBufferInitialized {
            // First packet ever — initialize the window
            seqBufferInitialized = true
            seqBufferBase = seqNum
            seqBuffer = [Bool](repeating: false, count: AudioStreamReceiver.seqBufferSize)
            let idx = Int(seqNum) % AudioStreamReceiver.seqBufferSize
            seqBuffer[idx] = true
            return false
        }

        // Calculate how far ahead this seqnum is from the base.
        // Use signed 16-bit difference to handle wrapping at 65535→0.
        let diff = Int16(bitPattern: seqNum &- seqBufferBase)

        if diff < 0 {
            // Packet is older than our window — definitely a duplicate or very late
            return true
        }

        if diff >= Int16(AudioStreamReceiver.seqBufferSize) {
            // Packet is ahead of our window — slide the window forward.
            // Clear entries that fall out of the new window.
            let slide = Int(diff) - AudioStreamReceiver.seqBufferSize + 1
            for i in 0..<min(slide, AudioStreamReceiver.seqBufferSize) {
                let clearIdx = Int(seqBufferBase &+ UInt16(i)) % AudioStreamReceiver.seqBufferSize
                seqBuffer[clearIdx] = false
            }
            if slide >= AudioStreamReceiver.seqBufferSize {
                // Entire buffer is stale — clear everything
                seqBuffer = [Bool](repeating: false, count: AudioStreamReceiver.seqBufferSize)
            }
            seqBufferBase = seqNum &- UInt16(AudioStreamReceiver.seqBufferSize - 1)
        }

        let idx = Int(seqNum) % AudioStreamReceiver.seqBufferSize
        if seqBuffer[idx] {
            // Already processed this seqnum
            return true
        }

        seqBuffer[idx] = true
        return false
    }

    // MARK: - Decryption

    /// Decrypts audio data using AES-128-CBC per-packet.
    /// Each packet is independently decrypted with the same key and IV.
    /// Only the first N*16 bytes are decrypted (AES block size); any trailing
    /// bytes shorter than a block are passed through in the clear.
    private func decryptAudio(data: Data) -> Data {
        guard let key = decryptKey, let iv = decryptIV, !data.isEmpty else { return data }

        // AES-CBC decrypts in 16-byte blocks; trailing bytes pass through
        let blockSize = kCCBlockSizeAES128
        let encryptedLength = (data.count / blockSize) * blockSize

        guard encryptedLength > 0 else { return data }

        // Allocate output buffer (CBC with no padding: output == input length)
        var outBuffer = [UInt8](repeating: 0, count: encryptedLength + blockSize)
        var outMoved: size_t = 0

        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),  // no padding — we handle block alignment ourselves
                        keyPtr.baseAddress,
                        key.count,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress,
                        encryptedLength,
                        &outBuffer,
                        outBuffer.count,
                        &outMoved
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            if packetCount <= 5 {
                logger.error("Audio AES-CBC decrypt failed: \(status)")
            }
            return data
        }

        // Combine decrypted blocks + clear trailing bytes
        var result = Data(outBuffer.prefix(outMoved))
        if encryptedLength < data.count {
            result.append(data.suffix(from: data.startIndex + encryptedLength))
        }
        return result
    }

    // MARK: - Key Derivation

    /// Derives the audio AES key using SHA-512:
    ///   key = SHA-512(fairplayKey[16] || ecdhSecret[32])[0..15]
    /// UxPlay's sha_init() uses EVP_sha512() despite misleading comments saying "sha-256".
    /// The video key derivation also uses SHA-512 (with streamConnectionID), so both
    /// audio and video use SHA-512 — audio just uses a simpler single-hash derivation.
    private func deriveAudioKey(fairplayKey: Data, ecdhSecret: Data) -> Data {
        var hasher = SHA512()
        hasher.update(data: fairplayKey)
        hasher.update(data: ecdhSecret)
        return Data(hasher.finalize().prefix(16))
    }
}
