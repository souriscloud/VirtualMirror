import Foundation
import CryptoKit
import Security

struct AirPlayConfig {
    static let serverName = "VirtualMirror"
    static let model = "AppleTV3,2"
    static let sourceVersion = "220.68"
    static let protoVersion = "1.1"
    static let firmwareVersion = "p20.20"
    static let osVersion = "14.0"

    // Feature flags matching UxPlay exactly for maximum compatibility.
    // UxPlay uses 0x5A7FFEE6,0x0 — this avoids triggering AirPlay 2 protocol
    // paths or MFi /auth-setup that we can't handle.
    //
    // Low word 0x5A7FFEE6:
    //   Bit 1: Photo, Bit 2: VideoFairPlay, Bit 5: VideoVolumeControl,
    //   Bit 6: VideoHTTPLiveStreams(?), Bit 7: Screen, Bit 9: Audio,
    //   Bit 10: AudioRedundant, Bit 11: FPSAPv2pt5_AES_GCM,
    //   Bit 12: FPSAPv2.5, Bit 13-14: Authentication,
    //   Bit 15-17: (various), Bit 19-22: MetadataFeatures,
    //   Bit 25: AudioFormat type 100, Bit 27: SupportsLegacyPairing,
    //   Bit 28-30: (AP2 related)
    // NOT setting bit 0 (Video), bit 4 (VideoHTTPLiveStreams), bit 8 (ScreenRotate)
    // NOT setting bit 26 (AudioFormat type 101) — requires MFi /auth-setup
    //
    // High word 0x0:
    //   NOT setting bits 33-36 (Volume, AirPlayVideoV2, RFC2198, AP2)
    //   These caused the iPhone to use AirPlay 2 protocol paths
    static let featuresLow: UInt32 = 0x5A7FFEE6
    static let featuresHigh: UInt32 = 0x00000000
    static var featuresString: String {
        return String(format: "0x%X,0x%X", featuresLow, featuresHigh)
    }
    static var featuresInt: UInt64 {
        return UInt64(featuresHigh) << 32 | UInt64(featuresLow)
    }

    // Generate a stable device ID (MAC-address format)
    static var deviceID: String = {
        let key = "VirtualMirrorDeviceID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        var bytes = [UInt8](repeating: 0, count: 6)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = bytes[0] & 0xFE | 0x02 // locally administered, unicast
        let id = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    static var deviceIDBytes: [UInt8] {
        return deviceID.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    }

    // MARK: - Ed25519 long-term keypair (stored in Keychain)

    private static let keychainService = "cloud.souris.virtualmirror"
    private static let keychainAccount = "Ed25519PrivateKey"

    static var ed25519PrivateKey: Curve25519.Signing.PrivateKey = {
        // Try loading from Keychain first
        if let data = loadFromKeychain(service: keychainService, account: keychainAccount),
           let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return privKey
        }

        // Migrate from UserDefaults if present
        let legacyKey = "VirtualMirrorEd25519Key"
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            saveToKeychain(service: keychainService, account: keychainAccount, data: data)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return privKey
        }

