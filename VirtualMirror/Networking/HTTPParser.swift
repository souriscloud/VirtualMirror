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
    }

    static func parse(data: Data) -> ParseResult {
        // Find the header/body separator \r\n\r\n
        guard let headerEnd = findHeaderEnd(in: data) else {
            return .needsMore
        }

        let headerData = data[data.startIndex..<headerEnd]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .needsMore
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

        // Determine body length
        let bodyStart = headerEnd + 4 // skip \r\n\r\n
        let contentLength = Int(headers["Content-Length"] ?? headers["content-length"] ?? "0") ?? 0

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

    private static func findHeaderEnd(in data: Data) -> Int? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        let bytes = Array(data)
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) {
            if bytes[i] == separator[0] && bytes[i+1] == separator[1] &&
               bytes[i+2] == separator[2] && bytes[i+3] == separator[3] {
                return i
            }
        }
        return nil
    }
}
