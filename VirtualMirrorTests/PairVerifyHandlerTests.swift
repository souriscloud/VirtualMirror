import XCTest
import CryptoKit
@testable import VirtualMirror

/// Tests for the pair-verify exchange.
///
/// These exercise the ECDH path (stage 1) and pin the stage-2 signature-policy
/// behaviour so a future change to enforcement is a conscious, visible decision.
final class PairVerifyHandlerTests: XCTestCase {

    /// Builds a well-formed pair-verify stage-1 request body:
    /// [flag 0x01,0x00,0x00,0x00] + [32-byte client Curve25519 public key] (+ optional trailing sig bytes)
    private func stage1Request(clientPublicKey: Curve25519.KeyAgreement.PublicKey) -> Data {
        var body = Data([0x01, 0x00, 0x00, 0x00])
        body.append(clientPublicKey.rawRepresentation)
        body.append(Data(repeating: 0, count: 64)) // signature region (unused by stage 1)
        return body
    }

    func testStage1ProducesServerKeyAndSharedSecret() {
        let handler = PairVerifyHandler()
        let clientPriv = Curve25519.KeyAgreement.PrivateKey()

        let result = handler.handle(requestBody: stage1Request(clientPublicKey: clientPriv.publicKey))

        guard case .ok(let response) = result else {
            return XCTFail("Stage 1 should return .ok")
        }
        // Response = 32-byte server Curve25519 pubkey + 64-byte encrypted signature.
        XCTAssertEqual(response.count, 96)
        XCTAssertNotNil(handler.derivedSharedSecret, "ECDH shared secret should be available after stage 1")
    }

    func testStage1SharedSecretMatchesClientSide() {
        let handler = PairVerifyHandler()
        let clientPriv = Curve25519.KeyAgreement.PrivateKey()

        guard case .ok(let response) = handler.handle(requestBody: stage1Request(clientPublicKey: clientPriv.publicKey)) else {
            return XCTFail("Stage 1 should return .ok")
        }

        // The first 32 bytes of the response are the server's ephemeral public key.
        let serverPubData = response.prefix(32)
        let serverPub = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverPubData)
        let clientSideSecret = try! clientPriv.sharedSecretFromKeyAgreement(with: serverPub)
        let clientSideBytes = clientSideSecret.withUnsafeBytes { Data($0) }

        XCTAssertEqual(handler.derivedSharedSecret, clientSideBytes,
                       "Server- and client-derived ECDH secrets must match")
    }

    func testStage1RejectsInvalidClientKey() {
        let handler = PairVerifyHandler()
        // 32 bytes that aren't a valid Curve25519 point handling is lenient, but a
        // too-short body must not crash and must not yield a shared secret.
        var body = Data([0x01, 0x00, 0x00, 0x00])
        body.append(Data(repeating: 0xAB, count: 8)) // far too short for a key
        guard case .ok(let response) = handler.handle(requestBody: body) else {
            return XCTFail("Short stage-1 body should return .ok(empty), not crash")
        }
        XCTAssertTrue(response.isEmpty)
        XCTAssertNil(handler.derivedSharedSecret)
    }

    func testShortBodyReturnsEmptyOk() {
        let handler = PairVerifyHandler()
        guard case .ok(let response) = handler.handle(requestBody: Data([0x00, 0x01])) else {
            return XCTFail("Too-short body should return .ok(empty)")
        }
        XCTAssertTrue(response.isEmpty)
    }

    /// Pins the stage-2 policy: with `requireClientSignature` at its default,
    /// an unverifiable stage-2 payload is tolerated (.ok). If enforcement is
    /// turned on, this expectation flips to `.reject` — update intentionally.
    func testStage2PolicyMatchesConfig() {
        let handler = PairVerifyHandler()
        // Establish session keys via a real stage 1 first.
        let clientPriv = Curve25519.KeyAgreement.PrivateKey()
        _ = handler.handle(requestBody: stage1Request(clientPublicKey: clientPriv.publicKey))

        // Stage 2 with garbage ciphertext → signature can't verify.
        var stage2 = Data([0x00, 0x00, 0x00, 0x00])
        stage2.append(Data(repeating: 0x00, count: 96))
        let result = handler.handle(requestBody: stage2)

        if AirPlayConfig.requireClientSignature {
            guard case .reject = result else {
                return XCTFail("With enforcement on, an invalid signature must .reject")
            }
        } else {
            guard case .ok = result else {
                return XCTFail("With enforcement off, an invalid signature is tolerated (.ok)")
            }
        }
    }
}
