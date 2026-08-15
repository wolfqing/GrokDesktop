import AppKit
import UserNotifications

@MainActor
final class AttentionCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AttentionCenter()

    var onOpenSession: ((String) -> Void)?

    private var posted: Set<String> = []
    private var authorized = false
    private var requested = false

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func prepare() {
        requestAccessIfNeeded()
    }

    func sync(
        needs: [AttentionNeed],
        focusedSessionID: String?,
        destinationIsChat: Bool,
        enabled: Bool
    ) {
        let keys = Set(needs.map(\.key))
        NSApp.dockTile.badgeLabel = keys.isEmpty ? nil : "\(keys.count)"

        if !enabled {
            clearPosted()
            return
        }

        requestAccessIfNeeded()
        let appActive = NSApp.isActive
        for need in needs {
            if posted.contains(need.key) { continue }
            let lookingAtIt = appActive && destinationIsChat && focusedSessionID == need.sessionID
            if lookingAtIt { continue }
            posted.insert(need.key)
            post(need)
        }
        for key in posted where !keys.contains(key) {
            posted.remove(key)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let sessionID {
                AttentionCenter.shared.onOpenSession?(sessionID)
            }
        }
    }

    private func requestAccessIfNeeded() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.authorized = granted
            }
        }
    }

    private func post(_ need: AttentionNeed) {
        let content = UNMutableNotificationContent()
        content.title = need.title
        content.body = need.body
        content.sound = .default
        content.userInfo = ["sessionID": need.sessionID]
        let request = UNNotificationRequest(identifier: need.key, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func clearPosted() {
        guard !posted.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(posted))
        posted.removeAll()
    }
}

struct AttentionNeed: Hashable {
    enum Kind: String {
        case permission
        case question
    }

    var sessionID: String
    var kind: Kind
    var title: String
    var body: String

    var key: String { "\(sessionID):\(kind.rawValue)" }
}
