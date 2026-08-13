import Foundation

public struct AccountUsage: Equatable, Sendable {
    public var creditPercent: Int
    public var periodKind: PeriodKind
    public var periodStart: Date?
    public var periodEnd: Date?
    public var prepaidDollars: Double
    public var onDemandUsed: Double
    public var onDemandCap: Double
    public var products: [Product]
    public var fetchedAt: Date?
    public var error: String?
    public var isLoaded: Bool

    public enum PeriodKind: String, Equatable, Sendable {
        case weekly
        case monthly
        case unknown
    }

    public struct Product: Equatable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var percent: Int?

        public init(name: String, percent: Int?) {
            self.name = name
            self.percent = percent
        }
    }

    public init(
        creditPercent: Int = 0,
        periodKind: PeriodKind = .unknown,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        prepaidDollars: Double = 0,
        onDemandUsed: Double = 0,
        onDemandCap: Double = 0,
        products: [Product] = [],
        fetchedAt: Date? = nil,
        error: String? = nil,
        isLoaded: Bool = false
    ) {
        self.creditPercent = creditPercent
        self.periodKind = periodKind
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.prepaidDollars = prepaidDollars
        self.onDemandUsed = onDemandUsed
        self.onDemandCap = onDemandCap
        self.products = products
        self.fetchedAt = fetchedAt
        self.error = error
        self.isLoaded = isLoaded
    }

    public var prepaidDisplay: String {
        String(format: "US$%.2f", prepaidDollars)
    }

    public var hasPayAsYouGo: Bool {
        onDemandCap > 0
    }

    public var displayPercent: Int {
        if let build = products.first(where: { $0.name.lowercased().contains("build") }),
           let percent = build.percent {
            return percent
        }
        return creditPercent
    }
}

public enum AccountUsageService: Sendable {
    public static let defaultProxyBase = "https://cli-chat-proxy.grok.com/v1"

    public static func load(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json"),
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/config.toml"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> (usage: AccountUsage, profile: AccountProfile?) {
        guard let token = accessToken(authURL: authURL, environment: environment) else {
            return (AccountUsage(error: "Not signed in", isLoaded: false), nil)
        }
        let base = proxyBase(configURL: configURL, environment: environment)
        var usage = AccountUsage()
        var profile: AccountProfile?
        async let billingData = getJSON(url: URL(string: "\(base)/billing?format=credits"), token: token)
        async let userData = getJSON(url: URL(string: "\(base)/user"), token: token)
        let billing = await billingData
        let user = await userData
        switch billing {
        case .ok(let object):
            usage = parseBilling(object)
            usage.isLoaded = true
            usage.fetchedAt = Date()
        case .failed(let message):
            usage.error = message
        }
        if case .ok(let object) = user {
            profile = parseProfile(object)
        }
        return (usage, profile)
    }

    public static func parseBilling(_ object: [String: Any]) -> AccountUsage {
        let config = object["config"] as? [String: Any] ?? object
        let period = config["currentPeriod"] as? [String: Any]
            ?? config["current_period"] as? [String: Any]
            ?? [:]
        let products = parseProducts(config["productUsage"] ?? config["product_usage"])
        return AccountUsage(
            creditPercent: intValue(config["creditUsagePercent"] ?? config["credit_usage_percent"]),
            periodKind: periodKind(period["type"] as? String),
            periodStart: dateValue(period["start"] ?? config["billingPeriodStart"] ?? config["billing_period_start"]),
            periodEnd: dateValue(period["end"] ?? config["billingPeriodEnd"] ?? config["billing_period_end"]),
            prepaidDollars: moneyValue(config["prepaidBalance"] ?? config["prepaid_balance"]),
            onDemandUsed: moneyValue(config["onDemandUsed"] ?? config["on_demand_used"]),
            onDemandCap: moneyValue(config["onDemandCap"] ?? config["on_demand_cap"]),
            products: products,
            isLoaded: true
        )
    }

    public static func parseProfile(_ object: [String: Any]) -> AccountProfile {
        let first = object["firstName"] as? String ?? object["first_name"] as? String ?? ""
        let last = object["lastName"] as? String ?? object["last_name"] as? String ?? ""
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let teamID = object["teamId"] as? String ?? object["team_id"] as? String
        var plan = SubscriptionPlan.grok
        if object["hasGrokCodeAccess"] as? Bool == true || !(teamID ?? "").isEmpty {
            plan = .superGrok
        }
        return AccountProfile(
            email: object["email"] as? String,
            name: combined.isEmpty ? nil : combined,
            userID: object["userId"] as? String ?? object["user_id"] as? String,
            teamID: teamID,
            plan: plan
        )
    }

    public static func proxyBase(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/config.toml"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let env = environment["GROK_CLI_CHAT_PROXY_BASE_URL"], !env.isEmpty {
            return env.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let raw = try? String(contentsOf: configURL, encoding: .utf8),
           let value = tomlString(raw, section: "endpoints", key: "cli_chat_proxy_base_url"),
           !value.isEmpty {
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return defaultProxyBase
    }

    public static func accessToken(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let key = environment["XAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        for value in object.values {
            guard let dict = value as? [String: Any] else { continue }
            if let key = dict["key"] as? String, !key.isEmpty { return key }
            if let token = dict["access_token"] as? String, !token.isEmpty { return token }
        }
        return nil
    }

    private enum FetchResult {
        case ok([String: Any])
        case failed(String)
    }

    private static func getJSON(url: URL?, token: String) async -> FetchResult {
        guard let url else { return .failed("Invalid usage endpoint") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
        request.setValue("GrokDesktop/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 {
                return .failed("Sign in again")
            }
            if status >= 400 {
                return .failed("Usage request failed (\(status))")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed("Couldn't parse usage")
            }
            return .ok(object)
        } catch {
            return .failed("Couldn't reach usage service")
        }
    }

    private static func parseProducts(_ value: Any?) -> [AccountUsage.Product] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let raw = row["product"] as? String ?? row["name"] as? String ?? ""
            guard !raw.isEmpty else { return nil }
            let percentValue = row["usagePercent"] ?? row["usage_percent"]
            let percent = percentValue == nil ? nil : intValue(percentValue)
            return AccountUsage.Product(name: prettyProduct(raw), percent: percent)
        }
    }

    private static func prettyProduct(_ raw: String) -> String {
        switch raw {
        case "GrokBuild": return "Grok Build"
        case "GrokChat": return "Grok Chat"
        default: return raw
        }
    }

    private static func periodKind(_ raw: String?) -> AccountUsage.PeriodKind {
        let value = (raw ?? "").uppercased()
        if value.contains("WEEK") { return .weekly }
        if value.contains("MONTH") { return .monthly }
        return .unknown
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number.rounded()) }
        if let number = value as? NSNumber { return Int(number.doubleValue.rounded()) }
        if let text = value as? String, let number = Double(text) { return Int(number.rounded()) }
        return 0
    }

    private static func moneyValue(_ value: Any?) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let number = Double(text) { return number }
        if let dict = value as? [String: Any] {
            return moneyValue(dict["val"] ?? dict["value"] ?? dict["amount"])
        }
        return 0
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static func tomlString(_ raw: String, section: String, key: String) -> String? {
        var inSection = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inSection = trimmed == "[\(section)]"
                continue
            }
            guard inSection, trimmed.hasPrefix("\(key)"), trimmed.contains("=") else { continue }
            var value = trimmed.split(separator: "=", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(of: "#") {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }
}
