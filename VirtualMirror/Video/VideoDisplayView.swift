import SwiftUI
import AVFoundation
import CoreMedia
import os

struct VideoDisplayView: NSViewRepresentable {
    @ObservedObject var videoDecoder: VideoDecoder

    func makeNSView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        return view
    }

    func updateNSView(_ nsView: VideoLayerView, context: Context) {
        if let sampleBuffer = videoDecoder.latestSampleBuffer {
            nsView.enqueueSampleBuffer(sampleBuffer)
        }
    }
}

class VideoLayerView: NSView {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "VideoDisplay")
    private var displayLayer: AVSampleBufferDisplayLayer!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor.black

        layer?.addSublayer(displayLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            logger.warning("Display layer failed (error=\(String(describing: self.displayLayer.error))), recovering")
            displayLayer.flushAndRemoveImage()
        }

        displayLayer.enqueue(sampleBuffer)
    }

    func flush() {
        displayLayer.flush()
    }
}
