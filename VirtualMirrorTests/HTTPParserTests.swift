import XCTest
@testable import VirtualMirror

final class HTTPParserTests: XCTestCase {

    // MARK: - Basic Parsing

    func testParseSimpleGetRequest() {
        let raw = "GET /info HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, let consumed) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/info")
        XCTAssertEqual(request.headers["Host"], "localhost")
        XCTAssertEqual(consumed, data.count)
    }

    func testParsePostWithBody() {
        let body = "hello world"
        let raw = "POST /pair-setup HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, let consumed) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/pair-setup")
        XCTAssertEqual(request.body, Data(body.utf8))
        XCTAssertEqual(consumed, data.count)
    }

    func testParseRTSPSetupRequest() {
        let raw = "SETUP rtsp://localhost RTSP/1.0\r\nCSeq: 3\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, _) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertEqual(request.method, "SETUP")
        XCTAssertEqual(request.cseq, "3")
    }

    // MARK: - Incomplete Data

    func testNeedsMoreForIncompleteHeaders() {
        let raw = "GET /info HTTP/1.1\r\nHost: local"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .needsMore = result else {
            XCTFail("Expected needsMore")
            return
        }
    }

    func testNeedsMoreForIncompleteBody() {
        let raw = "POST /data HTTP/1.1\r\nContent-Length: 100\r\n\r\npartial"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .needsMore = result else {
            XCTFail("Expected needsMore for incomplete body")
            return
        }
    }

    // MARK: - Edge Cases

    func testEmptyBody() {
        let raw = "GET /info HTTP/1.1\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, _) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertTrue(request.body.isEmpty)
    }

    func testMultipleRequestsInBuffer() {
        let raw1 = "GET /info HTTP/1.1\r\n\r\n"
        let raw2 = "POST /feedback HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let data = Data((raw1 + raw2).utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, let consumed) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(consumed, Data(raw1.utf8).count)

        // Parse the remainder
        let remaining = Data(data.suffix(from: consumed))
        let result2 = HTTPParser.parse(data: remaining)
        guard case .parsed(let request2, _) = result2 else {
            XCTFail("Expected second parsed result")
            return
        }
        XCTAssertEqual(request2.method, "POST")
        XCTAssertEqual(request2.path, "/feedback")
    }

    func testCaseInsensitiveContentLength() {
        let raw = "POST /data HTTP/1.1\r\ncontent-length: 5\r\n\r\nhello"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .parsed(let request, _) = result else {
            XCTFail("Expected parsed result")
            return
        }
        XCTAssertEqual(request.contentLength, 5)
        XCTAssertEqual(request.body, Data("hello".utf8))
    }

    // MARK: - Security / DoS Protection

    func testRejectsOversizedHeaders() {
        // Create a header that exceeds the max size
        let longHeader = String(repeating: "X", count: HTTPParser.maxHeaderSize + 1)
        let raw = "GET /info HTTP/1.1\r\nX-Long: \(longHeader)\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .error = result else {
            XCTFail("Expected error for oversized headers")
            return
        }
    }

    func testRejectsNegativeContentLength() {
        let raw = "POST /data HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .error = result else {
            XCTFail("Expected error for negative content length")
            return
        }
    }

    func testRejectsExcessiveContentLength() {
        let raw = "POST /data HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n"
        let data = Data(raw.utf8)
        let result = HTTPParser.parse(data: data)

        guard case .error = result else {
            XCTFail("Expected error for excessive content length")
            return
        }
    }
}
