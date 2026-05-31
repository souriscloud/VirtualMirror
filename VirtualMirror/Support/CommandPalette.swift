import SwiftUI
import AppKit

// MARK: - Model

@MainActor
struct CommandItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let shortcut: String?
    let tint: Color
    let action: () -> Void

    init(id: String, icon: String, title: String, subtitle: String? = nil,
         shortcut: String? = nil, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.id = id; self.icon = icon; self.title = title; self.subtitle = subtitle
        self.shortcut = shortcut; self.tint = tint; self.action = action
    }
}

/// Fuzzy subsequence matcher with word-boundary and prefix bonuses.
enum CommandMatcher {
    static func filter(_ items: [CommandItem], query: String) -> [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        var scored: [(CommandItem, Int)] = []
        for item in items {
            let hay = item.title + " " + (item.subtitle ?? "")
            if let s = score(needle: q, haystack: hay, title: item.title) {
                scored.append((item, s))
            }
        }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    private static func score(needle: String, haystack: String, title: String) -> Int? {
        let n = Array(needle.lowercased())
        let h = Array(haystack.lowercased())
        guard !n.isEmpty, !h.isEmpty else { return nil }

        // Subsequence check.
        var hi = 0, ni = 0
        while ni < n.count, hi < h.count {
            if n[ni] == h[hi] { ni += 1 }
            hi += 1
        }
        guard ni == n.count else { return nil }

        var s = 0
        let lowTitle = title.lowercased(), lowNeedle = needle.lowercased()
        if lowTitle.hasPrefix(lowNeedle) { s += 200 - (title.count - needle.count) }
        else if lowTitle.contains(lowNeedle) { s += 80 }

        var ni2 = 0, hi2 = 0, run = 0
        var prev: Character = " "
        while ni2 < n.count, hi2 < h.count {
            let c = h[hi2]
            if n[ni2] == c {
                run += 1; s += 1
                if hi2 == 0 || prev == " " || prev == "-" { s += 6 }
                s += min(run, 5)
                ni2 += 1
            } else { run = 0 }
            prev = c; hi2 += 1
        }
        return s - h.count / 32
    }

    static func matchedRanges(in title: String, needle: String) -> [Range<String.Index>] {
        let q = needle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let lower = title.lowercased()
        var ranges: [Range<String.Index>] = []
        var ti = lower.startIndex, qi = q.startIndex
        while qi < q.endIndex, ti < lower.endIndex {
            if lower[ti] == q[qi] {
                ranges.append(ti..<lower.index(after: ti))
                qi = q.index(after: qi)
            }
            ti = lower.index(after: ti)
        }
        return qi == q.endIndex ? ranges : []
    }
}

@MainActor
final class CommandPaletteModel: ObservableObject {
    let items: [CommandItem]
    @Published var query = ""
    @Published var selectionIndex = 0

    init(items: [CommandItem]) { self.items = items }

    var filtered: [CommandItem] { CommandMatcher.filter(items, query: query) }

    func selected() -> CommandItem? {
        let list = filtered
        guard !list.isEmpty else { return nil }
        return list[max(0, min(selectionIndex, list.count - 1))]
    }

    func move(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { selectionIndex = 0; return }
        selectionIndex = max(0, min(count - 1, selectionIndex + delta))
    }
}

// MARK: - View

struct CommandPaletteView: View {
    @ObservedObject var model: CommandPaletteModel
    let onExecute: (CommandItem) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                TextField("Type a command…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .onSubmit { if let i = model.selected() { onExecute(i) } }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.filtered.enumerated()), id: \.element.id) { idx, item in
                            CommandRow(item: item, isSelected: idx == model.selectionIndex, query: model.query)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectionIndex = idx; onExecute(item) }
                                .onHover { if $0 { model.selectionIndex = idx } }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 320)
                .onChange(of: model.selectionIndex) { _, new in
                    guard new < model.filtered.count else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(model.filtered[new].id, anchor: .center)
                    }
                }
                .overlay {
                    if model.filtered.isEmpty {
                        Text("No matches")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            Divider().opacity(0.4)

            HStack(spacing: 14) {
                hint("↩", "Run"); hint("↑↓", "Navigate"); hint("⎋", "Close")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        .onAppear { searchFocused = true }
        .onChange(of: model.query) { _, _ in model.selectionIndex = 0 }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.18)))
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(item.tint.opacity(0.18)).frame(width: 28, height: 28)
                Image(systemName: item.icon).font(.system(size: 13, weight: .medium)).foregroundStyle(item.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                highlighted.font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let sub = item.subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.18)))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? item.tint.opacity(0.22) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? item.tint.opacity(0.4) : .clear, lineWidth: 0.75))
    }

    private var highlighted: Text {
        let ranges = CommandMatcher.matchedRanges(in: item.title, needle: query)
        if ranges.isEmpty { return Text(item.title) }
        var out = AttributedString(item.title)
        for r in ranges {
            if let lo = AttributedString.Index(r.lowerBound, within: out),
               let hi = AttributedString.Index(r.upperBound, within: out) {
                out[lo..<hi].foregroundColor = item.tint
                out[lo..<hi].font = .system(size: 14, weight: .bold)
            }
        }
        return Text(out)
    }
}

