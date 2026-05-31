import SwiftUI
import AppKit

/// Lightweight feedback / bug-report form. Composes a pre-filled GitHub issue
/// and opens it in the browser — the user reviews and submits with their own
/// account. A "Copy report" fallback covers anyone without GitHub.
struct FeedbackView: View {
    var onClose: () -> Void

    @State private var kind: FeedbackKind = .bug
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var includeDiagnostics = true
    @State private var copied = false

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(.tint)
                Text("Send feedback").font(.title3.weight(.semibold))
            }

            Picker("", selection: $kind) {
                ForEach(FeedbackKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            ZStack(alignment: .topLeading) {
                if details.isEmpty {
                    Text(kind.placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $details)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
            }
            .frame(height: 150)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            Toggle(isOn: $includeDiagnostics) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Include app & system info").font(.callout)
                    Text(GitHubFeedback.diagnostics())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Text("This opens a pre-filled GitHub issue in your browser — review and submit it there. No account? Use Copy report and send it however you like.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    let text = "\(kind.titlePrefix)\(title)\n\n" + GitHubFeedback.reportText(body: details, includeDiagnostics: includeDiagnostics)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button {
                    if let url = GitHubFeedback.issueURL(kind: kind, title: title, body: details, includeDiagnostics: includeDiagnostics) {
                        NSWorkspace.shared.open(url)
                    }
                    onClose()
                } label: {
                    Label("Open in GitHub", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
