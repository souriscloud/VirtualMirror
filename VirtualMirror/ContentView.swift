import SwiftUI

struct ContentView: View {
    @EnvironmentObject var airPlayManager: AirPlayManager

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            switch airPlayManager.state {
            case .idle:
                VStack(spacing: 16) {
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    Text("Waiting for AirPlay connection...")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("Open Control Center on your iPhone\nand tap Screen Mirroring")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

            case .connecting(let deviceName):
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Connecting to \(deviceName)...")
                        .font(.title3)
                        .foregroundColor(.white)
                }

            case .mirroring(_):
                MirroringView(airPlayManager: airPlayManager)

            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    Text(message)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        airPlayManager.restart()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 400)
        .onAppear {
            airPlayManager.start()
        }
    }
}

// MARK: - Mirroring View with Volume Overlay

/// Wraps the video display and a hover-activated volume control overlay.
struct MirroringView: View {
    @ObservedObject var airPlayManager: AirPlayManager
    @State private var isHovering = false
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoDisplayView(videoDecoder: airPlayManager.videoDecoder)

            if showControls {
                VolumeOverlay(volume: $airPlayManager.volume)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls = true
                }
                scheduleHide()
            } else {
                scheduleHide(delay: 1.0)
            }
        }
    }

    private func scheduleHide(delay: TimeInterval = 3.0) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Only hide if the mouse has left
            if !isHovering {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Volume Overlay

/// A semi-transparent floating volume control bar.
struct VolumeOverlay: View {
    @Binding var volume: Float

    private var volumeIcon: String {
        if volume <= 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    volume = volume > 0 ? 0 : 1
                }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(volume) },
                set: { volume = Float($0) }
            ), in: 0...1)
            .tint(.white)
            .frame(width: 140)

            Text("\(Int(volume * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
        .padding(.bottom, 16)
    }
}
