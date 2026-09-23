import XCTest
@testable import VirtualMirror

final class HTTPResponseTests: XCTestCase {

    func testOkResponseContainsStatus200() throws {
        let response = HTTPResponse.ok(cseq: "1")
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("CSeq: 1"))
        XCTAssertTrue(str.contains("Server: AirTunes/220.68"))
    }

    func testRTSPResponse() throws {
        let response = HTTPResponse.ok(cseq: "5", isRTSP: true)
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(str.hasPrefix("RTSP/1.0 200 OK\r\n"))
    }

    func testResponseWithBody() throws {
        let body = Data("test body".utf8)
        let response = HTTPResponse.ok(cseq: "2", body: body, contentType: "text/plain")
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(str.contains("Content-Length: 9"))
        XCTAssertTrue(str.contains("Content-Type: text/plain"))
        XCTAssertTrue(str.hasSuffix("test body"))
    }

    func testBplistResponse() throws {
        let body = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) // "bplist"
        let response = HTTPResponse.okBplist(cseq: "3", body: body)
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(str.contains("Content-Type: application/x-apple-binary-plist"))
    }

    func testErrorResponse() throws {
        let response = HTTPResponse.build(status: 400, statusText: "Bad Request", cseq: "4")
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }

    func testResponseWithoutCseq() throws {
        let response = HTTPResponse.ok()
        let str = try XCTUnwrap(String(data: response, encoding: .utf8))
        XCTAssertFalse(str.contains("CSeq"))
    }
}
