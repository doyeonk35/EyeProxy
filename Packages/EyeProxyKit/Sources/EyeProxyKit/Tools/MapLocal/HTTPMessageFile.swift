import EyeProxyCore
import Foundation
import UniformTypeIdentifiers

public enum HTTPMessageFileError: Error, Equatable {
    case badStatusLine
    case fileNotFound(String)
}

/// Proxyman 호환 HTTP 메시지 파일(상태줄, 헤더, 빈 줄, 본문) 읽기/쓰기.
public enum HTTPMessageFile {
    public static func parse(_ data: Data, fileURLBase: URL?) throws -> FlowResponse {
        let crlf = Data("\r\n\r\n".utf8), lf = Data("\n\n".utf8)
        let a = data.range(of: crlf), b = data.range(of: lf)
        let sep = [a, b].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        let head = sep.map { data[data.startIndex..<$0.lowerBound] } ?? data[...]
        var body = sep.map { Data(data[$0.upperBound...]) } ?? Data()

        // Character 단위로 쪼개면 "\r\n"이 한 글자라 바이트로 나눈다.
        let lines = head.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { line in
            String(decoding: line.last == UInt8(ascii: "\r") ? line.dropLast() : line, as: UTF8.self)
        }
        guard let first = lines.first else { throw HTTPMessageFileError.badStatusLine }

        // "HTTP/1.1 200 OK": reason은 공백을 포함하거나 비어 있을 수 있다.
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0].uppercased().hasPrefix("HTTP/"), let status = Int(parts[1]) else {
            throw HTTPMessageFileError.badStatusLine
        }
        let reason = parts.count == 3 ? String(parts[2]) : ""

        var headers: [HTTPHeader] = []
        var fileURL: String?
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("<file_url=\""), lower.hasSuffix("\">") {
                fileURL = String(trimmed.dropFirst(11).dropLast(2))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            if name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame { continue }
            headers.append(HTTPHeader(name: name, value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
        }

        if let fileURL {
            let path = (fileURL as NSString).expandingTildeInPath
            let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: path, relativeTo: fileURLBase.map { URL(fileURLWithPath: $0.path, isDirectory: true) } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
            ).standardizedFileURL
            guard let content = try? Data(contentsOf: url) else {
                throw HTTPMessageFileError.fileNotFound(url.path)
            }
            body = content
        }

        let length = "\(body.count)"
        var rewritten = false
        for i in headers.indices where headers[i].name.caseInsensitiveCompare("Content-Length") == .orderedSame {
            headers[i].value = length
            rewritten = true
        }
        if !rewritten { headers.append(HTTPHeader(name: "Content-Length", value: length)) }
        return FlowResponse(status: status, reason: reason, headers: headers, body: body)
    }

    public static func serialize(_ response: FlowResponse) -> Data {
        var text = "HTTP/1.1 \(response.status) \(response.reason)\n"
        for h in response.headers { text += "\(h.name): \(h.value)\n" }
        return Data((text + "\n").utf8) + response.body
    }

    public static func response(forLocalFile url: URL) throws -> FlowResponse {
        let body = try Data(contentsOf: url)
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return FlowResponse(status: 200, reason: "OK", headers: [HTTPHeader(name: "Content-Type", value: mime)], body: body)
    }
}
