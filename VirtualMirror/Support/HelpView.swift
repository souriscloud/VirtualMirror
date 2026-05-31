import SwiftUI

/// In-app Help: a small documentation browser. A topic sidebar on the left,
/// rich formatted content on the right. Intentionally self-contained (no web
/// view) so it works offline and matches the app's chrome.
struct HelpView: View {
    // List selection must be Optional to bind reliably; fall back to .welcome.
    @State private var selection: HelpTopic? = .welcome
    private var topic: HelpTopic { selection ?? .welcome }

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { t in
                Label(t.title, systemImage: t.icon)
                    .tag(t)
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 208, max: 240)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    topic.content
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(topic)   // reset scroll on topic change
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: - Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case welcome, mirroring, audio, shortcuts, troubleshooting, updates, privacy, support
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:         return "Welcome"
        case .mirroring:       return "Start Mirroring"
        case .audio:           return "Audio & Volume"
        case .shortcuts:       return "Command Palette & Shortcuts"
        case .troubleshooting: return "Troubleshooting"
        case .updates:         return "Updates"
        case .privacy:         return "Privacy & Security"
        case .support:         return "Support & Feedback"
        }
    }

    var icon: String {
        switch self {
        case .welcome:         return "sparkles"
        case .mirroring:       return "iphone.gen3"
        case .audio:           return "speaker.wave.2.fill"
        case .shortcuts:       return "command"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .updates:         return "arrow.triangle.2.circlepath"
        case .privacy:         return "lock.shield"
        case .support:         return "heart"
        }
    }

    @ViewBuilder var content: some View {
        switch self {
        case .welcome:         HelpWelcome()
        case .mirroring:       HelpMirroring()
        case .audio:           HelpAudio()
        case .shortcuts:       HelpShortcuts()
        case .troubleshooting: HelpTroubleshooting()
        case .updates:         HelpUpdates()
        case .privacy:         HelpPrivacy()
        case .support:         HelpSupport()
        }
    }
}

// MARK: - Reusable building blocks

/// Section title with a tinted icon.
private struct HelpHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title).font(.system(size: 24, weight: .bold))
            }
            if let subtitle {
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}

/// One feature row: icon, bold lead, explanation.
private struct HelpPoint: View {
    let icon: String
    let lead: String
    let body_: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(lead).font(.headline)
                Text(body_).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A numbered step row.
private struct StepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
            Text(text).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
    }
}

private func Para(_ text: String) -> some View {
    Text(text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

/// A keyboard-shortcut row: keys as chips, then what it does.
private struct ShortcutRow: View {
    let keys: [String]
    let label: String
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { k in
                    Text(k)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.separator))
                        )
                }
            }
            .frame(width: 96, alignment: .leading)
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Topic content

private struct HelpWelcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "sparkles", title: "Welcome to VirtualMirror",
                       subtitle: "AirPlay screen mirroring for your Mac.")
            Para("VirtualMirror turns your Mac into an AirPlay receiver — mirror an iPhone or iPad screen to a native window, no Apple TV required. It runs quietly in the menu bar and shows live connection status.")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "iphone.gen3", lead: "Mirror any iPhone or iPad",
                          body_: "Pick VirtualMirror from Screen Mirroring in Control Center and your device appears in a window on the Mac.")
                HelpPoint(icon: "bolt.fill", lead: "Low latency",
                          body_: "Hardware-accelerated H.264 decoding via VideoToolbox keeps the picture smooth and responsive.")
                HelpPoint(icon: "speaker.wave.2.fill", lead: "Audio included",
                          body_: "Full audio passthrough with a volume slider — not just the picture.")
                HelpPoint(icon: "menubar.arrow.up.rectangle", lead: "Lives in the menu bar",
                          body_: "Closing the window hides the app; it keeps receiving from the menu bar until you quit.")
                HelpPoint(icon: "command", lead: "Command Palette (⌘K)",
                          body_: "Press ⌘K anywhere for a searchable list of every action. A live status footer shows resolution, frame rate, and session time while mirroring.")
            }
            Text("Pick a topic on the left to dig in.")
                .font(.callout).foregroundStyle(.tertiary).padding(.top, 4)
        }
    }
}

private struct HelpMirroring: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "iphone.gen3", title: "Start Mirroring")
            Para("Make sure your iPhone/iPad and this Mac are on the same Wi-Fi network, then:")
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Launch VirtualMirror — it appears in the menu bar and shows a waiting screen.")
                StepRow(number: 2, text: "On your iPhone or iPad, open Control Center.")
                StepRow(number: 3, text: "Tap Screen Mirroring.")
                StepRow(number: 4, text: "Select VirtualMirror from the list.")
                StepRow(number: 5, text: "Your device screen appears in the VirtualMirror window.")
            }
            HelpPoint(icon: "rotate.right", lead: "Rotation & lock",
                      body_: "VirtualMirror handles device rotation and lock/unlock seamlessly — the stream resumes on its own.")
            HelpPoint(icon: "stop.circle", lead: "Stop mirroring",
                      body_: "Tap Screen Mirroring → Stop Mirroring on your device, or just disconnect. VirtualMirror returns to the waiting screen.")
        }
    }
}

