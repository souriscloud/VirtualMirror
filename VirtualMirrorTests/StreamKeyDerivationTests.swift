import XCTest
import CryptoKit
@testable import VirtualMirror

final class StreamKeyDerivationTests: XCTestCase {

    // Use fixed test data for reproducible key derivation
    let testFairplayKey = Data(repeating: 0xAA, count: 16)
    let testEcdhSecret = Data(repeating: 0xBB, count: 32)

    // MARK: - Base Key Derivation

    func testBaseKeyIs16Bytes() {
        let key = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        XCTAssertEqual(key.count, 16)
    }

    func testBaseKeyIsDeterministic() {
        let key1 = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        let key2 = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        XCTAssertEqual(key1, key2)
    }

    func testBaseKeyDiffersWithDifferentInput() {
        let key1 = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        let key2 = StreamKeyDerivation.deriveBaseKey(fairplayKey: Data(repeating: 0xCC, count: 16), ecdhSecret: testEcdhSecret)
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Mirror Key Derivation

    func testMirrorKeysAre16Bytes() {
        let (key, iv) = StreamKeyDerivation.deriveMirrorKeys(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret, streamConnectionID: 42)
        XCTAssertEqual(key.count, 16)
        XCTAssertEqual(iv.count, 16)
    }

    func testMirrorKeyDiffersFromIV() {
        let (key, iv) = StreamKeyDerivation.deriveMirrorKeys(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret, streamConnectionID: 1)
        XCTAssertNotEqual(key, iv)
    }

    func testMirrorKeysDifferByConnectionID() {
        let (key1, iv1) = StreamKeyDerivation.deriveMirrorKeys(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret, streamConnectionID: 1)
        let (key2, iv2) = StreamKeyDerivation.deriveMirrorKeys(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret, streamConnectionID: 2)
        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(iv1, iv2)
    }

    // MARK: - Audio Key Derivation

    func testAudioKeyIs16Bytes() {
        let key = StreamKeyDerivation.deriveAudioKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        XCTAssertEqual(key.count, 16)
    }

    func testAudioKeyMatchesBaseKey() {
        // Audio key derivation uses the same simpler path as base key
        let audioKey = StreamKeyDerivation.deriveAudioKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        let baseKey = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        XCTAssertEqual(audioKey, baseKey)
    }

    func testAudioKeyDiffersFromMirrorKey() {
        let audioKey = StreamKeyDerivation.deriveAudioKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        let (mirrorKey, _) = StreamKeyDerivation.deriveMirrorKeys(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret, streamConnectionID: 1)
        XCTAssertNotEqual(audioKey, mirrorKey)
    }

    // MARK: - Manual SHA-512 Verification

    func testBaseKeyMatchesManualSHA512() {
        // Manually compute SHA-512(fairplayKey || ecdhSecret) and take first 16 bytes
        var hasher = SHA512()
        hasher.update(data: testFairplayKey)
        hasher.update(data: testEcdhSecret)
        let expected = Data(hasher.finalize().prefix(16))

        let actual = StreamKeyDerivation.deriveBaseKey(fairplayKey: testFairplayKey, ecdhSecret: testEcdhSecret)
        XCTAssertEqual(actual, expected)
    }
}
