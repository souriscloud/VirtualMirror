import AppKit

/// Tracks the live AirPlay receivers — one per window. Hands out port slots and
/// ephemeral identities, maps windows to their manager (so the command palette
/// and menu bar can act on the focused receiver), and tears receivers down when
/// their window closes.
@MainActor
final class ReceiverRegistry {
    static let shared = ReceiverRegistry()

    /// Upper bound on simultaneous receivers (port slots 0…max-1).
    static let maxReceivers = 8

    private(set) var managers: [AirPlayManager] = []
    private var usedSlots: Set<Int> = []
    private var windowMap: [ObjectIdentifier: AirPlayManager] = [:]
    /// The receiver whose window was most recently key. Commands invoked while
    /// no receiver window is key (the status-bar menu or palette with the app
    /// inactive) act on this one rather than on an arbitrary first receiver.
    private weak var lastFocusedManager: AirPlayManager?
    private var keyObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// Bridge to SwiftUI's `openWindow`, captured when a window appears.
    var openWindowAction: (() -> Void)?

    var canAddReceiver: Bool { managers.count < ReceiverRegistry.maxReceivers }

    private func allocateSlot() -> Int {
        var slot = 0
        while usedSlots.contains(slot) { slot += 1 }
        usedSlots.insert(slot)
        return slot
    }

    /// Creates a manager for a new window. Called once per window from the
    /// window root's `@StateObject` initialiser, so it must not touch published
    /// UI state — registration happens later in `register(_:)`.
    func makeManager() -> AirPlayManager {
        let slot = allocateSlot()
        let name = slot == 0 ? AirPlayConfig.serverName : "\(AirPlayConfig.serverName) \(slot + 1)"
        return AirPlayManager(identity: ReceiverIdentity(slot: slot, name: name))
    }

    func register(_ manager: AirPlayManager) {
        guard !managers.contains(where: { $0 === manager }) else { return }
        managers.append(manager)
    }

    func release(_ manager: AirPlayManager) {
        manager.stop()
        usedSlots.remove(manager.identity.slot)
        managers.removeAll { $0 === manager }
        for (key, value) in windowMap where value === manager {
            if let observer = keyObservers.removeValue(forKey: key) {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        windowMap = windowMap.filter { $0.value !== manager }
        if lastFocusedManager === manager { lastFocusedManager = nil }
    }

    func bind(window: NSWindow, to manager: AirPlayManager) {
        let key = ObjectIdentifier(window)
        windowMap[key] = manager
        if window.isKeyWindow { lastFocusedManager = manager }
        if let old = keyObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(old)
        }
        keyObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak manager] _ in
            MainActor.assumeIsolated { self?.lastFocusedManager = manager }
        }
    }

    func window(for manager: AirPlayManager) -> NSWindow? {
        for (key, value) in windowMap where value === manager {
            return NSApp.windows.first { ObjectIdentifier($0) == key }
        }
        return nil
    }

    /// The receiver whose window is key, else the one most recently key, else
    /// the first.
    var focusedManager: AirPlayManager? {
        if let key = NSApp.keyWindow, let m = windowMap[ObjectIdentifier(key)] { return m }
        if let last = lastFocusedManager, managers.contains(where: { $0 === last }) { return last }
        return managers.first
    }

    /// Opens another receiver window (if under the cap).
    func openNewReceiver() {
        guard canAddReceiver else { NSSound.beep(); return }
        openWindowAction?()
    }

    func stopAll() {
        for manager in managers { manager.stop() }
    }

    /// One-line summary for the menu bar.
    var summary: String {
        if managers.isEmpty { return "No receivers" }
        let mirroring = managers.filter {
            if case .mirroring = $0.state { return true }
            return false
        }.count
        let count = managers.count
        let plural = count == 1 ? "" : "s"
        if mirroring > 0 { return "\(mirroring) mirroring · \(count) receiver\(plural)" }
        return "\(count) receiver\(plural) · idle"
    }
}
