import Foundation
import dnssd
import os

/// Advertises AirPlay and RAOP Bonjour services using the DNS-SD C API.
/// Replaces the deprecated NetService-based implementation.
class AirPlayService {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayService")

    private var airplayRef: DNSServiceRef?
    private var raopRef: DNSServiceRef?

    /// Shared queue for processing DNS-SD events
    private let dnssdQueue = DispatchQueue(label: "cloud.souris.virtualmirror.dnssd")
    private var airplaySource: DispatchSourceRead?
    private var raopSource: DispatchSourceRead?

    func startAdvertising(identity: ReceiverIdentity) {
        let port = Int(identity.ports.airplay)
        logger.info("Starting Bonjour advertisement for \"\(identity.name)\" on port \(port)")

        let port16 = UInt16(port)

        // Advertise _airplay._tcp
        let airplayTXT = AirPlayConfig.airplayTXTRecord(identity)
        var airplayServiceRef: DNSServiceRef?
        let airplayErr = DNSServiceRegister(
            &airplayServiceRef,
            0,                          // flags
            0,                          // interfaceIndex (all)
            identity.name,              // name
            "_airplay._tcp",            // regtype
            nil,                        // domain (default)
            nil,                        // host (default)
            CFSwapInt16HostToBig(port16),
            UInt16(airplayTXT.count),
            airplayTXT,
            nil,                        // callback (not needed)
            nil                         // context
        )
        if airplayErr == kDNSServiceErr_NoError, let ref = airplayServiceRef {
            airplayRef = ref
            airplaySource = createDispatchSource(for: ref, label: "AirPlay")
            logger.info("AirPlay Bonjour service registered")
        } else {
            logger.error("Failed to register AirPlay service: \(airplayErr)")
        }

        // Advertise _raop._tcp with deviceID@name format
        let raopName = "\(identity.deviceID.replacingOccurrences(of: ":", with: ""))@\(identity.name)"
        let raopTXT = AirPlayConfig.raopTXTRecord(identity)
        var raopServiceRef: DNSServiceRef?
        let raopErr = DNSServiceRegister(
            &raopServiceRef,
            0,
            0,
            raopName,
            "_raop._tcp",
            nil,
            nil,
            CFSwapInt16HostToBig(port16),
            UInt16(raopTXT.count),
            raopTXT,
            nil,
            nil
        )
        if raopErr == kDNSServiceErr_NoError, let ref = raopServiceRef {
            raopRef = ref
            raopSource = createDispatchSource(for: ref, label: "RAOP")
            logger.info("RAOP Bonjour service registered")
        } else {
            logger.error("Failed to register RAOP service: \(raopErr)")
        }
    }

    func stopAdvertising() {
        logger.info("Stopping Bonjour advertisement")
        airplaySource?.cancel()
        raopSource?.cancel()
        airplaySource = nil
        raopSource = nil
        if let ref = airplayRef {
            DNSServiceRefDeallocate(ref)
            airplayRef = nil
        }
        if let ref = raopRef {
            DNSServiceRefDeallocate(ref)
            raopRef = nil
        }
    }

    // MARK: - DNS-SD Event Processing

    /// Creates a dispatch source to process DNS-SD socket events.
    /// Without this, the registration may not complete on some systems.
    private func createDispatchSource(for ref: DNSServiceRef, label: String) -> DispatchSourceRead {
        let fd = DNSServiceRefSockFD(ref)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: dnssdQueue)
        source.setEventHandler { [weak self] in
            let err = DNSServiceProcessResult(ref)
            if err != kDNSServiceErr_NoError {
                self?.logger.error("\(label) DNS-SD process error: \(err)")
            }
        }
        source.setCancelHandler {
            // Cancel handler intentionally empty — cleanup is in stopAdvertising()
        }
        source.resume()
        return source
    }

}
