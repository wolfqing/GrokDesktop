import Foundation

public enum PermissionTier: String, Codable, Sendable, Equatable, CaseIterable {
    case ask
    case allowOnce
    case allowSession
    case deny
    case yolo
}

public enum PermissionChoice: String, Sendable, Equatable {
    case allowOnce
    case allowSession
    case deny
    case yolo
    case ask
}

/// Ask is the stored default. YOLO is opt-in. A per-project tier overrides the global one.
public struct PermissionPolicy: Equatable, Sendable {
    public var tier: PermissionTier
    public var projectTiers: [String: PermissionTier]

    public init(tier: PermissionTier = .ask, projectTiers: [String: PermissionTier] = [:]) {
        self.tier = tier
        self.projectTiers = projectTiers
    }

    public static func fresh() -> PermissionPolicy {
        PermissionPolicy()
    }

    public var isYOLODefault: Bool { tier == .yolo }

    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public func effective(project path: String) -> PermissionTier {
        projectTiers[Self.normalize(path)] ?? tier
    }

    public func setting(_ choice: PermissionChoice, project path: String?) -> PermissionPolicy {
        var copy = self
        let next = Self.tier(for: choice)
        if choice == .yolo || path == nil {
            copy.tier = next
        } else if let path {
            copy.projectTiers[Self.normalize(path)] = next
        }
        return copy
    }

    /// `allowOnce` answers the current prompt and does not stick. A stored once-tier falls back to Ask.
    public func decision(_ choice: PermissionChoice?, project path: String) -> PermissionTier {
        if let choice {
            switch choice {
            case .allowOnce: return .allowOnce
            case .allowSession: return setting(.allowSession, project: path).effective(project: path)
            case .deny: return .deny
            case .yolo: return .yolo
            case .ask: return .ask
            }
        }
        let stored = effective(project: path)
        return stored == .allowOnce ? .ask : stored
    }

    private static func tier(for choice: PermissionChoice) -> PermissionTier {
        switch choice {
        case .allowOnce: return .allowOnce
        case .allowSession: return .allowSession
        case .deny: return .deny
        case .yolo: return .yolo
        case .ask: return .ask
        }
    }
}
