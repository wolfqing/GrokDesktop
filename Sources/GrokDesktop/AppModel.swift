import AppKit
import Foundation
import GrokDesktopCore
import SwiftUI

enum MainDestination: String {
    case chat
    case automations
    case skills
}

enum ResponseStyle: String, CaseIterable, Identifiable {
    case custom, concise, formal, tutor, comprehensive
    var id: String { rawValue }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case account
    case appearance
    case behavior
    case customize
    case billing
    case usage
    case dataControls

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .account, .appearance, .behavior: return .general
        case .customize: return .grok
        case .billing, .usage: return .payments
        case .dataControls: return .data
        }
    }
}

enum SettingsGroup: String, CaseIterable {
    case general
    case grok
    case payments
    case data
}

enum FirstRunReason: Equatable {
    case missingCLI
    case agent(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var client: ACPClient
    @Published var sessions: [SessionRecord] = []
    @Published var search = ""
    @Published var draft = ""
    @Published var showSettings = false
    @Published var showPalette = false
    @Published var showInspector = true
    @Published var showSearchField = false
    @Published var showAttachMenu = false
    @Published var showCreateProject = false
    @Published var showLanguagePicker = false
    @Published var sidebarCollapsed = false
    @Published var projectsExpanded = true
    @Published var historyExpanded = true
    @Published var destination: MainDestination = .chat
    @Published var isPrivateChat = false
    @Published var settingsSection: SettingsSection = .account
    @Published var firstRunReason: FirstRunReason?
    @Published var account = AccountProfile()
    @Published var skills: [SkillRecord] = []
    @Published var automations: [AutomationRecord] = []
    @Published var namedProjects: [NamedProject] = []
    @Published var skillsQuery = ""
    @Published var skillsTab = 0
    @Published var newProjectName = ""
    @Published var newProjectFolder: URL?
    @Published var workspace = WorkspaceSnapshot()

    @AppStorage("appearancePreference") var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("languagePreference") var languageRaw = AppLanguage.system.rawValue
    @AppStorage("wrapCodeLines") var wrapCodeLines = false
    @AppStorage("autoScroll") var autoScroll = false
    @AppStorage("notifyThinking") var notifyThinking = true
    @AppStorage("requireCmdEnter") var requireCmdEnter = false
    @AppStorage("richTextEditor") var richTextEditor = true
    @AppStorage("responseStyle") var responseStyleRaw = ResponseStyle.custom.rawValue

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set {
            appearanceRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .system }
        set {
            languageRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var responseStyle: ResponseStyle {
        get { ResponseStyle(rawValue: responseStyleRaw) ?? .custom }
        set {
            responseStyleRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var copy: L10n {
        L10n(language: language.resolved())
    }

    let sessionIndex: SessionIndex
    let locator: GrokBinaryLocator
    let automationStore = AutomationStore()
    let projectStore = ProjectStore()
    let skillCatalog = SkillCatalog()

    init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        sessionIndex: SessionIndex = SessionIndex()
    ) {
        self.locator = locator
        self.sessionIndex = sessionIndex
        self.client = ACPClient(locator: locator)
        refreshAll()
        if locator.locate() == nil {
            firstRunReason = .missingCLI
        }
        refreshWorkspace()
    }

    func refreshAll() {
        refreshSessions()
        account = AccountProfile.load()
        skills = skillCatalog.load()
        automations = automationStore.load()
        namedProjects = projectStore.load()
    }

    var filteredSessions: [SessionRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.cwd.localizedCaseInsensitiveContains(query)
        }
    }

    var visibleProjects: [NamedProject] {
        if !namedProjects.isEmpty { return namedProjects }
        return projectPaths.map { NamedProject(id: $0.path, name: $0.name, path: $0.path) }
    }

    var projectPaths: [(path: String, name: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []
        for session in sessions {
            guard seen.insert(session.cwd).inserted, !session.cwd.isEmpty else { continue }
            result.append((session.cwd, session.cwdName))
        }
        return result.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var isEmptyChat: Bool {
        destination == .chat && client.items.isEmpty && firstRunReason == nil
    }

    var filteredSkills: [SkillRecord] {
        let query = skillsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    func refreshSessions() {
        sessions = sessionIndex.load()
        refreshWorkspace()
    }

    func refreshWorkspace() {
        let sessionDir = sessions.first(where: { $0.id == client.sessionID })?.directory
        workspace = WorkspaceSnapshot.load(cwd: client.workingDirectory, sessionDirectory: sessionDir)
    }

    func openInFinder() {
        NSWorkspace.shared.open(client.workingDirectory)
    }

    func openInTerminal() {
        let script = """
        tell application "Terminal"
          activate
          do script "cd \(client.workingDirectory.path.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    func commitOrPushHint() -> String {
        "cd \(workspace.path) && git status"
    }

    func openChat() {
        destination = .chat
        client.resetConversation()
        firstRunReason = locator.locate() == nil ? .missingCLI : nil
    }

    func startNewSession() {
        destination = .chat
        Task {
            do {
                try await client.newSession()
                firstRunReason = nil
            } catch {
                present(error)
            }
        }
    }

    func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = copy.chooseFolder
        panel.directoryURL = client.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        client.workingDirectory = url
        refreshWorkspace()
        startNewSession()
    }

    func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = newProjectFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/\(name)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = NamedProject(name: name, path: folder.path)
        namedProjects.insert(project, at: 0)
        projectStore.save(namedProjects)
        client.workingDirectory = folder
        refreshWorkspace()
        showCreateProject = false
        newProjectName = ""
        newProjectFolder = nil
        startNewSession()
    }

    func open(_ record: SessionRecord) {
        destination = .chat
        isPrivateChat = false
        Task {
            do {
                try await client.loadSession(id: record.id, cwd: URL(fileURLWithPath: record.cwd))
                firstRunReason = nil
            } catch {
                present(error)
            }
        }
    }

    func sendDraft() {
        let text = draft
        draft = ""
        destination = .chat
        Task {
            do {
                try await client.send(text: text)
                if !isPrivateChat {
                    refreshSessions()
                }
                refreshWorkspace()
            } catch {
                present(error)
            }
        }
    }

    func runSkill(_ skill: SkillRecord) {
        destination = .chat
        draft = "/\(skill.slug) "
    }

    func addAutomation(_ record: AutomationRecord) {
        var next = record
        next.suggested = false
        next.id = UUID().uuidString
        automations.insert(next, at: 0)
        automationStore.save(automations)
    }

    func runAutomation(_ record: AutomationRecord) {
        destination = .chat
        draft = record.prompt
        sendDraft()
    }

    func createAutomation() {
        let item = AutomationRecord(
            title: copy.newAutomation,
            detail: copy.automations,
            prompt: "/loop 1d "
        )
        addAutomation(item)
        draft = item.prompt
        destination = .chat
    }

    func handleCommand(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(line.split(separator: " ").first ?? "")
        switch name {
        case "/new", "/clear":
            startNewSession()
        case "/settings", "/config", "/prefs":
            showSettings = true
        case "/dashboard", "/sessions":
            search = ""
            sidebarCollapsed = false
        case "/home", "/welcome":
            openChat()
        case "/quit", "/exit":
            NSApp.terminate(nil)
        default:
            draft = line
            sendDraft()
        }
        showPalette = false
    }

    func retryLocate() {
        if locator.locate() == nil {
            firstRunReason = .missingCLI
        } else {
            firstRunReason = nil
            startNewSession()
        }
    }

    func login() {
        guard let grok = locator.locate() else {
            firstRunReason = .missingCLI
            return
        }
        let process = Process()
        process.executableURL = grok
        process.arguments = ["login"]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.account = AccountProfile.load()
        }
    }

    func openUsage() {
        if let grok = locator.locate() {
            let process = Process()
            process.executableURL = grok
            process.arguments = ["-p", "/usage"]
            try? process.run()
        }
        settingsSection = .usage
        showSettings = true
    }

    private func present(_ error: Error) {
        if let acp = error as? ACPError, acp == .grokNotFound {
            firstRunReason = .missingCLI
        } else {
            firstRunReason = .agent(error.localizedDescription)
        }
    }
}