        // Generate new key
        let privKey = Curve25519.Signing.PrivateKey()
        saveToKeychain(service: keychainService, account: keychainAccount, data: privKey.rawRepresentation)
        return privKey
    }()

    static var ed25519PublicKey: Curve25519.Signing.PublicKey {
        return ed25519PrivateKey.publicKey
    }

    static var publicKeyHex: String {
        return ed25519PublicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    }

    // Pairing identifier
    static var pairingID: String = {
        let key = "VirtualMirrorPairingID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    // Stable display UUID (generated once, persisted)
    static var displayUUID: String = {
        let key = "VirtualMirrorDisplayUUID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    // MARK: - Keychain helpers

    private static func saveToKeychain(service: String, account: String, data: Data) {
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadFromKeychain(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - /info response as binary plist data

    static func infoResponseData(forDisplay width: Int = 1920, height: Int = 1080) -> Data {
        // Matches UxPlay raop_handler_info exactly:
        // - No "protovers" (only in TXT records, not /info response)
        // - keepAliveSendStatsAsBody is boolean (not integer)
        // - Stable display UUID (not regenerated each call)
        let info: [String: Any] = [
            "deviceID": deviceID,
            "macAddress": deviceID,
            "model": model,
            "name": serverName,
            "sourceVersion": sourceVersion,
            "features": NSNumber(value: featuresInt),
            "statusFlags": NSNumber(value: 68 as UInt64),
            "vv": NSNumber(value: 2 as UInt64),
            "initialVolume": NSNumber(value: -20.0),
            "pi": pairingID,
            "pk": ed25519PublicKey.rawRepresentation,
            "keepAliveLowPower": NSNumber(value: 1 as UInt64),
            "keepAliveSendStatsAsBody": NSNumber(value: true),
            "displays": [
                [
                    "width": NSNumber(value: UInt64(width)),
                    "height": NSNumber(value: UInt64(height)),
                    "widthPixels": NSNumber(value: UInt64(width)),
                    "heightPixels": NSNumber(value: UInt64(height)),
                    "widthPhysical": NSNumber(value: 0 as UInt64),
                    "heightPhysical": NSNumber(value: 0 as UInt64),
                    "uuid": displayUUID,
                    "features": NSNumber(value: 14 as UInt64),
                    "rotation": NSNumber(value: false),
                    "overscanned": NSNumber(value: false),
                    "refreshRate": NSNumber(value: 1.0 / 60.0),
                    "maxFPS": NSNumber(value: 30 as UInt64),
                ] as [String : Any]
            ],
            "audioFormats": [
                [
                    "type": NSNumber(value: 100 as UInt64),
                    "audioInputFormats": NSNumber(value: 0x03FFFFFC as UInt64),
                    "audioOutputFormats": NSNumber(value: 0x03FFFFFC as UInt64),
                ] as [String : Any],
                [
                    "type": NSNumber(value: 101 as UInt64),
                    "audioInputFormats": NSNumber(value: 0x03FFFFFC as UInt64),
                    "audioOutputFormats": NSNumber(value: 0x03FFFFFC as UInt64),
                ] as [String : Any],
            ],
            "audioLatencies": [
                [
                    "type": NSNumber(value: 100 as UInt64),
                    "audioType": "default",
                    "inputLatencyMicros": NSNumber(value: 0 as UInt64),
                    "outputLatencyMicros": NSNumber(value: false),
                ] as [String : Any],
                [
                    "type": NSNumber(value: 101 as UInt64),
                    "audioType": "default",
                    "inputLatencyMicros": NSNumber(value: 0 as UInt64),
                    "outputLatencyMicros": NSNumber(value: false),
                ] as [String : Any],
            ],
        ]
        return try! PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
    }

    // MARK: - /info qualifier response (txtAirPlay / txtRAOP)

    /// Handles a GET /info request that includes a qualifier plist body.
    /// Returns a plist containing only the requested TXT record data blob(s),
    /// matching UxPlay's behavior (the full /info fields are NOT included).
    static func infoQualifierResponseData(qualifier: String) -> Data {
        var response: [String: Any] = [:]
        if qualifier == "txtAirPlay" {
            response["txtAirPlay"] = Data(airplayTXTRecord())
        } else if qualifier == "txtRAOP" {
            response["txtRAOP"] = Data(raopTXTRecord())
        }
        return try! PropertyListSerialization.data(fromPropertyList: response, format: .binary, options: 0)
    }

    // MARK: - DNS-SD TXT Record Building

    /// Builds a DNS-SD TXT record as raw bytes (length-prefixed key=value pairs).
    /// Used both for Bonjour advertisement and /info qualifier responses.
    private static func buildTXTData(from entries: [(String, String)]) -> [UInt8] {
        var data: [UInt8] = []
        for (key, value) in entries {
            let entry = "\(key)=\(value)"
            let entryBytes = Array(entry.utf8)
            guard entryBytes.count <= 255 else { continue }
            data.append(UInt8(entryBytes.count))
            data.append(contentsOf: entryBytes)
        }
        return data
    }

    /// AirPlay (_airplay._tcp) TXT record entries.
    static func airplayTXTRecord() -> [UInt8] {
        buildTXTData(from: [
            ("deviceid", deviceID),
            ("features", featuresString),
            ("model", model),
            ("srcvers", sourceVersion),
            ("protovers", protoVersion),
            ("pk", publicKeyHex),
            ("pi", pairingID),
            ("flags", "0x4"),
            ("vv", "2"),
            ("pw", "false"),
            ("acl", "0"),
            ("fv", firmwareVersion),
            ("osvers", osVersion),
        ])
    }

    /// RAOP (_raop._tcp) TXT record entries.
    static func raopTXTRecord() -> [UInt8] {
        buildTXTData(from: [
            ("txtvers", "1"),
            ("ch", "2"),
            ("cn", "0,1,2,3"),
            ("da", "true"),
            ("et", "0,3,5"),
            ("md", "0,1,2"),
            ("pw", "false"),
            ("sr", "44100"),
            ("ss", "16"),
            ("tp", "UDP"),
            ("vn", "65537"),
            ("vs", sourceVersion),
            ("am", model),
            ("sf", "0x4"),
            ("ft", featuresString),
            ("pk", publicKeyHex),
            ("vv", "2"),
            ("rhd", "5.6.0.0"),
            ("sv", "false"),
        ])
    }
}
