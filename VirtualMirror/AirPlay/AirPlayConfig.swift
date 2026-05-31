import Foundation
import CryptoKit
import Security

struct AirPlayConfig {
    static let serverName = "VirtualMirror"
    static let model = "AppleTV3,2"

    // MARK: - Security
    // When true, pair-verify stage 2 rejects clients whose Ed25519 signature
    // fails to validate (the cryptographically correct behaviour). Defaults to
    // false because some senders use signature semantics we don't fully
    // replicate, and rejecting them would break mirroring. Flip to true once
    // the signature input is verified against real devices.
    static let requireClientSignature = false
    static let sourceVersion = "220.68"
    static let protoVersion = "1.1"
    static let firmwareVersion = "p20.20"
    static let osVersion = "14.0"

    // MARK: - Port Allocation
    // macOS built-in AirPlay Receiver runs on port 7000; we use 47000+ to avoid conflicts.
    static let airplayPort: UInt16 = 47000
    static let videoStreamPort: UInt16 = 47100
    static let ntpTimingPort: UInt16 = 47102
    static let audioStreamPort: UInt16 = 47103
    static let audioControlPort: UInt16 = 47104

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

    // Identity (device ID, Ed25519 key, pairing ID, display UUID) and port
    // allocation are per-receiver — see ReceiverIdentity. AirPlayConfig now
    // holds only the protocol-level constants shared by every receiver.

    // MARK: - /info response as binary plist data

    static func infoResponseData(_ identity: ReceiverIdentity, forDisplay width: Int = 1920, height: Int = 1080) -> Data {
        // Matches UxPlay raop_handler_info exactly:
        // - No "protovers" (only in TXT records, not /info response)
        // - keepAliveSendStatsAsBody is boolean (not integer)
        // - Stable display UUID (not regenerated each call)
        let info: [String: Any] = [
            "deviceID": identity.deviceID,
            "macAddress": identity.deviceID,
            "model": model,
            "name": identity.name,
            "sourceVersion": sourceVersion,
            "features": NSNumber(value: featuresInt),
            "statusFlags": NSNumber(value: 68 as UInt64),
            "vv": NSNumber(value: 2 as UInt64),
            "initialVolume": NSNumber(value: -20.0),
            "pi": identity.pairingID,
            "pk": identity.ed25519PublicKey.rawRepresentation,
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
                    "uuid": identity.displayUUID,
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
        do {
            return try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        } catch {
            // This should never fail with static dictionaries, but return empty data rather than crash
            return Data()
        }
    }

    // MARK: - /info qualifier response (txtAirPlay / txtRAOP)

    /// Handles a GET /info request that includes a qualifier plist body.
    /// Returns a plist containing only the requested TXT record data blob(s),
    /// matching UxPlay's behavior (the full /info fields are NOT included).
    static func infoQualifierResponseData(_ identity: ReceiverIdentity, qualifier: String) -> Data {
        var response: [String: Any] = [:]
        if qualifier == "txtAirPlay" {
            response["txtAirPlay"] = Data(airplayTXTRecord(identity))
        } else if qualifier == "txtRAOP" {
            response["txtRAOP"] = Data(raopTXTRecord(identity))
        }
        do {
            return try PropertyListSerialization.data(fromPropertyList: response, format: .binary, options: 0)
        } catch {
            return Data()
        }
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
    static func airplayTXTRecord(_ identity: ReceiverIdentity) -> [UInt8] {
        buildTXTData(from: [
            ("deviceid", identity.deviceID),
            ("features", featuresString),
            ("model", model),
            ("srcvers", sourceVersion),
            ("protovers", protoVersion),
            ("pk", identity.publicKeyHex),
            ("pi", identity.pairingID),
            ("flags", "0x4"),
            ("vv", "2"),
            ("pw", "false"),
            ("acl", "0"),
            ("fv", firmwareVersion),
            ("osvers", osVersion),
        ])
    }

    /// RAOP (_raop._tcp) TXT record entries.
    static func raopTXTRecord(_ identity: ReceiverIdentity) -> [UInt8] {
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
            ("pk", identity.publicKeyHex),
            ("vv", "2"),
            ("rhd", "5.6.0.0"),
            ("sv", "false"),
        ])
    }
}
