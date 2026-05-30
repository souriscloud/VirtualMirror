import XCTest
@testable import VirtualMirror

/// Hardening / malformed-input tests for the HTTP/RTSP parser.
///
/// VirtualMirror parses untrusted bytes straight off the network, so the parser
/// must never crash and must reject ambiguous input rather than silently
/// mis-parsing it (which could desync the request stream).
final class HTTPParserHardeningTests: XCTestCase {

    // MARK: - Content-Length

    func testMalformedContentLengthIsError() {
        // A present-but-unparseable Content-Length must be a hard error, not 0.
        // (Surrounding whitespace is trimmed per HTTP, so " 5" is valid and not listed here.)
        for bad in ["abc", "0x10", "1e3", "12.5", "5x", "", "++5", "0xFF"] {
            let raw = "POST /x HTTP/1.1\r\nContent-Length: \(bad)\r\n\r\nBODY"
            let result = HTTPParser.parse(data: Data(raw.utf8))
            guard case .error = result else {
                XCTFail("Expected .error for Content-Length '\(bad)', got \(result)")
                continue
            }
        }
    }

    func testNegativeContentLengthIsError() {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
        guard case .error = HTTPParser.parse(data: Data(raw.utf8)) else {
            return XCTFail("Expected .error for negative Content-Length")
        }
    }

    func testAbsentContentLengthIsBodylessParse() {
        // No Content-Length at all is legitimate and means an empty body.
        let raw = "GET /info HTTP/1.1\r\nHost: x\r\n\r\n"
        guard case .parsed(let req, _) = HTTPParser.parse(data: Data(raw.utf8)) else {
            return XCTFail("Expected .parsed for header with no Content-Length")
        }
        XCTAssertTrue(req.body.isEmpty)
    }

    func testValidContentLengthStillParses() {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 4\r\n\r\nDATA"
        guard case .parsed(let req, let consumed) = HTTPParser.parse(data: Data(raw.utf8)) else {
            return XCTFail("Expected .parsed for valid Content-Length")
        }
        XCTAssertEqual(req.body, Data("DATA".utf8))
        XCTAssertEqual(consumed, raw.utf8.count)
    }

    // MARK: - Encoding

    func testInvalidUTF8HeaderIsError() {
        // A complete header block (terminated by CRLFCRLF) that isn't valid UTF-8
        // is malformed input and must fail fast rather than stall on .needsMore.
        var data = Data([0xFF, 0xFE, 0x80, 0x81]) // invalid UTF-8 lead bytes
        data.append(Data("\r\n\r\n".utf8))
        guard case .error = HTTPParser.parse(data: data) else {
            return XCTFail("Expected .error for non-UTF8 header block")
        }
    }

    // MARK: - Fuzz

    /// Feed a large amount of random binary and assert the parser never crashes
    /// and always returns one of its defined results. Uses a fixed seed so any
    /// failure is reproducible.
    func testFuzzRandomBinaryNeverCrashes() {
        var rng = SeededRNG(seed: 0xA1B2_C3D4_E5F6_0718)
        for _ in 0..<5_000 {
            let len = Int(rng.next() % 600)
            var bytes = [UInt8]()
            bytes.reserveCapacity(len)
            for _ in 0..<len { bytes.append(UInt8(rng.next() & 0xFF)) }
            switch HTTPParser.parse(data: Data(bytes)) {
            case .needsMore, .parsed, .error:
                break // any defined result is acceptable; the point is no crash
            }
        }
    }

    /// Fuzz around a valid request skeleton with random CRLF/colon corruption.
    func testFuzzCorruptedRequestLinesNeverCrash() {
        var rng = SeededRNG(seed: 0x0F0F_0F0F_1234_5678)
        let template = Array("POST /pair-setup HTTP/1.1\r\nContent-Length: 8\r\n\r\nPAYLOAD!".utf8)
        for _ in 0..<5_000 {
            var bytes = template
            let flips = Int(rng.next() % 6)
            for _ in 0..<flips {
                let idx = Int(rng.next() % UInt64(bytes.count))
                bytes[idx] = UInt8(rng.next() & 0xFF)
            }
            switch HTTPParser.parse(data: Data(bytes)) {
            case .needsMore, .parsed, .error:
                break
            }
        }
    }
}

/// Minimal deterministic PRNG (SplitMix64) for reproducible fuzzing.
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