// MARK: - Controller (floating NSPanel + keyboard navigation)

@MainActor
final class CommandPaletteController {
    static let shared = CommandPaletteController()

    private var panel: NSPanel?
    private var model: CommandPaletteModel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { present() }
    }

    private func present() {
        let model = CommandPaletteModel(items: CommandRegistry.items())
        self.model = model

        let view = CommandPaletteView(model: model, onExecute: { [weak self] item in self?.execute(item) })
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: 640, height: 430)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear

        let panel = self.panel ?? makePanel()
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 640, height: 430))
        centerOverKeyWindow(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        installMonitors()
    }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        model = nil
    }

    private func execute(_ item: CommandItem) {
        dismiss()
        DispatchQueue.main.async { item.action() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func centerOverKeyWindow(_ panel: NSPanel) {
        let host = NSApp.windows.first(where: { $0.isVisible && $0 !== panel && $0.contentView != nil && !($0 is NSPanel) })
        let frame = (host?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 640, height: 430)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + 80, width: size.width, height: size.height), display: true)
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 53: self.dismiss(); return nil                      // esc
            case 125: self.model?.move(by: 1); return nil            // down
            case 126: self.model?.move(by: -1); return nil           // up
            case 36, 76:                                              // return
                if let i = self.model?.selected() { self.execute(i) }
                return nil
            case 40 where event.modifierFlags.contains(.command):    // ⌘K toggles closed
                self.dismiss(); return nil
            default: return event
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }
}

// MARK: - Command registry

@MainActor
enum CommandRegistry {
    static func items() -> [CommandItem] {
        let registry = ReceiverRegistry.shared
        let manager = registry.focusedManager
        var out: [CommandItem] = []

        if registry.canAddReceiver {
            out.append(CommandItem(id: "new-receiver", icon: "plus.rectangle.on.rectangle",
                                   title: "New Receiver", subtitle: "Open another AirPlay receiver", tint: .blue) {
                registry.openNewReceiver()
            })
        }

        if let manager {
            if case .mirroring = manager.state {
                out.append(CommandItem(id: "mute", icon: manager.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                       title: manager.isMuted ? "Unmute Audio" : "Mute Audio",
                                       subtitle: manager.displayName, tint: .blue) {
                    manager.volume = manager.isMuted ? 1 : 0
                })
            }
            out.append(CommandItem(id: "restart", icon: "arrow.clockwise", title: "Restart This Receiver",
                                   subtitle: manager.displayName, tint: .orange) {
                manager.restart()
            })
            out.append(CommandItem(id: "close", icon: "xmark.rectangle", title: "Close This Receiver",
                                   subtitle: manager.displayName, tint: .red) {
                registry.window(for: manager)?.performClose(nil)
            })
        }

        out.append(CommandItem(id: "updates", icon: "arrow.triangle.2.circlepath", title: "Check for Updates…", tint: .green) {
            AppDelegate.shared?.commandCheckForUpdates()
        })
        out.append(CommandItem(id: "help", icon: "questionmark.circle", title: "VirtualMirror Help",
                               shortcut: nil, tint: .blue) {
            HelpWindowController.shared.showWindow()
        })
        out.append(CommandItem(id: "feedback", icon: "exclamationmark.bubble", title: "Send Feedback…",
                               subtitle: "Report a bug or request a feature", tint: .blue) {
            FeedbackWindowController.shared.showWindow()
        })
        out.append(CommandItem(id: "about", icon: "info.circle", title: "About VirtualMirror", tint: .gray) {
            AboutWindowController.shared.showWindow()
        })
        out.append(CommandItem(id: "kofi", icon: "cup.and.saucer.fill", title: "Support on Ko-fi",
                               subtitle: "ko-fi.com/souriscloud", tint: .pink) {
            NSWorkspace.shared.open(GitHubFeedback.kofiURL)
        })
        out.append(CommandItem(id: "source", icon: "chevron.left.forwardslash.chevron.right", title: "View Source on GitHub", tint: .purple) {
            NSWorkspace.shared.open(GitHubFeedback.repoURL)
        })
        out.append(CommandItem(id: "quit", icon: "power", title: "Quit VirtualMirror", shortcut: "⌘Q", tint: .red) {
            NSApp.terminate(nil)
        })
        return out
    }
}
