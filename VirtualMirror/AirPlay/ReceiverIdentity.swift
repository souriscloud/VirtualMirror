import Foundation
import CryptoKit
import Security

/// Per-receiver identity and port allocation. Each receiver window owns one of
/// these, so multiple receivers can advertise side by side and an iPhone sees
/// them as distinct devices.
///
/// Ephemeral by design: a fresh device ID, signing key, and UUIDs are generated
/// on creation and live only for the lifetime of this object — nothing is
/// persisted, so each receiver is a clean slate every launch.
final class ReceiverIdentity {
    struct Ports {
        let airplay: UInt16
        let video: UInt16
        let ntp: UInt16
        let audioData: UInt16
        let audioControl: UInt16
    }

    let slot: Int
    let ports: Ports
    let deviceID: String
    let ed25519PrivateKey: Curve25519.Signing.PrivateKey
    let pairingID: String
    let displayUUID: String

    /// Display name (shown in the AirPlay list and the window title). Mutable so
    /// it can be renamed live; guarded with a lock because the advertising and
    /// connection paths read it off non-main threads.
    private let nameLock = NSLock()
    private var _name: String
    var name: String {
        get { nameLock.lock(); defer { nameLock.unlock() }; return _name }
        set { nameLock.lock(); _name = newValue; nameLock.unlock() }
    }

    init(slot: Int, name: String) {
        self.slot = slot
        self._name = name
        self.ports = ReceiverIdentity.ports(forSlot: slot)
        self.deviceID = ReceiverIdentity.randomDeviceID()
        self.ed25519PrivateKey = Curve25519.Signing.PrivateKey()
        self.pairingID = UUID().uuidString
        self.displayUUID = UUID().uuidString
    }

    var ed25519PublicKey: Curve25519.Signing.PublicKey { ed25519PrivateKey.publicKey }
    var publicKeyHex: String {
        ed25519PublicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
    }
    var deviceIDBytes: [UInt8] {
        deviceID.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    }

    /// Slot 0 keeps the historical ports (47000 / 47100 / 47102 / 47103 / 47104).
    /// Each subsequent slot is offset by 1000, preserving the +100/+102/+103/+104
    /// structure so port ranges never collide between receivers.
    static func ports(forSlot slot: Int) -> Ports {
        let base = UInt16(47000 + slot * 1000)
        return Ports(airplay: base,
                     video: base + 100,
                     ntp: base + 102,
                     audioData: base + 103,
                     audioControl: base + 104)
    }

    private static func randomDeviceID() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = bytes[0] & 0xFE | 0x02 // locally administered, unicast
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
