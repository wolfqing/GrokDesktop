import Foundation

/// Keeps earlier dictated sentences when a later recognition result replaces them.
public struct SpeechTranscript: Equatable, Sendable {
    public private(set) var kept = ""
    public private(set) var current = ""

    public init() {}

    public var text: String {
        Self.join(kept, current)
    }

    public mutating func absorb(_ raw: String, isFinal: Bool) {
        let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }
        if !current.isEmpty && !Self.continues(current, piece) {
            kept = Self.join(kept, current)
        }
        if isFinal {
            kept = Self.join(kept, piece)
            current = ""
        } else {
            current = piece
        }
    }

    public static func continues(_ previous: String, _ next: String) -> Bool {
        if previous.isEmpty || next.isEmpty { return true }
        if next.hasPrefix(previous) || previous.hasPrefix(next) { return true }
        let common = previous.commonPrefix(with: next)
        if common.count >= 4 { return true }
        if common.count >= 2 && common.count * 3 >= min(previous.count, next.count) { return true }
        return false
    }

    public static func join(_ base: String, _ extra: String) -> String {
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return base }
        guard !base.isEmpty else { return extra }
        if base.last?.isWhitespace == true { return base + extra }
        if let last = base.last, let first = extra.first, isCjk(last) || isCjk(first) {
            return base + extra
        }
        return base + " " + extra
    }

    private static func isCjk(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}
