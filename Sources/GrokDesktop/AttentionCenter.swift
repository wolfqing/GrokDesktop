import AppKit
import UserNotifications

@MainActor
final class AttentionCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AttentionCenter()

    var onOpenSession: ((String) -> Void)?

    private var posted: Set<String> = []
    private var authorized = false
    private var requested = false

    /// `swift run` is a bare executable. UserNotifications aborts unless this process is an .app bundle.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier != nil
        else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    override private init() {
        super.init()
        center?.delegate = self
    }

    func prepare() {
        requestAccessIfNeeded()
    }

    func sync(
        needs: [AttentionNeed],
        badgeCount: Int,
        focusedSessionID: String?,
        destinationIsChat: Bool,
        enabled: Bool
    ) {
        let keys = Set(needs.map(\.key))
        NSApp.dockTile.badgeLabel = badgeCount == 0 ? nil : "\(badgeCount)"

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
            // A finished turn is visible on the dashboard while the app is in front.
            if need.kind == .finished, appActive { continue }
            posted.insert(need.key)
            post(need)
        }
        for key in posted where !keys.contains(key) {
            posted.remove(key)
            center?.removeDeliveredNotifications(withIdentifiers: [key])
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
        guard !requested, let center else { return }
        requested = true
        Task {
            do {
                authorized = try await center
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                authorized = false
            }
        }
    }

    private func post(_ need: AttentionNeed) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = need.title
        content.body = need.body
        content.sound = .default
        content.userInfo = ["sessionID": need.sessionID]
        let request = UNNotificationRequest(identifier: need.key, content: content, trigger: nil)
        center.add(request)
    }

    private func clearPosted() {
        guard !posted.isEmpty else { return }
        center?.removeDeliveredNotifications(withIdentifiers: Array(posted))
        posted.removeAll()
    }
}

struct AttentionNeed: Hashable {
    enum Kind: String {
        case permission
        case question
        case finished
    }

    var sessionID: String
    var kind: Kind
    var title: String
    var body: String

    var key: String { "\(sessionID):\(kind.rawValue)" }
}
