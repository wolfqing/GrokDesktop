import Foundation

public enum SessionDataMode: String, Codable, Sendable, Equatable {
    case independent
    case shared
}

/// Visible history is exactly one side. Switching mode never copies the other side in.
public struct SessionDataLayout: Equatable, Sendable {
    public var mode: SessionDataMode
    public var independentIDs: [String]
    public var sharedIDs: [String]

    public init(mode: SessionDataMode, independentIDs: [String], sharedIDs: [String]) {
        self.mode = mode
        self.independentIDs = independentIDs
        self.sharedIDs = sharedIDs
    }

    public func visibleIDs() -> [String] {
        switch mode {
        case .independent: return independentIDs
        case .shared: return sharedIDs
        }
    }

    public var mergesHistories: Bool {
        Set(visibleIDs()) != Set(mode == .independent ? independentIDs : sharedIDs)
    }

    public static func root(mode: SessionDataMode, independent: URL, shared: URL) -> URL {
        mode == .independent ? independent : shared
    }

    /// Writes the active id list and leaves the other root's file byte-for-byte alone.
    public static func writeActive(
        mode: SessionDataMode,
        ids: [String],
        independent: URL,
        shared: URL
    ) throws {
        let active = root(mode: mode, independent: independent, shared: shared)
        let other = mode == .independent ? shared : independent
        let otherURL = other.appendingPathComponent("ids.txt")
        let before = try? Data(contentsOf: otherURL)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try ids.joined(separator: "\n").write(
            to: active.appendingPathComponent("ids.txt"),
            atomically: true,
            encoding: .utf8
        )
        let after = try? Data(contentsOf: otherURL)
        if before != after {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
