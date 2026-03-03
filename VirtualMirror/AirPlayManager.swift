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

    nonisolated let videoDecoder = VideoDecoder()
    private var airPlayService: AirPlayService?
    private var airPlayServer: AirPlayServer?

    func start() {
        logger.info("Starting AirPlay services")
        state = .idle

        airPlayServer = AirPlayServer(manager: self)
        let port: UInt16 = 47000 // Avoid conflict with macOS built-in AirPlay Receiver on port 7000
        airPlayServer?.start(port: port)

        airPlayService = AirPlayService()
        airPlayService?.startAdvertising(port: Int(port))
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
            self.state = .connecting(deviceName)
        }
    }

    nonisolated func didStartMirroring() {
        Task { @MainActor in
            let name = self.state.deviceName ?? "Unknown"
            self.state = .mirroring(name)
        }
    }

    nonisolated func didDisconnect() {
        Task { @MainActor in
            self.state = .idle
            self.videoDecoder.reset()
        }
    }

    nonisolated func didEncounterError(_ message: String) {
        Task { @MainActor in
            self.state = .error(message)
        }
    }
}
