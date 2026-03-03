import Foundation

struct HTTPResponse {
    static func build(
        status: Int = 200,
        statusText: String = "OK",
        headers: [String: String] = [:],
        body: Data = Data(),
        cseq: String? = nil,
        isRTSP: Bool = false
    ) -> Data {
        let proto = isRTSP ? "RTSP/1.0" : "HTTP/1.1"
        var response = "\(proto) \(status) \(statusText)\r\n"

        var allHeaders = headers
        if let cseq = cseq {
            allHeaders["CSeq"] = cseq
        }
        if !body.isEmpty {
            allHeaders["Content-Length"] = "\(body.count)"
        }
        allHeaders["Server"] = "AirTunes/220.68"

        for (key, value) in allHeaders {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        if !body.isEmpty {
            data.append(body)
        }
        return data
    }

    static func ok(cseq: String? = nil, body: Data = Data(), contentType: String? = nil, isRTSP: Bool = false) -> Data {
        var headers: [String: String] = [:]
        if let contentType = contentType {
            headers["Content-Type"] = contentType
        }
        return build(status: 200, headers: headers, body: body, cseq: cseq, isRTSP: isRTSP)
    }

    static func okBplist(cseq: String? = nil, body: Data, isRTSP: Bool = false) -> Data {
        return ok(cseq: cseq, body: body, contentType: "application/x-apple-binary-plist", isRTSP: isRTSP)
    }
}
