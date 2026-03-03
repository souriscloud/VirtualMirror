import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

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

            Text("\u{00A9} 2026 Souris.CLOUD")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Link("bio.souris.cloud", destination: URL(string: "https://bio.souris.cloud")!)
                .font(.system(size: 11))

            Text("Made by Souris")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 8)
        }
        .frame(width: 320, height: 340)
    }
}
