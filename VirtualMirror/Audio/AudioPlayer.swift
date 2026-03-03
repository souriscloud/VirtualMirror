import Foundation
import AVFoundation
import os

/// Plays decoded PCM audio through the default audio output using AVAudioEngine.
class AudioPlayer {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AudioPlayer")
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var isRunning = false

    /// Volume level (0.0 = silent, 1.0 = full). Applied to the player node.
    var volume: Float = 1.0 {
        didSet {
            playerNode?.volume = volume
        }
    }

    func configure(sampleRate: Double, channels: UInt32) {
        // Clean up any previous engine
        stop()

        // Use non-interleaved float32 to match AudioDecoder output
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            logger.error("Failed to create audio format: sr=\(sampleRate) ch=\(channels)")
            return
        }

        self.audioFormat = format

        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()

        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)

        do {
            try eng.start()
            node.volume = volume
            node.play()
            self.engine = eng
            self.playerNode = node
            isRunning = true
            logger.info("Audio player started: \(sampleRate) Hz, \(channels) ch, volume=\(self.volume)")
        } catch {
            logger.error("Failed to start audio engine: \(error)")
        }
    }

    /// Enqueues a buffer of decoded non-interleaved float32 PCM samples for playback.
    /// Data layout: [ch0_frame0, ch0_frame1, ...ch0_frameN, ch1_frame0, ...ch1_frameN]
    func play(pcmData: Data) {
        guard isRunning, let format = audioFormat, let playerNode = playerNode else { return }

        let channels = Int(format.channelCount)
        let framesPerChannel = pcmData.count / (channels * MemoryLayout<Float>.size)
        guard framesPerChannel > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(framesPerChannel)) else {
            return
        }
        buffer.frameLength = UInt32(framesPerChannel)

        // Copy non-interleaved float32 data into the buffer's per-channel pointers
        pcmData.withUnsafeBytes { src in
            guard let floatData = buffer.floatChannelData else { return }
            let srcFloat = src.bindMemory(to: Float.self)
            let bytesPerChannel = framesPerChannel * MemoryLayout<Float>.size
            for ch in 0..<channels {
                let chOffset = ch * framesPerChannel
                memcpy(floatData[ch], srcFloat.baseAddress! + chOffset, bytesPerChannel)
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        if isRunning {
            playerNode?.stop()
            engine?.stop()
            playerNode = nil
            engine = nil
            isRunning = false
            logger.info("Audio player stopped")
        }
    }

    deinit {
        stop()
    }
}