private struct HelpAudio: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "speaker.wave.2.fill", title: "Audio & Volume")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "speaker.wave.2.fill", lead: "Audio passthrough",
                          body_: "Sound from the mirrored device plays through your Mac's current output.")
                HelpPoint(icon: "slider.horizontal.3", lead: "Volume slider",
                          body_: "Hover over the mirroring window to reveal the volume slider.")
                HelpPoint(icon: "speaker.slash.fill", lead: "Mute",
                          body_: "Click the speaker icon next to the slider to mute or unmute.")
            }
        }
    }
}

private struct HelpShortcuts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "command", title: "Command Palette & Shortcuts",
                       subtitle: "Everything VirtualMirror does, one keystroke away.")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "command", lead: "Command Palette (⌘K)",
                          body_: "Press ⌘K for a searchable list of every action — show/hide the window, mute, restart AirPlay, check for updates, open Help or Feedback, and quit. Type to filter, ↑/↓ to move, ↩ to run, ⎋ to close.")
                HelpPoint(icon: "rectangle.bottomthird.inset.filled", lead: "Connectivity footer",
                          body_: "The strip along the bottom of the window shows live status: the connected device, and while mirroring the resolution, frame rate, session time, and a mute indicator.")
            }
            VStack(alignment: .leading, spacing: 10) {
                ShortcutRow(keys: ["⌘", "K"], label: "Open the Command Palette")
                ShortcutRow(keys: ["⌘", "?"], label: "Open VirtualMirror Help")
                ShortcutRow(keys: ["⌘", "W"], label: "Hide the window (keeps running in the menu bar)")
                ShortcutRow(keys: ["⌘", "Q"], label: "Quit VirtualMirror")
            }
        }
    }
}

private struct HelpTroubleshooting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "wrench.and.screwdriver", title: "Troubleshooting")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "airplayvideo", lead: "VirtualMirror isn't in the list",
                          body_: "macOS has its own built-in AirPlay Receiver. If it's on, your device may connect to it instead. Turn it off in System Settings → General → AirDrop & Handoff → AirPlay Receiver.")
                HelpPoint(icon: "wifi", lead: "Won't connect or keeps dropping",
                          body_: "Confirm both devices are on the same Wi-Fi network. Restart VirtualMirror (Quit from the menu bar, then relaunch).")
                HelpPoint(icon: "lock.shield", lead: "Blocked by a firewall",
                          body_: "VirtualMirror listens on port 47000. If you run a firewall, allow incoming connections to it.")
                HelpPoint(icon: "key.fill", lead: "Keychain prompt on first launch",
                          body_: "VirtualMirror stores a cryptographic identity key in the macOS Keychain for AirPlay pairing. The one-time prompt on first launch is expected.")
            }
        }
    }
}

private struct HelpUpdates: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "arrow.triangle.2.circlepath", title: "Updates")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "checkmark.seal", lead: "Automatic update checks",
                          body_: "VirtualMirror checks for new versions on its own using the Sparkle framework, and can install them for you.")
                HelpPoint(icon: "hand.point.up.left", lead: "Check manually",
                          body_: "Click the menu bar icon → Check for Updates… to look right away.")
                HelpPoint(icon: "shippingbox", lead: "Signed & notarized",
                          body_: "Releases are signed and notarized by Apple, and updates are verified before they install.")
            }
        }
    }
}

private struct HelpPrivacy: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "lock.shield", title: "Privacy & Security")
            Para("VirtualMirror is a local AirPlay receiver. The video and audio stream goes straight from your device to this Mac over your network — there's no cloud, no account, and no telemetry.")
            VStack(alignment: .leading, spacing: 14) {
                HelpPoint(icon: "key.fill", lead: "Identity in the Keychain",
                          body_: "The cryptographic key that identifies this receiver to your devices is stored in the macOS Keychain.")
                HelpPoint(icon: "lock.fill", lead: "Encrypted pairing",
                          body_: "Connections use the standard AirPlay pairing and FairPlay handshake; the mirror stream is decrypted only on this Mac.")
                HelpPoint(icon: "checkmark.shield", lead: "Diagnostics stay minimal",
                          body_: "If you send feedback with system info, it includes only the app version, macOS version, and CPU type — never device names or network details.")
            }
        }
    }
}

private struct HelpSupport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HelpHeader(icon: "heart.fill", title: "Support & Feedback")
            Para("VirtualMirror is free and open source, built by one person. Bug reports and ideas genuinely shape it — and if it saves you time, a coffee keeps it going.")
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    FeedbackWindowController.shared.showWindow()
                } label: {
                    Label("Send feedback or report a bug…", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.borderedProminent)

                Link(destination: GitHubFeedback.repoURL) {
                    Label("VirtualMirror on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: GitHubFeedback.kofiURL) {
                    Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                }
                .tint(.pink)
            }
            Text("VirtualMirror \(GitHubFeedback.appVersion) (build \(GitHubFeedback.appBuild))")
                .font(.footnote).foregroundStyle(.tertiary).padding(.top, 6)
        }
    }
}
