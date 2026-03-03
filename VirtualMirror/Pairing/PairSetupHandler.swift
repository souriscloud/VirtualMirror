import Foundation
import CryptoKit
import os

class PairSetupHandler {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "PairSetup")

    /// Handle pair-setup request.
    /// For transient pairing (legacy AirPlay screen mirroring), this is a single exchange:
    /// we just return our Ed25519 public key (32 bytes).
    func handle(requestBody: Data) -> Data {
        logger.debug("pair-setup: received \(requestBody.count) bytes")

        // Always respond with our Ed25519 public key
        let publicKey = AirPlayConfig.ed25519PublicKey.rawRepresentation
        logger.debug("pair-setup: sending Ed25519 public key (\(publicKey.count) bytes)")
        return publicKey
    }
}
