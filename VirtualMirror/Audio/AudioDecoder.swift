import Foundation
import AudioToolbox
import os

/// Decodes AAC-ELD (or AAC-LC) audio to PCM using AudioToolbox's AudioConverter.
class AudioDecoder {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AudioDecoder")
    private var converter: AudioConverterRef?
    private var outputFormat = AudioStreamBasicDescription()
    private var isConfigured = false
    private var packetCount = 0

    // Temporary storage for the current packet being fed to the converter.
    // Stored as NSData so its .bytes pointer remains valid while AudioConverter
    // reads from it in the C callback (Data.withUnsafeBytes is scope-limited).
    // (fileprivate so the C callback can access it)
    fileprivate var currentPacket: NSData?

    // Packet description for the current AAC frame.
    // AudioConverter needs this for VBR codecs like AAC-ELD to know the packet boundaries.
    // Heap-allocated so the C callback can return a stable pointer that remains valid
    // after the callback scope exits (the old withUnsafeMutablePointer approach returned
    // a dangling pointer, causing garbled audio from corrupted packet descriptions).
    fileprivate let currentPacketDescriptionPtr: UnsafeMutablePointer<AudioStreamPacketDescription> = {
        let ptr = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        ptr.initialize(to: AudioStreamPacketDescription())
        return ptr
    }()

    /// Configures the decoder for the given audio format.
    /// - Parameters:
    ///   - codecType: The audio codec (e.g. kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC)
    ///   - sampleRate: Sample rate in Hz (typically 44100)
    ///   - channels: Number of channels (typically 2)
    ///   - samplesPerFrame: Samples per frame (typically 480 for AAC-ELD, 1024 for AAC-LC)
    func configure(codecType: AudioFormatID, sampleRate: Float64, channels: UInt32, samplesPerFrame: UInt32) {
        // Tear down any existing converter
        if let ref = converter {
            AudioConverterDispose(ref)
            converter = nil
        }

        // Input: compressed AAC
        var inputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: codecType,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: samplesPerFrame,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        // Output: non-interleaved float32 PCM
        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size)
        outputFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var conv: AudioConverterRef?
        let status = AudioConverterNew(&inputFormat, &outputFormat, &conv)

        guard status == noErr, let ref = conv else {
            logger.error("Failed to create AudioConverter: \(status)")
            return
        }

        self.converter = ref
        self.isConfigured = true
        logger.info("Audio decoder configured: codec=\(codecType) sr=\(sampleRate) ch=\(channels) spf=\(samplesPerFrame)")
    }

    /// Decodes a single AAC frame into PCM data.
    /// Returns nil on failure.
    func decode(aacData: Data, samplesPerFrame: UInt32) -> Data? {
        guard isConfigured, let conv = converter else { return nil }

        self.currentPacket = aacData as NSData

        let channels = outputFormat.mChannelsPerFrame
        let bytesPerChannel = Int(samplesPerFrame) * MemoryLayout<Float32>.size
        let totalBytes = Int(channels) * bytesPerChannel

        // Create output buffer list (non-interleaved: one buffer per channel)
        let bufferList = AudioBufferList.allocate(maximumBuffers: Int(channels))
        defer { free(bufferList.unsafeMutablePointer) }

        for i in 0..<Int(channels) {
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bytesPerChannel, alignment: MemoryLayout<Float32>.alignment)
            bufferList[i] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(bytesPerChannel),
                mData: buf
            )
        }

        var ioOutputDataPacketSize = samplesPerFrame

        let status = AudioConverterFillComplexBuffer(
            conv,
            audioDecoderInputDataProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &ioOutputDataPacketSize,
            bufferList.unsafeMutablePointer,
            nil
        )

        self.currentPacket = nil

        guard status == noErr else {
            // Free allocated buffers on error
            for i in 0..<Int(channels) {
                if let data = bufferList[i].mData {
                    data.deallocate()
                }
            }
            if packetCount < 20 {
                logger.error("AudioConverter decode error: \(status) (packet #\(self.packetCount), inputSize=\(aacData.count))")
            }
            packetCount += 1
            return nil
        }

        packetCount += 1

        // Collect PCM from all channel buffers into a contiguous Data
        var pcm = Data(capacity: totalBytes)
        for i in 0..<Int(channels) {
            let actualBytes = Int(bufferList[i].mDataByteSize)
            if let data = bufferList[i].mData {
                pcm.append(Data(bytes: data, count: actualBytes))
                data.deallocate()
            }
        }

        return pcm
    }

    func stop() {
        if let ref = converter {
            AudioConverterDispose(ref)
            converter = nil
        }
        isConfigured = false
        packetCount = 0
    }

    deinit {
        stop()
        currentPacketDescriptionPtr.deinitialize(count: 1)
        currentPacketDescriptionPtr.deallocate()
    }
}

/// C-function callback for AudioConverterFillComplexBuffer.
/// Provides the next packet of compressed AAC data to the converter.
private func audioDecoderInputDataProc(
    _ inAudioConverter: AudioConverterRef,
    _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
    _ ioData: UnsafeMutablePointer<AudioBufferList>,
    _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = inUserData else {
        ioNumberDataPackets.pointee = 0
        return kAudio_ParamError
    }

    let decoder = Unmanaged<AudioDecoder>.fromOpaque(userData).takeUnretainedValue()

    guard let packet = decoder.currentPacket, packet.length > 0 else {
        ioNumberDataPackets.pointee = 0
        return kAudio_ParamError
    }

    ioNumberDataPackets.pointee = 1
    ioData.pointee.mNumberBuffers = 1

    // NSData.bytes is stable for the object's lifetime (unlike Data.withUnsafeBytes)
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: packet.bytes)
    ioData.pointee.mBuffers.mDataByteSize = UInt32(packet.length)
    ioData.pointee.mBuffers.mNumberChannels = 1

    // Provide packet description for VBR codecs (AAC-ELD, AAC-LC).
    // Without this, AudioConverter may not know the packet boundaries.
    if let descPtr = outDataPacketDescription {
        decoder.currentPacketDescriptionPtr.pointee.mStartOffset = 0
        decoder.currentPacketDescriptionPtr.pointee.mVariableFramesInPacket = 0
        decoder.currentPacketDescriptionPtr.pointee.mDataByteSize = UInt32(packet.length)
        descPtr.pointee = decoder.currentPacketDescriptionPtr
    }

    return noErr
}
