import Foundation
import dnssd
import os

/// Advertises AirPlay and RAOP Bonjour services using the DNS-SD C API.
/// Replaces the deprecated NetService-based implementation.
final class AirPlayService {
    private let logger = Logger(subsystem: "cloud.souris.virtualmirror", category: "AirPlayService")

    private var airplayRef: DNSServiceRef?
    private var raopRef: DNSServiceRef?

    /// Shared queue for processing DNS-SD events
    private let dnssdQueue = DispatchQueue(label: "cloud.souris.virtualmirror.dnssd")
    private var airplaySource: DispatchSourceRead?
    private var raopSource: DispatchSourceRead?

    /// Called with the DNS-SD error code if a registration fails, synchronously
    /// or later in the registration callback (e.g. Local Network access denied).
    var onFailure: ((DNSServiceErrorType) -> Void)?

    /// Context handed to the C registration callback. Retained until the
    /// source's cancel handler runs, which is after the last callback can fire.
    private final class RegistrationContext {
        let onFailure: ((DNSServiceErrorType) -> Void)?
        init(onFailure: ((DNSServiceErrorType) -> Void)?) {
            self.onFailure = onFailure
        }
    }

    private static let registerCallback: DNSServiceRegisterReply = { _, _, errorCode, _, _, _, context in
        guard errorCode != kDNSServiceErr_NoError, let context else { return }
        let registration = Unmanaged<RegistrationContext>.fromOpaque(context).takeUnretainedValue()
        registration.onFailure?(errorCode)
    }

    func startAdvertising(identity: ReceiverIdentity) {
        let port = Int(identity.ports.airplay)
        logger.info("Starting Bonjour advertisement for \"\(identity.name)\" on port \(port)")

        let port16 = UInt16(port)

        // Advertise _airplay._tcp
        let airplayTXT = AirPlayConfig.airplayTXTRecord(identity)
        var airplayServiceRef: DNSServiceRef?
        let airplayContext = Unmanaged.passRetained(RegistrationContext(onFailure: onFailure))
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
            AirPlayService.registerCallback,
            airplayContext.toOpaque()
        )
        if airplayErr == kDNSServiceErr_NoError, let ref = airplayServiceRef {
            airplayRef = ref
            airplaySource = createDispatchSource(for: ref, label: "AirPlay", context: airplayContext)
            logger.info("AirPlay Bonjour service registered")
        } else {
            airplayContext.release()
            logger.error("Failed to register AirPlay service: \(airplayErr)")
            onFailure?(airplayErr)
        }

        // Advertise _raop._tcp with deviceID@name format
        let raopName = "\(identity.deviceID.replacingOccurrences(of: ":", with: ""))@\(identity.name)"
        let raopTXT = AirPlayConfig.raopTXTRecord(identity)
        var raopServiceRef: DNSServiceRef?
        let raopContext = Unmanaged.passRetained(RegistrationContext(onFailure: onFailure))
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
            AirPlayService.registerCallback,
            raopContext.toOpaque()
        )
        if raopErr == kDNSServiceErr_NoError, let ref = raopServiceRef {
            raopRef = ref
            raopSource = createDispatchSource(for: ref, label: "RAOP", context: raopContext)
            logger.info("RAOP Bonjour service registered")
        } else {
            raopContext.release()
            logger.error("Failed to register RAOP service: \(raopErr)")
            onFailure?(raopErr)
        }
    }

    /// Re-advertises under a new name (used by live rename). The TCP listener
    /// and any active mirroring session are untouched — only the Bonjour record
    /// the iPhone browses changes.
    func updateName(identity: ReceiverIdentity) {
        stopAdvertising()
        startAdvertising(identity: identity)
    }

    func stopAdvertising() {
        logger.info("Stopping Bonjour advertisement")
        // Each source's cancel handler deallocates its DNSServiceRef (and the
        // callback context), so a ref is never freed while an event handler on
        // dnssdQueue could still be using it. A ref is only stored with a source.
        airplaySource?.cancel()
        raopSource?.cancel()
        airplaySource = nil
        raopSource = nil
        airplayRef = nil
        raopRef = nil
    }

    // MARK: - DNS-SD Event Processing

    /// Creates a dispatch source to process DNS-SD socket events.
    /// Without this, the registration may not complete on some systems.
    private func createDispatchSource(for ref: DNSServiceRef, label: String, context: Unmanaged<RegistrationContext>) -> DispatchSourceRead {
        let fd = DNSServiceRefSockFD(ref)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: dnssdQueue)
        source.setEventHandler { [weak self] in
            let err = DNSServiceProcessResult(ref)
            if err != kDNSServiceErr_NoError {
                self?.logger.error("\(label) DNS-SD process error: \(err)")
            }
        }
        source.setCancelHandler {
            DNSServiceRefDeallocate(ref)
            context.release()
        }
        source.resume()
        return source
    }

}
