import Foundation
import SwiftUI
import Network
import dnssd
import os

enum AirPlayState: Equatable {
    case idle
    case connecting(String)
    case mirroring(String)
    case error(String)

    static func == (lhs: AirPlayState, rhs: AirPlayState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.connecting(let a), .connecting(let b)): return a == b
        case (.mirroring(let a), .mirroring(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var deviceName: String? {
        switch self {
        case .connecting(let name), .mirroring(let name): return name
        default: return nil
        }
    }
}

@MainActor
class AirPlayManager: ObservableObject {
    @Published var state: AirPlayState = .idle
    @Published var volume: Float = 1.0 {
        didSet {
            airPlayServer?.setVolume(volume)
        }
    }

    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayManager")

    // `nonisolated` on purpose: the decoder is fed from the off-main network/
    // decode thread (via MirrorStreamReceiver), so it must be reachable without
    // hopping to the main actor on every frame. VideoDecoder is responsible for
    // its own internal thread-safety.
    nonisolated let videoDecoder = VideoDecoder()
    private var airPlayService: AirPlayService?
    private var airPlayServer: AirPlayServer?

    /// This receiver's identity (name, ports, device ID, signing key). One per
    /// window, so multiple receivers can run side by side. `nonisolated` because
    /// the off-main connection/advertising paths read it; it's immutable apart
    /// from `name`, which guards itself with a lock.
    nonisolated let identity: ReceiverIdentity
    /// Mirrors `identity.name` for SwiftUI (window title, footer). Update via
    /// `rename(to:)` so the Bonjour advertisement and title stay in sync.
    @Published var displayName: String

    init(identity: ReceiverIdentity = ReceiverIdentity(slot: 0, name: AirPlayConfig.serverName)) {
        self.identity = identity
        self.displayName = identity.name
    }

    /// The control connection that currently owns the UI state. Session events
    /// from any other connection (e.g. one being evicted by a newer sender) are
    /// ignored, so a late disconnect can't knock a new session back to idle.
    private var activeSession: UUID?

    /// Watchdog timer that fires if the state stays in `.connecting` too long.
    private var connectingTimeoutTask: Task<Void, Never>?
    /// How long to wait in `.connecting` before reverting to `.idle`.
    private static let connectingTimeout: TimeInterval = 30

    // MARK: - Live mirroring stats (for the connectivity footer)

    /// Resolution and frame rate of the active mirror stream. Polled once a
    /// second from the (off-main) decoder while mirroring.
    struct MirrorStats: Equatable { var width = 0; var height = 0; var fps = 0 }
    @Published var mirrorStats = MirrorStats()
    /// When the current mirroring session began (nil unless mirroring).
    @Published var mirroringStartedAt: Date?
    private var statsTask: Task<Void, Never>?

    var isMuted: Bool { volume <= 0 }

    private func startStatsPolling() {
        statsTask?.cancel()
        mirroringStartedAt = Date()
        statsTask = Task { @MainActor in
            var lastFrames = self.videoDecoder.statsSnapshot().totalFrames
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                let snap = self.videoDecoder.statsSnapshot()
                let fps = max(0, snap.totalFrames - lastFrames)
                lastFrames = snap.totalFrames
                let next = MirrorStats(width: snap.width, height: snap.height, fps: fps)
                if next != self.mirrorStats { self.mirrorStats = next }
            }
        }
    }

    private func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
        if mirrorStats != MirrorStats() { mirrorStats = MirrorStats() }
        mirroringStartedAt = nil
    }

    /// Starts listening and advertising. Idempotent — SwiftUI may call it from
    /// `onAppear` more than once, and a second listener/advertisement would leak.
    func start() {
        guard airPlayServer == nil else { return }
        logger.info("Starting AirPlay services for \"\(self.identity.name)\" on port \(self.identity.ports.airplay)")
        state = .idle

        let port = identity.ports.airplay
        airPlayServer = AirPlayServer(manager: self)
        airPlayServer?.onFailure = { [weak self] error in
            self?.didEncounterError(AirPlayManager.listenerErrorMessage(error, port: port))
        }
        airPlayServer?.start(port: port)

        airPlayService = AirPlayService()
        airPlayService?.onFailure = { [weak self] code in
            self?.didEncounterError(AirPlayManager.bonjourErrorMessage(code))
        }
        airPlayService?.startAdvertising(identity: identity)
    }

