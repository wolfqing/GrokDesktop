import AppKit
import Combine
import Foundation
import GrokDesktopCore
import SwiftUI
import UniformTypeIdentifiers

enum MainDestination: String {
    case chat
    case dashboard
    case imagine
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
    case session
    case customize
    case models
    case feedback
    case billing
    case usage
    case dataControls
    case extensions
    case agent
    case advanced

    var id: String { rawValue }

    var group: SettingsGroup {
        switch self {
        case .account, .appearance, .behavior, .session: return .general
        case .customize, .models, .feedback, .extensions, .agent: return .grok
        case .billing, .usage: return .payments
        case .dataControls, .advanced: return .data
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
    case unsigned
    case agent(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var client: ACPClient
    @Published var sessions: [SessionRecord] = []
    @Published var search = ""
    @Published var draft = ""
    @Published var showSettings = false
    @Published var showAbout = false
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
    @Published var grokConfig = GrokConfig()
    @Published var renameDraft = ""
    @Published var renamingSession: SessionRecord?
    @Published var mentionQuery: String?
    @Published var mentionMatches: [URL] = []
    @Published var jumpTarget: String?
    @Published var loginCode = ""
    @Published var toast: String?
    @Published var showResumePicker = false
    @Published var sidebarNotice: String?
    @Published var needsFolderPick = false
    @Published var personas: [String] = []
    @Published var officialWorkflows: [WorkflowRecord] = []
    @Published var mcpServers: [MCPServerRecord] = []
    @Published var showAddWorkflow = false
    @Published var showAddMCP = false
    @Published var newWorkflowName = ""
    @Published var newWorkflowDetail = ""
    @Published var mcpName = ""
    @Published var mcpTransport = "stdio"
    @Published var mcpCommand = ""
    @Published var mcpArgs = ""
    @Published var accountUsage = AccountUsage()
    @Published var isRefreshingUsage = false
    @Published var pendingBusySend: String?
    @Published var suppressSuggest = false

    @AppStorage("appearancePreference") var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("languagePreference") var languageRaw = AppLanguage.system.rawValue
    @AppStorage("wrapCodeLines") var wrapCodeLines = false
    @AppStorage("autoScroll") var autoScroll = false
    @AppStorage("notifyThinking") var notifyThinking = true
    @AppStorage("requireCmdEnter") var requireCmdEnter = false
    @AppStorage("richTextEditor") var richTextEditor = true
    @AppStorage("responseStyle") var responseStyleRaw = ResponseStyle.custom.rawValue
    @AppStorage("showTimestamps") var showTimestamps = false
    @AppStorage("compactChat") var compactChat = false
    @AppStorage("mergeToolRows") var mergeToolRows = true
    @AppStorage("showThinkingBlocks") var showThinkingBlocks = true

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
    let configStore = ConfigStore()
    let automationStore = AutomationStore()
    let projectStore = ProjectStore()
    let skillCatalog = SkillCatalog()
    let workflowCatalog = WorkflowCatalog()
    let mcpCatalog = MCPCatalog()
    private var clientCancellables = Set<AnyCancellable>()

    init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        sessionIndex: SessionIndex = SessionIndex()
    ) {
        self.locator = locator
        self.sessionIndex = sessionIndex
        self.client = ACPClient(locator: locator)
        restoreWorkingDirectory()
        refreshAll()
        firstRunReason = bootstrapReason()
        refreshWorkspace()
        refreshAccountUsage()
        bindClient()
    }

    private func bindClient() {
        clientCancellables.removeAll()
        client.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &clientCancellables)
    }

    var liveSessions: [SessionRecord] {
        client.liveWorkspaces.map { workspace in
            if let record = sessions.first(where: { $0.id == workspace.id }) {
                return record
            }
            return SessionRecord(
                id: workspace.id,
                cwd: workspace.cwd.path,
                title: workspace.title.isEmpty ? copy.t("Live session", "进行中") : workspace.title,
                updatedAt: Date(),
                model: client.buildModel.rawValue,
                directory: workspace.directory ?? workspace.cwd,
                messageCount: workspace.items.count
            )
        }
    }

    private func bootstrapReason() -> FirstRunReason? {
        if locator.locate() == nil { return .missingCLI }
        client.refreshAuth()
        if !client.authPresence.isReady { return .unsigned }
        return nil
    }

    func refreshAll() {
        refreshSessions()
        account = AccountProfile.load()
        skills = skillCatalog.load()
        automations = automationStore.load()
        namedProjects = projectStore.load()
        grokConfig = configStore.load()
        showThinkingBlocks = grokConfig.showThinking
        extensions = ExtensionInventory.load(mcpNames: grokConfig.mcpNames)
        personas = Self.loadPersonas()
        officialWorkflows = workflowCatalog.load(cwd: client.workingDirectory)
        mcpServers = mcpCatalog.load(locator: locator, cwd: client.workingDirectory)
    }

    private func restoreWorkingDirectory() {
        guard let path = UserDefaults.standard.string(forKey: "lastWorkingDirectory") else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
           isDir.boolValue,
           FileManager.default.isReadableFile(atPath: path) {
            client.workingDirectory = URL(fileURLWithPath: path)
        } else {
            needsFolderPick = true
        }
    }

    func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    private static func loadPersonas() -> [String] {
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bundled/personas"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/bundled/agents")
        ]
        var names: [String] = []
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            names.append(contentsOf: urls.map { $0.deletingPathExtension().lastPathComponent })
        }
        return names.sorted()
    }

    @Published var extensions = ExtensionInventory()

    var filteredSessions: [SessionRecord] {
        let visible = sessions.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visible }
        return visible.filter {
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
        startNewSession(cwd: client.workingDirectory)
    }

    func startNewSession(cwd: URL) {
        destination = .chat
        rememberWorkingDirectory(cwd)
        Task {
            do {
                try await client.newSession(cwd: cwd)
                firstRunReason = nil
                refreshWorkspace()
            } catch {
                present(error)
            }
        }
    }

    func openProject(_ project: NamedProject) {
        startNewSession(cwd: URL(fileURLWithPath: project.path))
    }

    func rememberWorkingDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "lastWorkingDirectory")
        client.workingDirectory = url
        refreshWorkspace()
    }

    func isCurrentProject(_ project: NamedProject) -> Bool {
        URL(fileURLWithPath: project.path).standardizedFileURL.path
            == client.workingDirectory.standardizedFileURL.path
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
        startNewSession(cwd: url)
    }

    func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = newProjectFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/\(name)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = NamedProject(name: name, path: folder.path)
        namedProjects.insert(project, at: 0)
        projectStore.save(namedProjects)
        showCreateProject = false
        newProjectName = ""
        newProjectFolder = nil
        startNewSession(cwd: folder)
    }

    func open(_ record: SessionRecord) {
        destination = .chat
        isPrivateChat = false
        if client.focusIfLoaded(record.id) {
            firstRunReason = nil
            sidebarNotice = nil
            refreshWorkspace()
            Task { await client.refreshGit() }
            return
        }
        Task {
            do {
                try await client.loadSession(id: record.id, cwd: URL(fileURLWithPath: record.cwd), directory: record.directory)
                firstRunReason = nil
                sidebarNotice = nil
                refreshWorkspace()
                await client.refreshGit()
            } catch {
                sidebarNotice = copy.t("Couldn't resume “\(record.title)”", "无法恢复「\(record.title)」")
                flash(sidebarNotice ?? error.localizedDescription)
                client.resetConversation()
                firstRunReason = nil
            }
        }
    }

    func rename(_ record: SessionRecord, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessionIndex.rename(record, title: trimmed)
        renamingSession = nil
        renameDraft = ""
        refreshSessions()
    }

    func delete(_ record: SessionRecord) {
        try? sessionIndex.delete(record)
        client.dropWorkspace(record.id)
        refreshSessions()
    }

    func export(_ record: SessionRecord) {
        let items = client.sessionID == record.id ? client.items : TranscriptLoader.load(sessionDirectory: record.directory).items
        let markdown = TranscriptLoader.markdown(from: items, title: record.title)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.nameFieldStringValue = "\(record.title).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    func copyLatestReply() {
        let text: String? = client.items.reversed().compactMap {
            if case .assistant(_, let body, _) = $0 { return body }
            return nil
        }.first
        guard let text, !text.isEmpty else { return }
        copyText(text)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func forkCurrent() {
        Task {
            do {
                try await client.forkSession()
                refreshSessions()
            } catch {
                present(error)
            }
        }
    }

    func cycleMode() {
        client.setMode(client.mode.next)
    }

    func jumpLatest() {
        jumpTarget = client.items.last?.id
        destination = .chat
    }

    func dismissComposerSuggestions() {
        mentionQuery = nil
        mentionMatches = []
        showPalette = false
        showAttachMenu = false
        suppressSuggest = true
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "@" || trimmed == "/" {
            draft = ""
            suppressSuggest = false
        }
    }

    func updateMentions(from draft: String) {
        guard let at = draft.lastIndex(of: "@") else {
            mentionQuery = nil
            mentionMatches = []
            return
        }
        let after = draft[draft.index(after: at)...]
        if after.contains(where: { $0.isWhitespace }) {
            mentionQuery = nil
            mentionMatches = []
            return
        }
        let query = String(after)
        mentionQuery = query
        mentionMatches = Self.fileMatches(cwd: client.workingDirectory, query: query)
    }

    func insertMention(_ url: URL) {
        var text = draft
        if let at = text.lastIndex(of: "@") {
            text = String(text[..<at])
        }
        if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
        draft = text + "@\(url.path) "
        mentionQuery = nil
        mentionMatches = []
        showAttachMenu = false
        suppressSuggest = false
    }

    private static func fileMatches(cwd: URL, query: String, limit: Int = 40) -> [URL] {
        let needle = query.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if needle.isEmpty && cwd.path == home {
            return []
        }
        if needle.isEmpty {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: cwd,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls.filter { !isSkippedPath($0) }.prefix(limit).map { $0 }
        }
        guard let enumerator = FileManager.default.enumerator(
            at: cwd,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var matches: [URL] = []
        for case let url as URL in enumerator {
            if isSkippedPath(url) { continue }
            if url.lastPathComponent.lowercased().contains(needle) {
                matches.append(url)
            }
            if matches.count >= limit { break }
        }
        return matches
    }

    private static func isSkippedPath(_ url: URL) -> Bool {
        let path = url.path
        let blocked = ["/Library/", "/Music/", "/Movies/", "/Pictures/", "/node_modules/", "/.git/", "/DerivedData/"]
        if blocked.contains(where: { path.contains($0) }) { return true }
        let blockedExt = ["musicdb", "itdb", "musiclibrary", "photoslibrary", "app", "framework"]
        return blockedExt.contains(url.pathExtension.lowercased())
    }

    private func lastNotice(_ text: String) {
        // kept for load warnings without wiping the first-run shell
        _ = text
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

    func beginBusySend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingBusySend = trimmed
        draft = ""
        showAttachMenu = false
        showPalette = false
    }

    func confirmBusySendNow() {
        guard let text = pendingBusySend else { return }
        pendingBusySend = nil
        destination = .chat
        Task {
            do {
                try await client.sendNow(text: text)
                if !isPrivateChat {
                    refreshSessions()
                }
                refreshWorkspace()
            } catch {
                present(error)
            }
        }
    }

    func confirmBusyEdit() {
        if let text = pendingBusySend {
            draft = text
        }
        pendingBusySend = nil
    }

    func confirmBusyCancel() {
        pendingBusySend = nil
    }

    func refreshAccountUsage() {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        Task {
            let result = await AccountUsageService.load()
            accountUsage = result.usage
            if let profile = result.profile {
                if account.email == nil { account.email = profile.email }
                if account.name == nil { account.name = profile.name }
                if account.userID == nil { account.userID = profile.userID }
                if account.teamID == nil { account.teamID = profile.teamID }
                if account.plan == .grok { account.plan = profile.plan }
            }
            isRefreshingUsage = false
        }
    }

    func runSkill(_ skill: SkillRecord) {
        destination = .chat
        insertSlashPrompt("/\(skill.slug)")
    }

    func insertSlashPrompt(_ command: String) {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("/") {
            text = "/\(text)"
        }
        draft = text + " "
        showPalette = false
        mentionQuery = nil
        mentionMatches = []
        suppressSuggest = true
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

    func runWorkflow(_ record: WorkflowRecord) {
        destination = .chat
        draft = "/workflow \(record.name)"
        sendDraft()
    }

    func createOfficialWorkflow() {
        do {
            let record = try workflowCatalog.create(
                name: newWorkflowName,
                detail: newWorkflowDetail,
                scope: "user",
                cwd: client.workingDirectory
            )
            officialWorkflows = workflowCatalog.load(cwd: client.workingDirectory)
            showAddWorkflow = false
            newWorkflowName = ""
            newWorkflowDetail = ""
            flash(copy.t("Saved \(record.name).rhai", "已保存 \(record.name).rhai"))
            runWorkflow(record)
        } catch {
            flash(error.localizedDescription)
        }
    }

    func deleteWorkflow(_ record: WorkflowRecord) {
        do {
            try workflowCatalog.delete(record)
            officialWorkflows = workflowCatalog.load(cwd: client.workingDirectory)
        } catch {
            flash(error.localizedDescription)
        }
    }

    func addMCPServer() {
        let args = mcpArgs.split(whereSeparator: \.isWhitespace).map(String.init)
        do {
            try mcpCatalog.add(
                name: mcpName,
                transport: mcpTransport,
                commandOrURL: mcpCommand,
                args: args,
                locator: locator
            )
            mcpServers = mcpCatalog.load(locator: locator, cwd: client.workingDirectory)
            grokConfig = configStore.load()
            showAddMCP = false
            mcpName = ""
            mcpCommand = ""
            mcpArgs = ""
            flash(copy.t("Added MCP server", "已添加 MCP"))
        } catch {
            flash(error.localizedDescription)
        }
    }

    func removeMCPServer(_ record: MCPServerRecord) {
        do {
            try mcpCatalog.remove(name: record.name, locator: locator)
            mcpServers = mcpCatalog.load(locator: locator, cwd: client.workingDirectory)
        } catch {
            flash(error.localizedDescription)
        }
    }

    func toggleMCPServer(_ record: MCPServerRecord) {
        do {
            try mcpCatalog.setEnabled(record.name, enabled: !record.enabled, locator: locator)
            mcpServers = mcpCatalog.load(locator: locator, cwd: client.workingDirectory)
        } catch {
            flash(error.localizedDescription)
        }
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
        let rest = line.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        switch name {
        case "/new", "/clear":
            startNewSession()
        case "/settings", "/config", "/prefs":
            showSettings = true
        case "/dashboard", "/sessions", "/agents-dashboard":
            destination = .dashboard
            sidebarCollapsed = false
        case "/home", "/welcome":
            openChat()
        case "/resume":
            showResumePicker = true
            sidebarCollapsed = false
            showSearchField = true
        case "/rename", "/title":
            if let id = client.sessionID, let record = sessions.first(where: { $0.id == id }) {
                if rest == "--auto" || rest.isEmpty {
                    renamingSession = record
                    renameDraft = record.title
                } else {
                    rename(record, title: rest)
                }
            }
        case "/delete":
            if let id = client.sessionID, let record = sessions.first(where: { $0.id == id }) {
                delete(record)
            }
        case "/export":
            if let id = client.sessionID, let record = sessions.first(where: { $0.id == id }) {
                export(record)
            }
        case "/copy":
            copyLatestReply()
        case "/fork":
            forkCurrent()
        case "/plan":
            client.setMode(.plan)
            if !rest.isEmpty {
                draft = rest
                sendDraft()
            }
        case "/jump", "/timeline":
            jumpLatest()
        case "/rewind", "/undo":
            Task { await client.rewind() }
        case "/compact":
            Task { await client.compact(note: rest) }
        case "/feedback":
            draft = rest.isEmpty ? "/feedback" : "/feedback \(rest)"
            sendDraft()
        case "/logout":
            logout()
        case "/login":
            login()
        case "/context", "/session-info", "/status", "/info":
            showInspector = true
            destination = .chat
            flash(sessionInfoLine())
        case "/docs":
            openDocs()
        case "/changelog":
            openChangelog()
        case "/imagine":
            destination = .imagine
            if !rest.isEmpty {
                draft = "/imagine \(rest)"
                destination = .chat
                sendDraft()
            }
        case "/usage", "/cost":
            if rest == "manage" {
                openAccountUsage()
            } else {
                openUsage()
            }
        case "/quit", "/exit":
            NSApp.terminate(nil)
        default:
            draft = line
            sendDraft()
        }
        showPalette = false
    }

    func retryLocate() {
        firstRunReason = bootstrapReason()
        if firstRunReason == nil {
            startNewSession()
        }
    }

    func login() {
        guard locator.locate() != nil else {
            firstRunReason = .missingCLI
            return
        }
        Task {
            do {
                let challenge = try await client.beginLogin()
                if let url = challenge.url {
                    NSWorkspace.shared.open(url)
                }
                firstRunReason = client.authPresence.isReady ? nil : .unsigned
                account = AccountProfile.load()
                refreshAccountUsage()
            } catch {
                fallbackLogin()
            }
        }
    }

    func submitLoginCode() {
        let code = loginCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        Task {
            do {
                try await client.submitLoginCode(code)
                account = AccountProfile.load()
                loginCode = ""
                firstRunReason = bootstrapReason()
                refreshAccountUsage()
            } catch {
                fallbackLogin()
            }
        }
    }

    func logout() {
        guard let grok = locator.locate() else { return }
        let process = Process()
        process.executableURL = grok
        process.arguments = ["logout"]
        try? process.run()
        process.waitUntilExit()
        client.refreshAuth()
        account = AccountProfile()
        accountUsage = AccountUsage()
        firstRunReason = bootstrapReason()
    }

    func exportDiagnostics() {
        let text = DiagnosticExport.make(
            version: "0.1.0",
            grokVersion: client.grokVersion,
            state: String(describing: client.state),
            lastError: client.lastError,
            sessionID: client.sessionID,
            cwd: client.workingDirectory.path,
            stderr: client.stderrLines
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "grok-desktop-diagnostic.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func fallbackLogin() {
        guard let grok = locator.locate() else { return }
        let process = Process()
        process.executableURL = grok
        process.arguments = ["login"]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.client.refreshAuth()
            self.account = AccountProfile.load()
            self.refreshAccountUsage()
            if self.client.authPresence.isReady {
                self.firstRunReason = nil
            }
        }
    }

    func openUsage() {
        settingsSection = .usage
        showSettings = true
        refreshAccountUsage()
    }

    func openAccountUsage() {
        if let url = URL(string: "https://grok.com/?_s=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAPIUsage() {
        if let url = URL(string: "https://console.x.ai/") {
            NSWorkspace.shared.open(url)
        }
    }

    func installCLI() {
        flash(copy.t("Installing grok CLI…", "正在安装 grok CLI…"))
        Task {
            let code: Int32 = await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-lc", "curl -fsSL https://x.ai/cli/install.sh | bash"]
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                } catch {
                    return -1
                }
            }.value
            retryLocate()
            if code == 0, firstRunReason == nil {
                flash(copy.t("CLI installed", "CLI 已安装"))
            } else if code != 0 {
                flash(copy.t("Install failed. Copy the curl command and run it in Terminal.", "安装失败。把 curl 命令拷到终端执行。"))
            } else {
                flash(copy.t("Install finished. Recheck if grok is still missing.", "安装结束。若仍找不到 grok，点重新检测。"))
            }
        }
    }

    func openDocs() {
        if let url = URL(string: "https://docs.x.ai/build/overview") {
            NSWorkspace.shared.open(url)
        }
    }

    func openChangelog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/CHANGELOG.md")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else if let web = URL(string: "https://github.com/xai-org/grok-build/releases") {
            NSWorkspace.shared.open(web)
        }
    }

    func pasteAttachments() {
        let board = NSPasteboard.general
        if let images = board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let url = Self.writePasteImage(image) {
                    insertMention(url)
                }
            }
            return
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls { insertMention(url) }
        }
    }

    func sessionInfoLine() -> String {
        let id = client.sessionID.map { String($0.prefix(8)) } ?? "—"
        return "\(client.buildModel.rawValue) · \(client.effort.rawValue) · \(workspace.contextPercent)% · \(id)"
    }

    private static func writePasteImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grok-paste-\(UUID().uuidString).png")
        try? data.write(to: url)
        return url
    }

    private func present(_ error: Error) {
        flash(error.localizedDescription)
        if let acp = error as? ACPError, acp == .grokNotFound {
            firstRunReason = .missingCLI
        } else if error.localizedDescription.lowercased().contains("auth")
                    || error.localizedDescription.lowercased().contains("login")
                    || error.localizedDescription.lowercased().contains("unauthor") {
            firstRunReason = .unsigned
        } else {
            firstRunReason = .agent(error.localizedDescription)
        }
    }
}
