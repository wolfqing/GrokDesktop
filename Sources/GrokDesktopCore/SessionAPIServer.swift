import Darwin
import Foundation

public enum MirrorExposure: String, Codable, Sendable, Equatable, CaseIterable {
    case loopback
    case lan
    case tunnel

    public var bindAddress: String {
        switch self {
        case .loopback, .tunnel: return "127.0.0.1"
        case .lan: return "0.0.0.0"
        }
    }
}

public enum MirrorBind {
    /// The settings UI never renders the bearer token.
    public static func uiToken(stored: String) -> String {
        stored.isEmpty ? "" : "••••"
    }

    public static func tunnelCommand(port: UInt16) -> [String] {
        ["cloudflared", "tunnel", "--url", "http://127.0.0.1:\(port)"]
    }

    /// Address a phone on this Mac, or on the same network, can open. The token stays out of the string.
    public static func displayURL(exposure: MirrorExposure, port: UInt16, lanHost: String) -> String {
        guard port > 0 else { return "" }
        switch exposure {
        case .loopback:
            return "http://127.0.0.1:\(port)"
        case .lan:
            guard !lanHost.isEmpty else { return "" }
            return "http://\(lanHost):\(port)"
        case .tunnel:
            return ""
        }
    }

    /// First usable IPv4. Skips loopback and link-local.
    public static func lanHost(addresses: [String]) -> String {
        for address in addresses {
            if address == "127.0.0.1" || address.hasPrefix("169.254.") || address.contains(":") { continue }
            return address
        }
        return ""
    }

    public static func tunnelURL(in text: String) -> String? {
        guard let range = text.range(
            of: #"https://[A-Za-z0-9-]+\.trycloudflare\.com"#,
            options: .regularExpression
        ) else { return nil }
        return String(text[range])
    }

    /// IPv4 addresses currently assigned on this Mac.
    public static func interfaceAddresses() -> [String] {
        var results: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                results.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return results
    }
}

public enum SessionAPIError: Error, Equatable {
    case bindFailed
}

/// Loopback HTTP API. Continues an existing session by queueing. Never creates a session and never interrupts one.
public final class SessionAPIServer: @unchecked Sendable {
    public struct ListedSession: Equatable, Sendable {
        public var id: String
        public var busy: Bool

        public init(id: String, busy: Bool) {
            self.id = id
            self.busy = busy
        }
    }

    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var token = ""
    private var sessions: [ListedSession] = []
    private var queueLog: [String: [String]] = [:]
    private var stopped = false
    private var queuedHandler: ((String, String) -> Void)?
    private let serveQueue = DispatchQueue(label: "com.wolfqing.GrokDesktop.session-api")

