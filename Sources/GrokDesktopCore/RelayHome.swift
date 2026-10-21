import Foundation

public enum RelayPreset: String, CaseIterable, Sendable, Equatable {
    case generic
    case openrouter
    case requesty
    case deepseek
    case ai98pro
}

public enum RelayPresets {
    public static func baseURL(_ preset: String) -> String {
        switch preset {
        case RelayPreset.openrouter.rawValue: return "https://openrouter.ai/api/v1"
        case RelayPreset.requesty.rawValue: return "https://router.requesty.ai/v1"
        case RelayPreset.deepseek.rawValue: return "https://api.deepseek.com/v1"
        case RelayPreset.ai98pro.rawValue: return "https://api.ai98pro.com/v1"
        default: return ""
        }
    }
}

public struct RelayProfile: Codable, Equatable, Sendable {
    public var preset: String
    public var baseURL: String
    public var defaultModel: String
    public var keyAccount: String

    public init(preset: String, baseURL: String, defaultModel: String, keyAccount: String) {
        self.preset = preset
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.keyAccount = keyAccount
    }
}

public enum RelayHomeMode: String, Codable, Sendable, Equatable {
    case independent
    case shared
}

public enum RelayHome {
    /// Writes `relay.json` only under the selected home. The key stays out of the file.
    public static func apply(
        mode: RelayHomeMode,
        profile: RelayProfile,
        independentRoot: URL,
        sharedRoot: URL
    ) throws -> URL {
        let root = mode == .independent ? independentRoot : sharedRoot
        let other = mode == .independent ? sharedRoot : independentRoot
        let otherURL = other.appendingPathComponent("relay.json")
        let before = try? Data(contentsOf: otherURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profile)
        let dest = root.appendingPathComponent("relay.json")
        try data.write(to: dest, options: .atomic)
        let after = try? Data(contentsOf: otherURL)
        if before != after {
            throw CocoaError(.fileWriteUnknown)
        }
        return dest
    }
}

public enum RelayProbeResult: String, Equatable, Sendable {
    case ok
    case auth
    case timeout
    case dns
    case other
}

public enum RelayProbe {
    public static func classify(httpStatus: Int?, urlErrorCode: Int?) -> RelayProbeResult {
        if let status = httpStatus {
            if status == 401 || status == 403 { return .auth }
            if (200..<300).contains(status) { return .ok }
        }
        if urlErrorCode == NSURLErrorTimedOut { return .timeout }
        if urlErrorCode == NSURLErrorCannotFindHost || urlErrorCode == NSURLErrorDNSLookupFailed {
            return .dns
        }
        return .other
    }
}
