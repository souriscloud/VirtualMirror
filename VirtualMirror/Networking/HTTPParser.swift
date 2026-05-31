import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    var cseq: String? { headers["CSeq"] ?? headers["cseq"] }
    var contentType: String? { headers["Content-Type"] ?? headers["content-type"] }
    var contentLength: Int? {
        if let cl = headers["Content-Length"] ?? headers["content-length"] {
            return Int(cl)
        }
        return nil
    }
}

class HTTPParser {
    enum ParseResult {
        case needsMore
        case parsed(HTTPRequest, Int) // request + total bytes consumed
        case error(String) // parsing error (malformed input)
    }

    /// Maximum allowed header size (64 KB) to prevent memory exhaustion from oversized headers.
    static let maxHeaderSize = 64 * 1024
    /// Maximum allowed Content-Length (50 MB) to prevent memory exhaustion from oversized bodies.
    static let maxContentLength = 50 * 1024 * 1024

    static func parse(data: Data) -> ParseResult {
        // Reject headers that exceed the size limit before we even find the separator
        if data.count > maxHeaderSize {
            if findHeaderEnd(in: data, limit: maxHeaderSize) == nil {
                return .error("Header exceeds maximum size (\(maxHeaderSize) bytes)")
            }
        }

        // Find the header/body separator \r\n\r\n
        guard let headerEnd = findHeaderEnd(in: data, limit: min(data.count, maxHeaderSize)) else {
            return .needsMore
        }

        // headerData is a complete header block (terminated by \r\n\r\n), so
        // invalid UTF-8 here is malformed input, not a partial read — fail fast
        // rather than waiting forever for "more" bytes that will never fix it.
        let headerData = data[data.startIndex..<headerEnd]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .error("Header block is not valid UTF-8")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .needsMore }

        // Parse request line
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return .needsMore }

        let method = String(parts[0])
        let path = String(parts[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines {
            guard !line.isEmpty else { continue }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Determine body length. A *present* Content-Length that doesn't parse
        // to a non-negative integer is a hard error — silently treating it as 0
        // would desync the stream (the body would be parsed as the next request).
        let bodyStart = headerEnd + 4 // skip \r\n\r\n
        let contentLength: Int
        if let clString = headers["Content-Length"] ?? headers["content-length"] {
            guard let cl = Int(clString), cl >= 0 else {
                return .error("Malformed Content-Length: \(clString)")
            }
            contentLength = cl
        } else {
            contentLength = 0
        }

        if contentLength > maxContentLength {
            return .error("Content-Length \(contentLength) exceeds maximum (\(maxContentLength))")
        }

        if contentLength > 0 {
            let totalNeeded = bodyStart + contentLength
            guard data.count >= totalNeeded else {
                return .needsMore
            }
            let body = data[bodyStart..<(bodyStart + contentLength)]
            return .parsed(HTTPRequest(method: method, path: path, headers: headers, body: Data(body)), totalNeeded)
        } else {
            return .parsed(HTTPRequest(method: method, path: path, headers: headers, body: Data()), bodyStart)
        }
    }

    private static func findHeaderEnd(in data: Data, limit: Int) -> Int? {
        let searchEnd = min(data.count, limit)
        guard searchEnd >= 4 else { return nil }
        return data.withUnsafeBytes { ptr -> Int? in
            let bytes = ptr.bindMemory(to: UInt8.self)
            for i in 0...(searchEnd - 4) {
                if bytes[i] == 0x0D && bytes[i+1] == 0x0A &&
                   bytes[i+2] == 0x0D && bytes[i+3] == 0x0A {
                    return i
                }
            }
            return nil
        }
    }
}
