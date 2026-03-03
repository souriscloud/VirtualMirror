import Foundation
import os

class FairPlayHandler {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "FairPlay")

    // Store phase 3 message for later key derivation
    private var phase3Message: Data?

    func handle(requestBody: Data) -> Data {
        guard requestBody.count >= 7 else {
            logger.error("FairPlay request too short: \(requestBody.count) bytes")
            return Data()
        }

        // Parse FPLY header
        let signature = requestBody[requestBody.startIndex ..< requestBody.startIndex + 4]
        guard signature.elementsEqual([0x46, 0x50, 0x4C, 0x59]) else {
            logger.error("Invalid FairPlay signature")
            return Data()
        }

        // Check version
        let majorVersion = requestBody[requestBody.startIndex + 4]
        guard majorVersion == 0x03 else {
            logger.error("Unsupported FairPlay major version: \(majorVersion)")
            return Data()
        }

        let phase = requestBody[requestBody.startIndex + 6]
        logger.debug("FairPlay phase: \(phase), body: \(requestBody.count) bytes")

        switch phase {
        case 1:
            return handlePhase1(requestBody: requestBody)
        case 3:
            return handlePhase3(requestBody: requestBody)
        default:
            logger.warning("Unknown FairPlay phase: \(phase)")
            return Data()
        }
    }

    private func handlePhase1(requestBody: Data) -> Data {
        // Mode byte is at offset 14 of the 16-byte request
        let mode: UInt8
        if requestBody.count > 14 {
            mode = requestBody[requestBody.startIndex + 14]
        } else {
            mode = 0
        }

        guard mode <= 3 else {
            logger.error("FairPlay invalid mode: \(mode)")
            return Data()
        }

        var response = [UInt8](repeating: 0, count: 142)
        let result = fairplay_setup_phase1(mode, &response, 142)

        if result != 0 {
            logger.error("FairPlay phase 1 failed for mode \(mode)")
            return Data()
        }

        logger.info("FairPlay phase 1 complete (mode \(mode)), response: 142 bytes")
        return Data(response)
    }

    private func handlePhase3(requestBody: Data) -> Data {
        guard requestBody.count >= 164 else {
            logger.error("FairPlay phase 3 request too short: \(requestBody.count) bytes (need 164)")
            return Data()
        }

        // Store the phase 3 message for later key derivation
        self.phase3Message = requestBody

        var response = [UInt8](repeating: 0, count: 32)
        let result = requestBody.withUnsafeBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return fairplay_setup_phase3(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                requestBody.count,
                &response,
                32
            )
        }

        if result != 0 {
            logger.error("FairPlay phase 3 failed")
            return Data()
        }

        logger.info("FairPlay phase 3 complete, response: 32 bytes")
        return Data(response)
    }

    /// Decrypt the ekey from SETUP using the FairPlay session key derived from phase 3
    func decryptStreamKey(ekey: Data) -> Data? {
        guard let message3 = phase3Message else {
            logger.error("Cannot decrypt ekey: no phase 3 message stored")
            return nil
        }
        guard ekey.count >= 72 else {
            logger.error("ekey too short: \(ekey.count) bytes (need 72)")
            return nil
        }

        var keyOut = [UInt8](repeating: 0, count: 16)

        message3.withUnsafeBytes { msg3Ptr in
            ekey.withUnsafeBytes { ekeyPtr in
                guard let msg3Base = msg3Ptr.baseAddress,
                      let ekeyBase = ekeyPtr.baseAddress else { return }
                playfair_decrypt(
                    UnsafeMutablePointer(mutating: msg3Base.assumingMemoryBound(to: UInt8.self)),
                    UnsafeMutablePointer(mutating: ekeyBase.assumingMemoryBound(to: UInt8.self)),
                    &keyOut
                )
            }
        }

        let keyData = Data(keyOut)
        logger.debug("Stream key decrypted (\(keyData.count) bytes)")
        return keyData
    }
}
