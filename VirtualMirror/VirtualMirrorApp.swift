import SwiftUI
import Sparkle

@main
struct VirtualMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "receiver") {
            ReceiverWindowRoot()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 400, height: 720)
        .commands {
            // One About: route the standard app-menu item to our custom panel.
            CommandGroup(replacing: .appInfo) {
                Button("About VirtualMirror") {
                    AboutWindowController.shared.showWindow()
                }
            }
            // Replace the default "New Window" with "New Receiver".
            CommandGroup(replacing: .newItem) {
                Button("New Receiver") {
                    ReceiverRegistry.shared.openNewReceiver()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Command Palette…") {
                    CommandPaletteController.shared.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            // Replace the default Help menu (with its search field) with ours.
            CommandGroup(replacing: .help) {
                Button("VirtualMirror Help") {
                    HelpWindowController.shared.showWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
                Button("Send Feedback…") {
                    FeedbackWindowController.shared.showWindow()
                }
            }
        }
    }
}

// MARK: - Receiver Window Root

/// Root view for one receiver window. Owns a single AirPlayManager with its own
/// identity/port slot from the registry, sets the window title to the receiver
/// name, and binds the window so focus-aware commands can find this receiver.
struct ReceiverWindowRoot: View {
    @StateObject private var manager = ReceiverRegistry.shared.makeManager()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environmentObject(manager)
            .navigationTitle(manager.displayName)
            .background(WindowBinder(manager: manager))
            .onAppear {
                ReceiverRegistry.shared.register(manager)
                ReceiverRegistry.shared.openWindowAction = { openWindow(id: "receiver") }
            }
            .onDisappear {
                ReceiverRegistry.shared.release(manager)
            }
    }
}

/// Grabs the host NSWindow so the registry can map it to its receiver (for
/// focus-aware commands) and pins window tabbing off.
private struct WindowBinder: NSViewRepresentable {
    let manager: AirPlayManager
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingMode = .disallowed
            ReceiverRegistry.shared.bind(window: window, to: manager)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Windows are fine, tabs are not. This must run BEFORE the WindowGroup
        // creates its window — otherwise the tab bar is already baked in and a
        // later `tabbingMode = .disallowed` won't remove it.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusItem()
    }

    /// Stay alive in the menu bar even when every receiver window is closed —
    /// you reopen one with New Receiver (⌘N) or the command palette.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { ReceiverRegistry.shared.openNewReceiver() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ReceiverRegistry.shared.stopAll()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: "VirtualMirror")
        }

        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "No receivers", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let newItem = NSMenuItem(title: "New Receiver", action: #selector(newReceiver), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        let paletteItem = NSMenuItem(title: "Command Palette…", action: #selector(showCommandPalette), keyEquivalent: "k")
        paletteItem.target = self
        menu.addItem(paletteItem)

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

        let helpItem = NSMenuItem(title: "VirtualMirror Help", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let feedbackItem = NSMenuItem(title: "Send Feedback...", action: #selector(showFeedback), keyEquivalent: "")
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        let aboutItem = NSMenuItem(title: "About VirtualMirror...", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VirtualMirror", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func newReceiver() { ReceiverRegistry.shared.openNewReceiver() }
    @objc private func showAbout() { AboutWindowController.shared.showWindow() }
    @objc private func showHelp() { HelpWindowController.shared.showWindow() }
    @objc private func showFeedback() { FeedbackWindowController.shared.showWindow() }
    @objc private func showCommandPalette() { CommandPaletteController.shared.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Bring a specific receiver's window to the front (status-menu list).
    @objc private func focusReceiver(_ sender: NSMenuItem) {
        guard let manager = sender.representedObject as? AirPlayManager,
              let window = ReceiverRegistry.shared.window(for: manager) else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Hook used by the command palette.
    func commandCheckForUpdates() { updaterController.checkForUpdates(nil) }
}

// MARK: - Status menu refresh

extension AppDelegate: NSMenuDelegate {
    private static let receiverRowTag = 0x5245_4356  // 'RECV'

    /// Refresh the status line and the live receiver list each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        let registry = ReceiverRegistry.shared
        statusMenuItem?.title = registry.summary

        // Rebuild the dynamic receiver rows between the status line and the
        // first separator.
        menu.items.removeAll { $0.tag == Self.receiverRowTag }
        guard let statusMenuItem,
              let statusIdx = menu.items.firstIndex(of: statusMenuItem) else { return }
        var at = statusIdx + 1
        for manager in registry.managers {
            let item = NSMenuItem(title: "  \(receiverLabel(manager))",
                                  action: #selector(focusReceiver(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = manager
            item.tag = Self.receiverRowTag
            menu.insertItem(item, at: at)
            at += 1
        }
    }

    private func receiverLabel(_ manager: AirPlayManager) -> String {
        switch manager.state {
        case .idle:        return "\(manager.displayName) — idle"
        case .connecting:  return "\(manager.displayName) — connecting…"
        case .mirroring:   return "\(manager.displayName) — mirroring"
        case .error:       return "\(manager.displayName) — error"
        }
    }
}

// MARK: - About Window Controller

class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingView = NSHostingView(rootView: aboutView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 452)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 452),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "About VirtualMirror"
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

// MARK: - Help Window Controller

@MainActor
class HelpWindowController {
    static let shared = HelpWindowController()
    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: HelpView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "VirtualMirror Help"
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

// MARK: - Feedback Window Controller

@MainActor
class FeedbackWindowController {
    static let shared = FeedbackWindowController()
    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let feedbackView = FeedbackView { [weak self] in
            self?.window?.close()
        }
        let hostingView = NSHostingView(rootView: feedbackView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 460)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "Send Feedback"
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}
