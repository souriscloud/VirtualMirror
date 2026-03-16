import XCTest
@testable import VirtualMirror

final class AirPlayStateTests: XCTestCase {

    // MARK: - Equality

    func testIdleEquality() {
        XCTAssertEqual(AirPlayState.idle, AirPlayState.idle)
    }

    func testConnectingEquality() {
        XCTAssertEqual(AirPlayState.connecting("iPhone"), AirPlayState.connecting("iPhone"))
        XCTAssertNotEqual(AirPlayState.connecting("iPhone"), AirPlayState.connecting("iPad"))
    }

    func testMirroringEquality() {
        XCTAssertEqual(AirPlayState.mirroring("iPhone"), AirPlayState.mirroring("iPhone"))
        XCTAssertNotEqual(AirPlayState.mirroring("iPhone"), AirPlayState.mirroring("iPad"))
    }

    func testErrorEquality() {
        XCTAssertEqual(AirPlayState.error("timeout"), AirPlayState.error("timeout"))
        XCTAssertNotEqual(AirPlayState.error("timeout"), AirPlayState.error("refused"))
    }

    func testDifferentStatesNotEqual() {
        XCTAssertNotEqual(AirPlayState.idle, AirPlayState.connecting("iPhone"))
        XCTAssertNotEqual(AirPlayState.connecting("iPhone"), AirPlayState.mirroring("iPhone"))
        XCTAssertNotEqual(AirPlayState.idle, AirPlayState.error("test"))
    }

    // MARK: - Device Name

    func testDeviceNameForConnecting() {
        let state = AirPlayState.connecting("My iPhone")
        XCTAssertEqual(state.deviceName, "My iPhone")
    }

    func testDeviceNameForMirroring() {
        let state = AirPlayState.mirroring("My iPad")
        XCTAssertEqual(state.deviceName, "My iPad")
    }

    func testDeviceNameForIdle() {
        XCTAssertNil(AirPlayState.idle.deviceName)
    }

    func testDeviceNameForError() {
        XCTAssertNil(AirPlayState.error("something").deviceName)
    }
}
