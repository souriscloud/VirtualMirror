import Foundation
import CryptoKit

/// Shared key derivation logic for AirPlay audio and video streams.
/// Both streams derive their AES keys from the same FairPlay key and ECDH shared secret
/// using SHA-512, but with different derivation paths.
enum StreamKeyDerivation {
    /// Derives the base AES key shared by both audio and video:
    ///   eaeskey = SHA-512(fairplayKey || ecdhSecret)[0..<16]
    static func deriveBaseKey(fairplayKey: Data, ecdhSecret: Data) -> Data {
        var hasher = SHA512()
        hasher.update(data: fairplayKey)
        hasher.update(data: ecdhSecret)
        return Data(hasher.finalize().prefix(16))
    }

    /// Derives the mirror (video) stream AES-128-CTR key and IV:
    ///   key = SHA-512("AirPlayStreamKey{connID}" || eaeskey)[0..<16]
    ///   iv  = SHA-512("AirPlayStreamIV{connID}"  || eaeskey)[0..<16]
    static func deriveMirrorKeys(fairplayKey: Data, ecdhSecret: Data, streamConnectionID: UInt64) -> (key: Data, iv: Data) {
        let eaeskey = deriveBaseKey(fairplayKey: fairplayKey, ecdhSecret: ecdhSecret)

        var keyHasher = SHA512()
        keyHasher.update(data: Data("AirPlayStreamKey\(streamConnectionID)".utf8))
        keyHasher.update(data: eaeskey)
        let decryptKey = Data(keyHasher.finalize().prefix(16))

        var ivHasher = SHA512()
        ivHasher.update(data: Data("AirPlayStreamIV\(streamConnectionID)".utf8))
        ivHasher.update(data: eaeskey)
        let decryptIV = Data(ivHasher.finalize().prefix(16))

        return (decryptKey, decryptIV)
    }

    /// Derives the audio stream AES-128-CBC key:
    ///   key = SHA-512(fairplayKey || ecdhSecret)[0..<16]
    /// (Same as the base key — audio uses the simpler single-hash derivation.)
    static func deriveAudioKey(fairplayKey: Data, ecdhSecret: Data) -> Data {
        return deriveBaseKey(fairplayKey: fairplayKey, ecdhSecret: ecdhSecret)
    }
}
