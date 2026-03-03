import Foundation
import VideoToolbox
import CoreMedia
import os

class VideoDecoder: ObservableObject {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "VideoDecoder")

    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var nalLengthSize: Int32 = 4

    // Output: decoded sample buffers for display
    @Published var latestSampleBuffer: CMSampleBuffer?

    /// Resets the decoder state so it can be reconfigured with new codec parameters.
    /// Called when the mirroring session reconnects (e.g. after rotation or lock/unlock).
    func reset() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
        nalLengthSize = 4
        frameCount = 0
        decodeErrorCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.latestSampleBuffer = nil
        }
        logger.info("Decoder reset")
    }

    func configureWithAVCC(_ avccData: Data) {
        // Reset error counter so first errors after codec change are always logged
        decodeErrorCount = 0

        // Parse avcC (ISO 14496-15) format:
        // byte 0: version (1)
        // byte 1: H.264 profile
        // byte 2: profile compatibility
        // byte 3: H.264 level
        // byte 4: NAL unit length size - 1 (masked with 0x03)
        // byte 5: number of SPS (masked with 0x1F)
        // then SPS entries: [2-byte length][SPS data]
        // then: number of PPS
        // then PPS entries: [2-byte length][PPS data]

        guard avccData.count >= 7 else {
            logger.error("avcC data too short: \(avccData.count)")
            return
        }

        let bytes = Array(avccData)
        nalLengthSize = Int32((bytes[4] & 0x03) + 1)
        let numSPS = Int(bytes[5] & 0x1F)

        var offset = 6
        var spsData: [Data] = []
        var ppsData: [Data] = []

        // Parse SPS entries
        for _ in 0..<numSPS {
            guard offset + 2 <= bytes.count else { break }
            let spsLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard offset + spsLength <= bytes.count else { break }
            spsData.append(Data(bytes[offset..<(offset + spsLength)]))
            offset += spsLength
        }

        // Parse PPS entries
        guard offset < bytes.count else { return }
        let numPPS = Int(bytes[offset])
        offset += 1

        for _ in 0..<numPPS {
            guard offset + 2 <= bytes.count else { break }
            let ppsLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            guard offset + ppsLength <= bytes.count else { break }
            ppsData.append(Data(bytes[offset..<(offset + ppsLength)]))
            offset += ppsLength
        }

        guard !spsData.isEmpty, !ppsData.isEmpty else {
            logger.error("No SPS/PPS found in avcC data")
            return
        }

        logger.info("Parsed avcC: \(spsData.count) SPS, \(ppsData.count) PPS, NAL length size: \(self.nalLengthSize)")

        // Create format description from SPS/PPS
        createFormatDescription(sps: spsData[0], pps: ppsData[0])
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        // Destroy existing session
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        // Create CMVideoFormatDescription from SPS/PPS
        var formatDesc: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsPtr in
            pps.withUnsafeBytes { ppsPtr in
                let paramSets: [UnsafePointer<UInt8>] = [
                    spsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let paramSetSizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: paramSets,
                    parameterSetSizes: paramSetSizes,
                    nalUnitHeaderLength: nalLengthSize,
                    formatDescriptionOut: &formatDesc
                )
            }
        }

        guard status == noErr, let desc = formatDesc else {
            logger.error("Failed to create format description: \(status)")
            return
        }

        self.formatDescription = desc
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        logger.info("Video format: \(dimensions.width)x\(dimensions.height)")

        // Create decompression session
        createDecompressionSession(formatDescription: desc)
    }

    private func createDecompressionSession(formatDescription: CMVideoFormatDescription) {
        let decoderConfig: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderConfig as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            logger.error("Failed to create decompression session: \(status)")
            return
        }

        self.decompressionSession = session
        logger.info("Decompression session created")
    }

    private var frameCount = 0
    private var decodeErrorCount = 0

    func decodeVideoData(_ data: Data, timestamp: UInt64) {
        guard let session = decompressionSession, let formatDesc = formatDescription else {
            logger.warning("Decoder not ready (session=\(self.decompressionSession != nil), fmt=\(self.formatDescription != nil)), dropping \(data.count) bytes")
            return
        }

        frameCount += 1

        // The data contains length-prefixed NAL units
        // We need to wrap each in a CMBlockBuffer and create a CMSampleBuffer
        var blockBuffer: CMBlockBuffer?
        let dataCount = data.count

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return }

            status = CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: dataCount
            )

            guard status == kCMBlockBufferNoErr else { return }
        }

        guard let buffer = blockBuffer else {
            logger.error("Failed to create block buffer")
            return
        }

        // Create CMSampleBuffer with current host time for immediate display
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [dataCount],
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sample = sampleBuffer else {
            logger.error("Failed to create sample buffer: \(status)")
            return
        }

        // Decode the frame
        var flagsOut = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flagsOut
        ) { [weak self] status, _, pixelBuffer, presentationTime, _ in
            guard let self = self else { return }
            guard status == noErr, let pixelBuffer = pixelBuffer else {
                if status != noErr {
                    self.decodeErrorCount += 1
                    if self.decodeErrorCount <= 5 || self.decodeErrorCount % 100 == 0 {
                        self.logger.error("Decode error: \(status) (count: \(self.decodeErrorCount))")
                    }
                }
                return
            }
            self.decodeErrorCount = 0

            // Create a new CMSampleBuffer from the decoded pixel buffer for display
            self.createDisplaySampleBuffer(from: pixelBuffer, time: presentationTime)
        }

        if decodeStatus != noErr {
            decodeErrorCount += 1
            if decodeErrorCount <= 5 || decodeErrorCount % 100 == 0 {
                logger.error("VTDecompressionSessionDecodeFrame failed: \(decodeStatus) (count: \(self.decodeErrorCount))")
            }
        }
    }

    private func createDisplaySampleBuffer(from pixelBuffer: CVPixelBuffer, time: CMTime) {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )

        guard let desc = formatDesc else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else { return }

        // Publish on main thread for SwiftUI
        DispatchQueue.main.async { [weak self] in
            self?.latestSampleBuffer = buffer
        }
    }

    deinit {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
    }
}
