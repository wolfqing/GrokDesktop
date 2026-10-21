import AppKit
import GrokDesktopCore
import SwiftUI

@MainActor
final class DeskController: ObservableObject {
    @AppStorage("deskLocale") var localeID = "system"
    @AppStorage("sessionDataMode") var sessionDataMode = SessionDataMode.shared.rawValue
    @AppStorage("permissionTier") var permissionTier = PermissionTier.ask.rawValue
    @AppStorage("projectTiersJSON") var projectTiersJSON = "{}"
    @AppStorage("trustedProjects") var trustedRaw = ""
    @AppStorage("projectTrustSeeded") var trustSeeded = false
    @AppStorage("proxyURL") var proxyURL = ""
    @AppStorage("mirrorExposure") var mirrorExposure = MirrorExposure.loopback.rawValue
    @Published var companionDraft = ""
    @Published var mirrorPort: UInt16 = 0
    @Published var mirrorOn = false
    @Published var relayPreset = RelayPreset.generic.rawValue
    @Published var relayBase = ""
    @Published var relayModel = "grok-4.7"
    @Published var relayKey = ""
    @Published var relayMode = RelayHomeMode.independent.rawValue
    @Published var relayNote = ""
    @Published var imChannel: IMChannel = .telegram
    @Published var imFields: [String: String] = [:]
    @Published var bridges: [IMBridgeConfig] = []
    @Published var referenceDraft = ""
    @Published var nlAutomation = ""
    @Published var automationLog: [AutomationRun] = []
    @Published var extensionToggles: [ExtensionToggle] = []
    @Published var accountSlots: [AccountSlot] = []
    @Published var activeAccount = ""
    @Published var slotLabel = ""
    @Published var prNumbers = ""
    @Published var prNote = ""
    @Published var previousPRJSON: [String] = []
    @Published var sshHosts: [SSHHost] = []
    @Published var sshAlias = ""
    @Published var sshRelative = ""
    @Published var sshBody = ""
    @Published var sshNote = ""
    @Published var doctorNote = ""
    @Published var lastFork = ""
    let sessionAPI = SessionAPIServer()
    private var mirrorToken = ""
    private var companionPanel: NSPanel?

    var trustedPaths: Set<String> {
        Set(trustedRaw.split(separator: "\n").map { ProjectTrust.normalize(String($0)) }.filter { !$0.isEmpty })
    }

    func setTrusted(_ paths: Set<String>) {
        trustedRaw = paths.sorted().joined(separator: "\n")
    }

    var projectTiers: [String: PermissionTier] {
        guard let data = projectTiersJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.compactMapValues(PermissionTier.init(rawValue:))
    }

    func setProjectTier(_ path: String, tier: PermissionTier) {
        var next = projectTiers
        next[ProjectTrust.normalize(path)] = tier
        let encoded = Dictionary(uniqueKeysWithValues: next.map { ($0.key, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(encoded) {
            projectTiersJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    func policy() -> PermissionPolicy {
        PermissionPolicy(tier: PermissionTier(rawValue: permissionTier) ?? .ask, projectTiers: projectTiers)
    }

    var maskedMirrorToken: String {
        MirrorBind.uiToken(stored: mirrorToken)
    }

    func ensureMirrorToken() -> String {
        if mirrorToken.isEmpty {
            if let saved = AccountKeychain.load(account: "session-api") {
                mirrorToken = saved
            } else {
                mirrorToken = UUID().uuidString
                _ = AccountKeychain.save(account: "session-api", secret: mirrorToken)
            }
        }
        return mirrorToken
    }

    func toggleCompanion(model: AppModel) {
        if let companionPanel, companionPanel.isVisible {
            companionPanel.close()
            return
        }
        let scheme: ColorScheme = {
            switch model.appearance {
            case .light: return .light
            case .dark: return .dark
            case .system:
                return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            }
        }()
        let root = CompanionDeskView()
            .environmentObject(model)
            .environmentObject(self)
            .environment(\.palette, Palette.resolve(preference: model.appearance, system: scheme))
            .environment(\.l10n, model.copy)
        let host = NSHostingView(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 188),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Desk"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        panel.center()
        panel.orderFrontRegardless()
        companionPanel = panel
    }
}
