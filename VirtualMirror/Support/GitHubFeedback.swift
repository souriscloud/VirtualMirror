import Foundation

enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug, feature, question
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug:      return "Bug"
        case .feature:  return "Feature"
        case .question: return "Question"
        }
    }

    var titlePrefix: String {
        switch self {
        case .bug:      return "[Bug] "
        case .feature:  return "[Feature] "
        case .question: return "[Question] "
        }
    }

    /// Must be a label that exists in the repo, else GitHub shows a notice.
    /// `bug`/`enhancement` are GitHub's defaults; questions get `question`.
    var githubLabel: String? {
        switch self {
        case .bug:      return "bug"
        case .feature:  return "enhancement"
        case .question: return "question"
        }
    }

    var placeholder: String {
        switch self {
        case .bug:
            return "What happened, what you expected, and the steps to reproduce it. Which iPhone/iPad and iOS version, and what you were mirroring, all help."
        case .feature:
            return "What you'd like VirtualMirror to do, and why it'd help."
        case .question:
            return "Ask away — how something works, whether something's possible, etc."
        }
    }
}

/// Builds a pre-filled GitHub "new issue" URL so users can file feedback with
/// their own GitHub account — no token, no backend, no app-side auth. The app
/// only opens the URL; the user reviews and submits on GitHub. A "Copy report"
/// fallback covers anyone without a GitHub account.
enum GitHubFeedback {
    static let repo = "souriscloud/VirtualMirror"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Non-identifying environment line appended to the report. Contains only
    /// app version/build, macOS version, and CPU arch — never device names,
    /// network details, or anything from the keychain.
    static func diagnostics() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return "VirtualMirror \(appVersion) (build \(appBuild)) · macOS \(osStr) · \(arch)"
    }

    /// The full report text (body + optional diagnostics) — used both for the
    /// GitHub URL and the "Copy report" fallback.
    static func reportText(body: String, includeDiagnostics: Bool) -> String {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics {
            text += "\n\n---\n_\(diagnostics())_"
        }
        return text
    }

    static func issueURL(kind: FeedbackKind, title: String, body: String, includeDiagnostics: Bool) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")
        var items = [
            URLQueryItem(name: "title", value: kind.titlePrefix + title.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "body", value: reportText(body: body, includeDiagnostics: includeDiagnostics)),
        ]
        if let label = kind.githubLabel {
            items.append(URLQueryItem(name: "labels", value: label))
        }
        components?.queryItems = items
        return components?.url
    }

    static var issuesListURL: URL? {
        URL(string: "https://github.com/\(repo)/issues")
    }

    static let kofiURL = URL(string: "https://ko-fi.com/souriscloud")!
    static let repoURL = URL(string: "https://github.com/\(repo)")!
}
