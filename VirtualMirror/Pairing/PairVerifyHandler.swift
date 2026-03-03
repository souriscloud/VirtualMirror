import Foundation
import CryptoKit
import CommonCrypto
import os

class PairVerifyHandler {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "PairVerify")

    // Ephemeral Curve25519 key pair for this session
    private var ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var clientPublicKeyData: Data?
    private var sharedSecretBytes: Data?
    private var aesKey: Data?
    private var aesIV: Data?

    /// The shared secret bytes, available after pair-verify completes (for FairPlay key derivation)
    var derivedSharedSecret: Data? { sharedSecretBytes }

    /// Handle pair-verify request.
    /// Stage is determined by the first byte of the request (0x01 = stage 1, 0x00 = stage 2).
    /// Returns the response body.
    func handle(requestBody: Data) -> Data {
        guard requestBody.count >= 4 else {
            logger.error("pair-verify: body too short (\(requestBody.count) bytes)")
            return Data()
        }

        let stageFlag = requestBody[requestBody.startIndex]
        logger.debug("pair-verify: flag=\(stageFlag), body=\(requestBody.count) bytes")

        if stageFlag == 1 {
            return handleStage1(requestBody: requestBody)
        } else {
            return handleStage2(requestBody: requestBody)
        }
    }

    private func handleStage1(requestBody: Data) -> Data {
        // Stage 1:
        // Receive: [4 bytes flag 0x01,0x00,0x00,0x00] + [32 bytes client Curve25519 pubkey] + [64 bytes Ed25519 signature]
        guard requestBody.count >= 4 + 32 else {
            logger.error("pair-verify stage 1: body too short (\(requestBody.count) bytes)")
            return Data()
        }

        // Extract client's Curve25519 public key (bytes 4-35)
        let clientPubKeyData = Data(requestBody[requestBody.startIndex + 4 ..< requestBody.startIndex + 36])
        self.clientPublicKeyData = clientPubKeyData

        guard let clientPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: clientPubKeyData) else {
            logger.error("pair-verify stage 1: invalid client public key")
            return Data()
        }

        // Generate our ephemeral Curve25519 key pair
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        self.ephemeralPrivateKey = privateKey

        // Compute shared secret
        guard let shared = try? privateKey.sharedSecretFromKeyAgreement(with: clientPublicKey) else {
            logger.error("pair-verify stage 1: key agreement failed")
            return Data()
        }

        // Get raw shared secret bytes
        let sharedBytes = shared.withUnsafeBytes { Data($0) }
        self.sharedSecretBytes = sharedBytes

        // Derive AES key: SHA-512("Pair-Verify-AES-Key" + shared_secret), take first 16 bytes
        aesKey = deriveKey(label: "Pair-Verify-AES-Key", sharedSecret: sharedBytes)
        // Derive AES IV: SHA-512("Pair-Verify-AES-IV" + shared_secret), take first 16 bytes
        aesIV = deriveKey(label: "Pair-Verify-AES-IV", sharedSecret: sharedBytes)

        guard let aesKey = aesKey, let aesIV = aesIV else {
            logger.error("pair-verify stage 1: key derivation failed")
            return Data()
        }

        // Sign: (our_curve25519_pubkey + client_curve25519_pubkey)
        var signatureInput = Data()
        signatureInput.append(privateKey.publicKey.rawRepresentation)
        signatureInput.append(clientPubKeyData)

        guard let signature = try? AirPlayConfig.ed25519PrivateKey.signature(for: signatureInput) else {
            logger.error("pair-verify stage 1: signing failed")
            return Data()
        }

        // Encrypt signature with AES-128-CTR (no auth tag)
        let encryptedSignature = aesCTR(key: aesKey, iv: aesIV, data: Data(signature))

        // Response: [32 bytes our Curve25519 pubkey] + [64 bytes encrypted signature]
        var responseData = Data()
        responseData.append(privateKey.publicKey.rawRepresentation) // 32 bytes
        responseData.append(encryptedSignature) // 64 bytes

        logger.info("pair-verify stage 1 complete, response: \(responseData.count) bytes")
        return responseData
    }

    private func handleStage2(requestBody: Data) -> Data {
        // Stage 2:
        // Receive: [4 bytes flag 0x00,0x00,0x00,0x00] + [encrypted client data]
        // Decrypt and verify the client's Ed25519 signature.

        logger.debug("pair-verify stage 2: verifying (\(requestBody.count) bytes)")

        if requestBody.count > 4, let aesKey = aesKey, let aesIV = aesIV {
            let encryptedData = Data(requestBody.suffix(from: requestBody.startIndex + 4))
            let decrypted = aesCTR(key: aesKey, iv: aesIV, data: encryptedData)

            // The decrypted data contains: [32 bytes client Ed25519 pubkey] + [64 bytes signature]
            if decrypted.count >= 96,
               let clientCurveKey = clientPublicKeyData,
               let serverCurveKey = ephemeralPrivateKey?.publicKey.rawRepresentation {
                let clientSigningKeyData = decrypted[decrypted.startIndex..<decrypted.startIndex + 32]
                let clientSignature = decrypted[decrypted.startIndex + 32..<decrypted.startIndex + 96]

                // Verify: client signed (client_curve25519_pubkey + server_curve25519_pubkey)
                var verifyInput = Data()
                verifyInput.append(clientCurveKey)
                verifyInput.append(serverCurveKey)

                if let clientSigningKey = try? Curve25519.Signing.PublicKey(rawRepresentation: clientSigningKeyData) {
                    let isValid = clientSigningKey.isValidSignature(Data(clientSignature), for: verifyInput)
                    if isValid {
                        logger.info("pair-verify stage 2: client signature verified")
                    } else {
                        logger.warning("pair-verify stage 2: client signature invalid (proceeding anyway for compatibility)")
                    }
                } else {
                    logger.warning("pair-verify stage 2: could not parse client signing key")
                }
            } else {
                logger.debug("pair-verify stage 2: decrypted data too short for verification (\(decrypted.count) bytes)")
            }
        }

        logger.info("pair-verify complete")
        // Response: empty body (200 OK)
        return Data()
    }

    // MARK: - Crypto helpers

    /// Derive a 16-byte key using SHA-512(label + sharedSecret)[0:16]
    private func deriveKey(label: String, sharedSecret: Data) -> Data? {
        var hasher = SHA512()
        hasher.update(data: Data(label.utf8))
        hasher.update(data: sharedSecret)
        let hash = hasher.finalize()
        return Data(hash.prefix(16))
    }

    /// AES-128-CTR encrypt/decrypt (symmetric operation)
    private func aesCTR(key: Data, iv: Data, data: Data) -> Data {
        var cryptor: CCCryptorRef?
        var outMoved: size_t = 0

        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    key.count,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }

        guard status == kCCSuccess, let ref = cryptor else {
            logger.error("AES-CTR setup failed: \(status)")
            return data
        }

        var resultBuffer = [UInt8](repeating: 0, count: data.count)
        _ = data.withUnsafeBytes { dataPtr in
            CCCryptorUpdate(
                ref,
                dataPtr.baseAddress,
                data.count,
                &resultBuffer,
                resultBuffer.count,
                &outMoved
            )
        }

        CCCryptorRelease(ref)
        return Data(resultBuffer.prefix(outMoved))
    }
}
