import XCTest
import Network
import os
import dnssd
@testable import VirtualMirror

/// Session lifecycle: the UI must always return to waiting when a session ends,
/// and events from a replaced connection must not clobber the current one.
@MainActor
final class SessionLifecycleTests: XCTestCase {

    // MARK: - Manager session ownership

    func testEndOfSessionReturnsToIdle() async throws {
        let manager = makeManager()
        let session = UUID()
        manager.didStartConnecting(session: session, deviceName: "iPhone")
        try await waitForState(manager, .connecting("iPhone"))
        manager.didStartMirroring(session: session)
        try await waitForState(manager, .mirroring("iPhone"))
        manager.didEndSession(session)
        try await waitForState(manager, .idle)
    }

    func testEndOfReplacedSessionIsIgnored() async throws {
        let manager = makeManager()
        let old = UUID(), new = UUID()
        manager.didStartConnecting(session: old, deviceName: "Old")
        manager.didStartConnecting(session: new, deviceName: "New")
        try await waitForState(manager, .connecting("New"))

        manager.didEndSession(old)
        manager.didStartMirroring(session: new)
        try await waitForState(manager, .mirroring("New"))
    }

    func testErrorIsNotClobberedBySessionEvents() async throws {
        let manager = makeManager()
        let session = UUID()
        manager.didEncounterError("boom")
        try await waitForState(manager, .error("boom"))

        manager.didStartConnecting(session: session, deviceName: "iPhone")
        manager.didEndSession(session)
        try await settle()
        XCTAssertEqual(manager.state, .error("boom"))
    }

    // MARK: - TEARDOWN scope

    func testTeardownWithoutBodyEndsSession() {
        XCTAssertEqual(AirPlayConnection.teardownScope(body: Data()), .session)
    }

    func testTeardownWithoutStreamListEndsSession() throws {
        // iOS 27 ends mirroring with a TEARDOWN that names no stream type.
        let body = try bplist(["foo": 1])
        XCTAssertEqual(AirPlayConnection.teardownScope(body: body), .session)
    }

    func testTeardownWithStreamsIsSelective() throws {
        let body = try bplist(["streams": [["type": 110], ["type": 96]]])
        XCTAssertEqual(AirPlayConnection.teardownScope(body: body), .streams([110, 96]))
    }

    // MARK: - Volume

    func testAirPlayVolumeMapping() {
        XCTAssertEqual(AirPlayConnection.airPlayVolume(fromLinear: 1), 0)
        XCTAssertEqual(AirPlayConnection.airPlayVolume(fromLinear: 0), -144)
        XCTAssertEqual(AirPlayConnection.airPlayVolume(fromLinear: 0.5), -6.0206, accuracy: 0.001)
        XCTAssertEqual(AirPlayConnection.airPlayVolume(fromLinear: 0.001), -30)
    }

    // MARK: - Error messages

    func testPortInUseMessageNamesThePort() {
        let message = AirPlayManager.listenerErrorMessage(.posix(.EADDRINUSE), port: 47000)
        XCTAssertTrue(message.contains("47000"), message)
        XCTAssertTrue(message.contains("already in use"), message)
    }

    func testPolicyDeniedMentionsLocalNetwork() {
        let code = DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
        XCTAssertEqual(AirPlayManager.bonjourErrorMessage(code), AirPlayManager.localNetworkDeniedMessage)
        XCTAssertEqual(AirPlayManager.listenerErrorMessage(.dns(code), port: 1), AirPlayManager.localNetworkDeniedMessage)
    }

    // MARK: - End to end over a real listener

    /// A second sender evicts the first; the evicted session must be reported
    /// as ended (it used to leave the UI stuck), and a typeless TEARDOWN from
    /// the new sender returns to idle while its connection stays open.
    func testEvictionAndTeardownOverTheWire() async throws {
        let manager = AirPlayManager(identity: ReceiverIdentity(slot: 7, name: "Test Receiver"))
        let server = AirPlayServer(manager: manager)
        let port = manager.identity.ports.airplay
        server.start(port: port)
        defer { server.stop() }
        try await settle()

        let phoneA = try await RTSPClient.connect(port: port)
        defer { phoneA.close() }
        phoneA.send(try RTSPClient.setup(name: "Phone A", cseq: 1))
        try await waitForState(manager, .connecting("Phone A"))

        let phoneB = try await RTSPClient.connect(port: port)
        defer { phoneB.close() }
        try await waitForState(manager, .idle)

        phoneB.send(try RTSPClient.setup(name: "Phone B", cseq: 1))
        try await waitForState(manager, .connecting("Phone B"))
        phoneB.send(RTSPClient.request("RECORD", cseq: 2))
        try await waitForState(manager, .mirroring("Phone B"))
        phoneB.send(RTSPClient.request("TEARDOWN", cseq: 3))
        try await waitForState(manager, .idle)

        // The sender re-establishes the mirror stream on the same connection
        // without another RECORD: the UI resumes mirroring.
        let streams = try bplist(["streams": [["type": 110, "streamConnectionID": 1]]])
        phoneB.send(RTSPClient.request("SETUP", cseq: 4, body: streams, contentType: "application/x-apple-binary-plist"))
        try await waitForState(manager, .mirroring("Phone B"))
    }

    // MARK: - Helpers

    private func makeManager() -> AirPlayManager {
        AirPlayManager(identity: ReceiverIdentity(slot: 6, name: "Unit"))
    }

    private func bplist(_ object: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }

    /// Lets queued `Task { @MainActor in … }` hops run.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    private func waitForState(_ manager: AirPlayManager, _ expected: AirPlayState,
                              timeout: Duration = .seconds(5),
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + timeout
        while manager.state != expected {
            if ContinuousClock.now > deadline {
                XCTFail("Timed out waiting for \(expected); state is \(manager.state)", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Minimal RTSP sender for driving AirPlayConnection over loopback.
private final class RTSPClient {
    let connection: NWConnection

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func connect(port: UInt16) async throws -> RTSPClient {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let client = RTSPClient(connection: connection)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Only one of ready/failed/waiting may resume the continuation.
            let pending = OSAllocatedUnfairLock(initialState: Optional(continuation))
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    pending.withLock { $0.take() }?.resume()
                case .failed(let error), .waiting(let error):
                    pending.withLock { $0.take() }?.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "test.rtsp-client"))
        }
        client.drain()
        return client
    }

    /// Keep reading so responses don't back up; their content isn't asserted.
    private func drain() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, error in
            guard !isComplete, error == nil else { return }
            self?.drain()
        }
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        connection.cancel()
    }

    static func request(_ method: String, cseq: Int, body: Data = Data(), contentType: String? = nil) -> Data {
        var head = "\(method) rtsp://127.0.0.1/1 RTSP/1.0\r\nCSeq: \(cseq)\r\n"
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        if !body.isEmpty { head += "Content-Length: \(body.count)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    /// A session SETUP carrying the sender's name (and an eiv, which marks it as
    /// the session phase) — enough to move the receiver to `.connecting`.
    static func setup(name: String, cseq: Int) throws -> Data {
        let body = try PropertyListSerialization.data(
            fromPropertyList: ["eiv": Data(repeating: 0, count: 16), "name": name],
            format: .binary, options: 0)
        return request("SETUP", cseq: cseq, body: body, contentType: "application/x-apple-binary-plist")
    }
}
