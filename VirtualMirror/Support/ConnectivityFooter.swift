import SwiftUI

/// Thin status bar pinned to the bottom of the main window. Shows live
/// connectivity: state, device, resolution / fps / session time while
/// mirroring, mute state, and a quiet Ko-fi link.
struct ConnectivityFooter: View {
    @ObservedObject var airPlayManager: AirPlayManager

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            if let device = airPlayManager.state.deviceName {
                Text("·").foregroundStyle(.tertiary)
                Text(device)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if case .mirroring = airPlayManager.state {
                let s = airPlayManager.mirrorStats
                if s.width > 0 {
                    FooterChip(icon: "rectangle.on.rectangle", text: "\(s.width)×\(s.height)")
                }
                FooterChip(icon: "speedometer", text: "\(s.fps) fps")
                if let started = airPlayManager.mirroringStartedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        FooterChip(icon: "clock", text: elapsed(since: started, now: context.date))
                    }
                }
                if airPlayManager.isMuted {
                    FooterChip(icon: "speaker.slash.fill", text: "Muted")
                }
            }

            Spacer(minLength: 8)

            Link(destination: GitHubFeedback.kofiURL) {
                HStack(spacing: 3) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.37, blue: 0.36))
                    Text("Support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("VirtualMirror is free and made by one person — buy me a coffee on Ko-fi ☕")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var stateLabel: String {
        switch airPlayManager.state {
        case .idle:        return "Waiting for connection"
        case .connecting:  return "Connecting…"
        case .mirroring:   return "Mirroring"
        case .error:       return "Error"
        }
    }

    private var statusColor: Color {
        switch airPlayManager.state {
        case .idle:        return .secondary
        case .connecting:  return .yellow
        case .mirroring:   return .green
        case .error:       return .red
        }
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(start)))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// A small icon + monospaced-value chip used in the footer.
private struct FooterChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 2)
    }
}