    func restart() {
        stop()
        start()
    }

    /// Renames this receiver live. Updates the window title and re-advertises
    /// over Bonjour so iPhones see the new name; any active mirroring session
    /// (on the TCP listener) is unaffected.
    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != identity.name else { return }
        logger.info("Renaming receiver \"\(self.identity.name)\" → \"\(trimmed)\"")
        identity.name = trimmed
        displayName = trimmed
        airPlayService?.updateName(identity: identity)
    }

    func stop() {
        logger.info("Stopping AirPlay services")
        stopServices()
        state = .idle
    }

    private func stopServices() {
        connectingTimeoutTask?.cancel()
        stopStatsPolling()
        activeSession = nil
        airPlayService?.stopAdvertising()
        airPlayServer?.stop()
        airPlayService = nil
        airPlayServer = nil
    }

    // MARK: - Session events (called from connection queues)

    nonisolated func didStartConnecting(session: UUID, deviceName: String) {
        Task { @MainActor in
            if case .error = self.state { return }
            self.activeSession = session
            self.connectingTimeoutTask?.cancel()
            self.stopStatsPolling()
            self.state = .connecting(deviceName)

            // Watchdog — if RECORD never arrives, drop the stuck handshake so the
            // sender gives up cleanly, and go back to waiting.
            self.connectingTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(AirPlayManager.connectingTimeout))
                guard !Task.isCancelled, case .connecting = self.state, self.activeSession == session else { return }
                self.logger.warning("Connecting timeout — closing connection and reverting to idle")
                self.airPlayServer?.closeAllConnections()
                self.activeSession = nil
                self.state = .idle
            }
        }
    }

    nonisolated func didStartMirroring(session: UUID, deviceName: String? = nil) {
        Task { @MainActor in
            if case .error = self.state { return }
            self.activeSession = session
            self.connectingTimeoutTask?.cancel()
            let name = deviceName ?? self.state.deviceName ?? "Unknown"
            self.state = .mirroring(name)
            self.startStatsPolling()
        }
    }

    /// The sender ended the session (a full TEARDOWN) or its control connection
    /// closed. Returns to waiting unless another session has since taken over.
    nonisolated func didEndSession(_ session: UUID) {
        Task { @MainActor in
            guard self.activeSession == nil || self.activeSession == session else { return }
            if case .error = self.state { return }
            self.activeSession = nil
            self.connectingTimeoutTask?.cancel()
            self.stopStatsPolling()
            self.state = .idle
            // The decoder is deliberately not reset here: this runs later, on
            // main, and could wipe a stream the same connection has already set
            // up again. The connection resets it in order on its own queue.
        }
    }

    /// A service-level failure (listener or Bonjour). Stops listening and
    /// advertising so senders don't see a receiver that can't accept them, and
    /// shows the error with a Retry button.
    nonisolated func didEncounterError(_ message: String) {
        Task { @MainActor in
            if case .error = self.state { return }
            self.logger.error("Receiver error: \(message)")
            self.stopServices()
            self.state = .error(message)
        }
    }

    // MARK: - Error messages

    nonisolated static func listenerErrorMessage(_ error: NWError, port: UInt16) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use. Another copy of VirtualMirror or another AirPlay receiver may be running — quit it and click Retry."
        }
        if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            return localNetworkDeniedMessage
        }
        return "Couldn't listen for AirPlay connections on port \(port): \(error.localizedDescription)"
    }

    nonisolated static func bonjourErrorMessage(_ code: DNSServiceErrorType) -> String {
        if code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            return localNetworkDeniedMessage
        }
        return "Couldn't advertise this receiver on the network (Bonjour error \(code))."
    }

    nonisolated static let localNetworkDeniedMessage =
        "VirtualMirror doesn't have Local Network access, so iPhones and iPads can't find it. Allow it in System Settings › Privacy & Security › Local Network, then click Retry."
}
