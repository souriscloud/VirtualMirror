import Foundation
import SwiftUI
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

    /// Watchdog timer that fires if the state stays in `.connecting` too long.
    private var connectingTimeoutTask: Task<Void, Never>?
    /// How long to wait in `.connecting` before reverting to `.idle`.
    private static let connectingTimeout: TimeInterval = 30

    func start() {
        logger.info("Starting AirPlay services")
        state = .idle

        airPlayServer = AirPlayServer(manager: self)
        airPlayServer?.start(port: AirPlayConfig.airplayPort)

        airPlayService = AirPlayService()
        airPlayService?.startAdvertising(port: Int(AirPlayConfig.airplayPort))
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        logger.info("Stopping AirPlay services")
        airPlayService?.stopAdvertising()
        airPlayServer?.stop()
        airPlayService = nil
        airPlayServer = nil
        state = .idle
    }

    nonisolated func didStartConnecting(deviceName: String) {
        Task { @MainActor in
            self.connectingTimeoutTask?.cancel()
            self.state = .connecting(deviceName)

            // Start watchdog — revert to idle if RECORD never arrives
            self.connectingTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(AirPlayManager.connectingTimeout))
                guard !Task.isCancelled, case .connecting = self.state else { return }
                self.logger.warning("Connecting timeout — reverting to idle")
                self.state = .idle
            }
        }
    }

    nonisolated func didStartMirroring() {
        Task { @MainActor in
            self.connectingTimeoutTask?.cancel()
            let name = self.state.deviceName ?? "Unknown"
            self.state = .mirroring(name)
        }
    }

    nonisolated func didDisconnect() {
        Task { @MainActor in
            self.connectingTimeoutTask?.cancel()
            self.state = .idle
            self.videoDecoder.reset()
        }
    }

    nonisolated func didEncounterError(_ message: String) {
        Task { @MainActor in
            self.connectingTimeoutTask?.cancel()
            self.state = .error(message)
        }
    }
}