    /// Fired after a continue is stored. The app drains it into the live session.
    public var onQueued: ((String, String) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return queuedHandler
        }
        set {
            lock.lock()
            queuedHandler = newValue
            lock.unlock()
        }
    }

    public private(set) var boundHost = "127.0.0.1"
    public private(set) var port: UInt16 = 0

    public init() {}

    public func update(sessions: [ListedSession]) {
        lock.lock()
        self.sessions = sessions
        lock.unlock()
    }

    public func snapshot() -> [ListedSession] {
        lock.lock()
        defer { lock.unlock() }
        return sessions
    }

    public func queuedText(id: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return queueLog[id] ?? []
    }

    /// Reads and clears the queued continues for one existing session.
    public func takeQueued(id: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let items = queueLog[id] ?? []
        queueLog[id] = nil
        return items
    }

    public func start(token: String, exposure: MirrorExposure = .loopback) throws -> UInt16 {
        stop()
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SessionAPIError.bindFailed }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        let host = exposure.bindAddress
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            Darwin.close(fd)
            throw SessionAPIError.bindFailed
        }
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw SessionAPIError.bindFailed
        }
        var got = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.getsockname(fd, sa, &length)
            }
        }
        guard named == 0 else {
            Darwin.close(fd)
            throw SessionAPIError.bindFailed
        }
        lock.lock()
        listenFD = fd
        self.token = token
        stopped = false
        queueLog = [:]
        boundHost = host
        port = UInt16(bigEndian: got.sin_port)
        let ready = port
        lock.unlock()
        serveQueue.async { [weak self] in
            self?.loop()
        }
        return ready
    }

    public func stop() {
        lock.lock()
        stopped = true
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func loop() {
        while true {
            let fd = currentFD()
            if fd < 0 || isStopped() { break }
            var slot = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&slot, 1, 200)
            if isStopped() { break }
            if ready < 0 { break }
            if ready == 0 { continue }
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 { continue }
            var noSig: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout<Int32>.size))
            handle(client)
            Darwin.close(client)
        }
    }

    private func currentFD() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return listenFD
    }

    private func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func handle(_ client: Int32) {
        let raw = readRequest(client)
        let lines = headerLines(raw)
        guard let request = lines.first else {
            writeJSON(client, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }
        let parts = request.split(separator: " ")
        guard parts.count >= 2 else {
            writeJSON(client, status: 400, body: #"{"error":"bad_request"}"#)
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        if !authorized(lines) {
            writeJSON(client, status: 401, body: #"{"error":"unauthorized"}"#)
            return
        }
        if method == "GET", path == "/v1/sessions" {
            writeJSON(client, status: 200, body: listJSON())
            return
        }
        if method == "POST", let id = continueID(path) {
            let text = bodyText(raw)
            lock.lock()
            guard let index = sessions.firstIndex(where: { $0.id == id }) else {
                lock.unlock()
                writeJSON(client, status: 404, body: #"{"error":"not_found"}"#)
                return
            }
            let busy = sessions[index].busy
            queueLog[id, default: []].append(text)
            let callback = queuedHandler
            lock.unlock()
            callback?(id, text)
            if busy {
                writeJSON(client, status: 202, body: #"{"status":"queued"}"#)
            } else {
                writeJSON(client, status: 200, body: #"{"status":"accepted"}"#)
            }
            return
        }
        writeJSON(client, status: 404, body: #"{"error":"not_found"}"#)
    }

    private func continueID(_ path: String) -> String? {
        let prefix = "/v1/sessions/"
        let suffix = "/continue"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        let id = String(path[start..<end])
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
            return nil
        }
        return id
    }

    /// Accepts CR, LF, and CRLF. Some HTTP stacks on this OS omit LF.
    private func headerLines(_ raw: String) -> [String] {
        let header: Substring
        if let range = raw.range(of: "\r\n\r\n") {
            header = raw[..<range.lowerBound]
        } else if let range = raw.range(of: "\n\n") {
            header = raw[..<range.lowerBound]
        } else if let range = raw.range(of: "\r\r") {
            header = raw[..<range.lowerBound]
        } else {
            header = Substring(raw)
        }
        let normalized = header.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func authorized(_ lines: [String]) -> Bool {
        lock.lock()
        let expected = token
        lock.unlock()
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("authorization:") {
                let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
                return value == "Bearer \(expected)"
            }
        }
        return false
    }

    private func listJSON() -> String {
        lock.lock()
        let rows = sessions
        lock.unlock()
        let encoded = rows.map { #"{"id":\#(jsonString($0.id)),"busy":\#($0.busy ? "true" : "false")}"# }
        return #"{"sessions":[\#(encoded.joined(separator: ","))]}"#
    }

    private func bodyText(_ raw: String) -> String {
        let body: String
        if let range = raw.range(of: "\r\n\r\n") {
            body = String(raw[range.upperBound...])
        } else if let range = raw.range(of: "\n\n") {
            body = String(raw[range.upperBound...])
        } else if let range = raw.range(of: "\r\r") {
            body = String(raw[range.upperBound...])
        } else {
            return ""
        }
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String
        else { return "" }
        return text
    }

    private func readRequest(_ fd: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 65_536 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if let marker = headerMarker(in: data) {
                let header = String(data: data.subdata(in: 0..<marker.upperBound), encoding: .utf8) ?? ""
                let length = contentLength(header)
                if data.count - marker.upperBound >= length { break }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func headerMarker(in data: Data) -> Range<Data.Index>? {
        let patterns = [Data("\r\n\r\n".utf8), Data("\n\n".utf8), Data("\r\r".utf8)]
        return patterns.compactMap { data.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
    }

    private func contentLength(_ header: String) -> Int {
        let normalized = header.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("content-length:") {
                let value = text.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func writeJSON(_ fd: Int32, status: Int, body: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(head.utf8)
        packet.append(payload)
        packet.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = Darwin.write(fd, base, raw.count)
        }
    }

    private func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            default:
                if scalar.value < 0x20 { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}
