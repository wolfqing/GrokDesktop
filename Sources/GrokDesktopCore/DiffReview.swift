import Foundation

public struct ReviewedFile: Equatable, Sendable {
    public var path: String
    public var baseline: String
    public var working: String
    public var accepted: Bool

    public init(path: String, baseline: String, working: String, accepted: Bool = false) {
        self.path = path
        self.baseline = baseline
        self.working = working
        self.accepted = accepted
    }
}

public enum DiffReview {
    public enum Action: String, Equatable, Sendable {
        case accept
        case reject
        case revert
    }

    public static func next(_ file: ReviewedFile, action: Action) -> ReviewedFile {
        var copy = file
        switch action {
        case .accept:
            copy.accepted = true
        case .reject, .revert:
            copy.working = file.baseline
            copy.accepted = false
        }
        return copy
    }

    /// Accept keeps the working bytes. Reject and revert write the baseline back.
    public static func apply(
        action: Action,
        files: [ReviewedFile],
        paths: [String],
        root: URL
    ) throws -> [ReviewedFile] {
        let chosen = Set(paths)
        return try files.map { file in
            guard chosen.contains(file.path) else { return file }
            let updated = next(file, action: action)
            let url = root.appendingPathComponent(updated.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = action == .accept ? updated.working : updated.baseline
            try text.write(to: url, atomically: true, encoding: .utf8)
            return updated
        }
    }
}
