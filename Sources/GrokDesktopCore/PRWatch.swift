import Foundation

public enum CIState: String, Equatable, Sendable {
    case unknown
    case pending
    case failing
    case green
}

public struct PRSnapshot: Equatable, Sendable {
    public var number: Int
    public var commentIDs: [String]
    public var reviewIDs: [String]
    public var ci: CIState

    public init(number: Int, commentIDs: [String], reviewIDs: [String], ci: CIState) {
        self.number = number
        self.commentIDs = commentIDs
        self.reviewIDs = reviewIDs
        self.ci = ci
    }
}

public struct PRFollowUp: Equatable, Sendable {
    public var number: Int
    public var reason: String
    public var text: String

    public init(number: Int, reason: String, text: String) {
        self.number = number
        self.reason = reason
        self.text = text
    }
}

public enum PRWatch {
    public static func classify(before: [PRSnapshot], after: [PRSnapshot], ghReadable: Bool) -> [PRFollowUp] {
        guard ghReadable else { return [] }
        var out: [PRFollowUp] = []
        for snap in after {
            guard let prev = before.first(where: { $0.number == snap.number }) else { continue }
            let oldComments = Set(prev.commentIDs)
            if snap.commentIDs.contains(where: { !oldComments.contains($0) }) {
                out.append(PRFollowUp(number: snap.number, reason: "comment", text: "New comment on PR #\(snap.number)"))
            }
            let oldReviews = Set(prev.reviewIDs)
            if snap.reviewIDs.contains(where: { !oldReviews.contains($0) }) {
                out.append(PRFollowUp(number: snap.number, reason: "review", text: "New review on PR #\(snap.number)"))
            }
            if prev.ci != .failing, snap.ci == .failing {
                out.append(PRFollowUp(number: snap.number, reason: "ci-failing", text: "CI failed on PR #\(snap.number)"))
            }
            if prev.ci != .green, snap.ci == .green {
                out.append(PRFollowUp(number: snap.number, reason: "ci-green", text: "CI passed on PR #\(snap.number)"))
            }
        }
        return out
    }

    public static func parse(json: String) -> PRSnapshot? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["number"] as? Int
        else { return nil }
        return PRSnapshot(
            number: number,
            commentIDs: ids(object["comments"]),
            reviewIDs: ids(object["reviews"]),
            ci: ciState(object["statusCheckRollup"])
        )
    }

    /// Unreadable `gh` output yields no follow-up, even if another payload in the batch parsed.
    public static func followUps(previousJSON: [String], currentJSON: [String]) -> [PRFollowUp] {
        let after = currentJSON.compactMap(parse)
        if after.count != currentJSON.count { return [] }
        let before = previousJSON.compactMap(parse)
        if before.count != previousJSON.count { return [] }
        return classify(before: before, after: after, ghReadable: true)
    }

    private static func ids(_ raw: Any?) -> [String] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            if let id = row["id"] as? String { return id }
            if let id = row["id"] as? Int { return String(id) }
            return nil
        }
    }

    private static func ciState(_ raw: Any?) -> CIState {
        guard let rows = raw as? [[String: Any]] else { return .unknown }
        let states = rows.compactMap { ($0["state"] as? String)?.uppercased() }
        if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" || $0 == "FAILING" }) { return .failing }
        if !states.isEmpty, states.allSatisfy({ $0 == "SUCCESS" || $0 == "SUCCESSFUL" || $0 == "GREEN" }) {
            return .green
        }
        if states.contains(where: { $0 == "PENDING" || $0 == "QUEUED" || $0 == "IN_PROGRESS" }) { return .pending }
        return .unknown
    }
}
