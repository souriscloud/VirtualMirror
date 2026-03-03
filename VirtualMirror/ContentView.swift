import SwiftUI

struct ContentView: View {
    @EnvironmentObject var airPlayManager: AirPlayManager
    @AppStorage("hasCompletedFirstLaunch") private var hasCompletedFirstLaunch = false
    @State private var showKeychainExplanation = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if showKeychainExplanation {
                KeychainExplanationView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showKeychainExplanation = false
                        hasCompletedFirstLaunch = true
                    }
                    airPlayManager.start()
                }
            } else {
                switch airPlayManager.state {
                case .idle:
                    IdleView()

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
        }
        .frame(minWidth: 300, minHeight: 400)
        .onAppear {
            if hasCompletedFirstLaunch {
                airPlayManager.start()
            } else {
                showKeychainExplanation = true
            }
        }
    }
}

// MARK: - First-Launch Keychain Explanation

struct KeychainExplanationView: View {
    var onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with subtle glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .opacity(appeared ? 1 : 0)

                Image(systemName: "key.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.8)
            }

            Spacer().frame(height: 28)

            Text("Secure Identity")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Spacer().frame(height: 12)

            Text("VirtualMirror generates a unique cryptographic key to identify itself to your Apple devices during AirPlay pairing.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Spacer().frame(height: 10)

            Text("This key is stored securely in your macOS Keychain. You may see a system prompt asking for permission — this is normal and only happens once.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            Spacer().frame(height: 32)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 15)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Animated Idle View

struct IdleView: View {
    @State private var pulse = false
    @State private var rotateRing = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                // Outer rotating dashed ring
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .blue.opacity(0.0),
                                .blue.opacity(0.3),
                                .cyan.opacity(0.5),
                                .blue.opacity(0.3),
                                .blue.opacity(0.0),
                            ],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(rotateRing ? 360 : 0))

                // Inner pulsing glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(pulse ? 0.25 : 0.1),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 65
                        )
                    )
                    .frame(width: 130, height: 130)

                // AirPlay icon
                Image(systemName: "airplayvideo")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .white.opacity(pulse ? 0.9 : 0.5),
                                .gray.opacity(pulse ? 0.7 : 0.4),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(pulse ? 1.04 : 1.0)
            }

            Text("Waiting for AirPlay connection")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .opacity(appeared ? 1 : 0)

            // Instruction steps
            VStack(spacing: 6) {
                InstructionRow(number: "1", text: "Open Control Center on your iPhone")
                InstructionRow(number: "2", text: "Tap Screen Mirroring")
                InstructionRow(number: "3", text: "Select VirtualMirror")
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            Spacer()
        }
        .onAppear {
            // Breathing pulse
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // Slow ring rotation
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotateRing = true
            }
            // Fade in text
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                appeared = true
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
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
