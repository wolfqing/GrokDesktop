import Foundation

public struct ModelChoice: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var shortTitle: String
    public var detail: String

    public init(id: String, name: String, shortTitle: String, detail: String = "") {
        self.id = id
        self.name = name
        self.shortTitle = shortTitle
        self.detail = detail
    }
}

public enum ModelCatalog {
    public static let fallbackID = "grok-4.7"

    public static func load(
        cacheURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/models_cache.json")
    ) -> [ModelChoice] {
        guard let data = try? Data(contentsOf: cacheURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [String: Any]
        else {
            return fallback
        }
        var choices: [ModelChoice] = []
        for (key, value) in models {
            guard let row = value as? [String: Any] else { continue }
            let info = row["info"] as? [String: Any] ?? row
            if truth(info["hidden"]) { continue }
            let id = (info["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
            guard !id.isEmpty else { continue }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            let detail = info["description"] as? String ?? ""
            choices.append(
                ModelChoice(
                    id: id,
                    name: name,
                    shortTitle: shortTitle(id: id, name: name),
                    detail: detail
                )
            )
        }
        let ranked = rank(choices)
        return ranked.isEmpty ? fallback : ranked
    }

    public static var fallback: [ModelChoice] {
        BuildModel.allCases.map {
            ModelChoice(id: $0.rawValue, name: $0.menuTitle, shortTitle: $0.shortTitle)
        }
    }

    public static func shortTitle(for id: String, choices: [ModelChoice] = []) -> String {
        if let match = choices.first(where: { $0.id == id }) {
            return match.shortTitle
        }
        return shortTitle(id: id, name: id)
    }

    public static func name(for id: String, choices: [ModelChoice] = []) -> String {
        if let match = choices.first(where: { $0.id == id }) {
            return match.name
        }
        return id
    }

    static func rank(_ choices: [ModelChoice]) -> [ModelChoice] {
        choices.sorted { lhs, rhs in
            let left = version(in: lhs.id)
            let right = version(in: rhs.id)
            if left != right { return left > right }
            let leftFast = lhs.id.contains("fast")
            let rightFast = rhs.id.contains("fast")
            if leftFast != rightFast { return !leftFast }
            return lhs.id < rhs.id
        }
    }

    static func shortTitle(id: String, name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("grok ") {
            return String(trimmed.dropFirst(5))
        }
        let number = versionText(in: id)
        if !number.isEmpty {
            return id.contains("fast") ? "\(number) Fast" : number
        }
        return trimmed.isEmpty ? id : trimmed
    }

    static func version(in id: String) -> Double {
        Double(versionText(in: id)) ?? 0
    }

    static func versionText(in id: String) -> String {
        var number = ""
        var started = false
        var sawDot = false
        for character in id {
            if character.isNumber {
                number.append(character)
                started = true
            } else if character == ".", started, !sawDot {
                number.append(character)
                sawDot = true
            } else if started {
                break
            }
        }
        return number
    }

    private static func truth(_ raw: Any?) -> Bool {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return false
    }
}
