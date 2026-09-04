import Foundation

public enum ACPFileRead {
    public static let defaultMaxBytes = 512_000

    public static func contents(
        at url: URL,
        line: Int? = nil,
        limit: Int? = nil,
        maxBytes: Int = defaultMaxBytes
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let cap = max(maxBytes, 0)
        if line == nil, limit == nil {
            return decode(handle.readData(ofLength: cap))
        }
        return readLines(
            handle: handle,
            startLine: max(line ?? 1, 1),
            limit: max(limit ?? Int.max, 0),
            maxBytes: cap
        )
    }

    public static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readLines(
        handle: FileHandle,
        startLine: Int,
        limit: Int,
        maxBytes: Int
    ) -> String {
        let start = max(startLine - 1, 0)
        var buffer = Data()
        var index = 0
        var collected = Data()
        var taken = 0

        func appendLine(_ row: Data) -> Bool {
            defer { index += 1 }
            if index < start { return true }
            if taken >= limit { return false }
            if !collected.isEmpty {
                if collected.count + 1 > maxBytes { return false }
                collected.append(0x0A)
            }
            let remaining = maxBytes - collected.count
            if remaining <= 0 { return false }
            if row.count > remaining {
                collected.append(row.prefix(remaining))
                taken += 1
                return false
            }
            collected.append(row)
            taken += 1
            return taken < limit
        }

        while taken < limit, collected.count < maxBytes {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let row = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if !appendLine(row) {
                    return decode(collected)
                }
            }
        }
        if taken < limit, !buffer.isEmpty, collected.count < maxBytes {
            _ = appendLine(buffer)
        }
        return decode(collected)
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
