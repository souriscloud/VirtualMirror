import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    @State private var showAcknowledgments = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 8)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text("VirtualMirror")
                .font(.system(size: 24, weight: .bold))

            Text("AirPlay Screen Mirroring Receiver")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Version \(version) (\(build))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text("Licensed under GPL-3.0")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("\u{00A9} 2026 Souris.CLOUD")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("bio.souris.cloud", destination: URL(string: "https://bio.souris.cloud")!)
                    .font(.system(size: 11))

                Link("Source Code", destination: URL(string: "https://github.com/souriscloud/VirtualMirror")!)
                    .font(.system(size: 11))
            }

            Button("Acknowledgments") {
                showAcknowledgments = true
            }
            .font(.system(size: 11))
            .buttonStyle(.link)

            Text("Made by Souris")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 8)
        }
        .frame(width: 320, height: 380)
        .sheet(isPresented: $showAcknowledgments) {
            AcknowledgmentsView()
        }
    }
}

struct AcknowledgmentsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Acknowledgments")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AckSection(
                        title: "FairPlay DRM",
                        description: "FairPlay decryption code derived from the playfair library by EstebanKubata — a reverse-engineering of Apple's FairPlay authentication protocol.",
                        license: "GPL"
                    )

                    AckSection(
                        title: "UxPlay",
                        description: "AirPlay protocol implementation informed by UxPlay, an open-source AirPlay mirror server for Unix by antimof.",
                        license: "GPL-3.0",
                        url: "https://github.com/antimof/UxPlay"
                    )

                    AckSection(
                        title: "shairplay",
                        description: "AirPlay/RAOP protocol reference implementation by Juho Vaha-Herttua.",
                        license: "LGPL-2.1",
                        url: "https://github.com/juhovh/shairplay"
                    )

                    AckSection(
                        title: "RPiPlay",
                        description: "AirPlay mirror server for Raspberry Pi by FD-.",
                        license: "GPL-3.0",
                        url: "https://github.com/FD-/RPiPlay"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Divider()

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(.vertical, 10)
        }
        .frame(width: 360, height: 380)
    }
}

private struct AckSection: View {
    let title: String
    let description: String
    let license: String
    var url: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(license)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            if let url = url, let link = URL(string: url) {
                Link(url.replacingOccurrences(of: "https://", with: ""), destination: link)
                    .font(.system(size: 10))
            }
        }
    }
}
