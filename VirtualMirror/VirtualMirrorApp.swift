import SwiftUI
import Combine
import Sparkle

@main
struct VirtualMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var airPlayManager = AirPlayManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(airPlayManager)
                .onAppear {
                    appDelegate.airPlayManager = airPlayManager
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 400, height: 720)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var showHideMenuItem: NSMenuItem!
    private var cancellable: AnyCancellable?
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var airPlayManager: AirPlayManager? {
        didSet { observeState() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Hide dock icon — app lives in the menu bar
        // (Commented out: keeping dock icon so window management works naturally)
        // NSApp.setActivationPolicy(.accessory)

        // Intercept window close to hide instead of quit
        DispatchQueue.main.async {
            for window in NSApp.windows where window.contentView != nil {
                window.delegate = self
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "airplayvideo", accessibilityDescription: "VirtualMirror")
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Idle — Waiting for connection", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        showHideMenuItem = NSMenuItem(title: "Show Window", action: #selector(toggleWindow), keyEquivalent: "")
        showHideMenuItem.target = self
        menu.addItem(showHideMenuItem)

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

        let aboutItem = NSMenuItem(title: "About VirtualMirror...", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit VirtualMirror", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observeState() {
        guard let manager = airPlayManager else { return }
        cancellable = manager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusMenu(state: state)
            }
    }

    private func updateStatusMenu(state: AirPlayState) {
        switch state {
        case .idle:
            statusMenuItem.title = "Idle — Waiting for connection"
        case .connecting(let name):
            statusMenuItem.title = "Connected: \(name)"
        case .mirroring(let name):
            statusMenuItem.title = "Mirroring: \(name)"
        case .error(let msg):
            statusMenuItem.title = "Error: \(msg)"
        }
    }

    // MARK: - Actions

    private weak var mainWindow: NSWindow?

    @objc private func toggleWindow() {
        // Lazily capture the main window reference on first use
        if mainWindow == nil {
            mainWindow = NSApp.windows.first(where: {
                $0.contentView != nil && !($0 is NSPanel)
            })
        }

        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        for window in NSApp.windows where window.contentView != nil {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        AboutWindowController.shared.showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Window Delegate (Close → Hide)

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        showHideMenuItem?.title = "Hide Window"
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            let anyVisible = NSApp.windows.contains { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
            if !anyVisible {
                self?.showHideMenuItem?.title = "Show Window"
            }
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
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
