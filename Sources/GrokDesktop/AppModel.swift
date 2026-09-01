import AppKit
import Combine
import Foundation
import GrokDesktopCore
import SwiftUI
import UniformTypeIdentifiers

enum MainDestination: String {
    case webChat
    case build
    case dashboard
    case imagine
    case automations
    case skills

    var isBuildSurface: Bool { self != .webChat }
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
    @Published var inspectorWidth: CGFloat = GrokTheme.inspectorWidth
    @Published var previewedFile: URL?
    @Published var inspectorDetailsVisible = true
    @Published var hiddenInspectorPanes: Set<String> = []
    @Published var showSearchField = false
    @Published var showAttachMenu = false
    @Published var showCreateProject = false
    @Published var showLanguagePicker = false
    @Published var sidebarCollapsed = false
    @Published var projectsExpanded = true
    @Published var historyExpanded = true
    @Published var historyFolderExpanded: [String: Bool] = [:]
    @Published var destination: MainDestination = .build
    @Published var lastBuildDestination: MainDestination = .build
    @Published var didOpenWebChat = false
    @Published var showInAppLogin = false
    @Published var inAppLoginURL: URL?
    @Published var webChatSignedIn = false
    @Published var isPrivateChat = false
    @Published var settingsSection: SettingsSection = .account
    @Published var firstRunReason: FirstRunReason?
    @Published var account = AccountProfile()
    @Published var skills: [SkillRecord] = []
    @Published var catalogsLoading = false
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
    @Published var showPromptHistory = false
    @Published var showCLIReport = false
    @Published var showDocsPicker = false
    @Published var showFeedbackSheet = false
    @Published var showShortcuts = false
    @Published var showClaudeImport = false
    @Published var docsPickerTutorial = false
    @Published var cliReportTitle = ""
    @Published var cliReportBody = ""
    @Published var feedbackDraft = ""
    @Published var historyCursor: Int?
    @Published var claudeImport = ClaudeImportSnapshot()
    @Published var promptHistory: [String] = UserDefaults.standard.stringArray(forKey: "promptHistory") ?? []
    private var escapeArmedAt: Date?
    private var loginPollTask: Task<Void, Never>?
    private var toastToken = UUID()
    private var catalogsTask: Task<Void, Never>?
    private var catalogsCwd: String?
    @Published var sidebarNotice: String?
    @Published var needsFolderPick = false
    @Published var personas: [String] = []
    @Published var officialWorkflows: [WorkflowRecord] = []
    @Published var mcpServers: [MCPServerRecord] = []
    @Published var plugins: [PluginRecord] = []
    @Published var marketplaces: [MarketplaceSource] = []
    @Published var hookDefinitions: [HookDefinition] = []
    @Published var memoryFiles: [MemoryFile] = []
    @Published var worktrees: [WorktreeRecord] = []
    @Published var showMemory = false
    @Published var showWorktrees = false
    @Published var pluginPending: PluginRecord?
    @Published var pluginSource = ""
    @Published var pluginBusy = false
    @Published var newWorktreeName = ""
    @Published var showAddWorkflow = false
    @Published var showAddMCP = false
    @Published var showFind = false
    @Published var findQuery = ""
    @Published var findTimeline = false
    @Published var showRewind = false
    @Published var showAgents = false
    @Published var agentsTab = 0
    @Published var showContextSheet = false
    @Published var contextBreakdown = ContextBreakdown()
    @Published var workflowRuns: [WorkflowRun] = []
    @Published var automationsTab = 1
    @Published var agentDefinitions: [AgentDefinition] = []
    @Published var personaDefinitions: [PersonaDefinition] = []
    @Published var newPersonaName = ""
    @Published var newPersonaDetail = ""
    @Published var newPersonaBody = ""
    @Published var newAgentName = ""
    @Published var newAgentDetail = ""
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
    @Published var goalMode = false

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
    let workflowRunStore = WorkflowRunStore()
    let mcpCatalog = MCPCatalog()
    let agentCatalog = AgentCatalog()
    private var clientCancellables = Set<AnyCancellable>()

    init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        sessionIndex: SessionIndex = SessionIndex()
    ) {
        self.locator = locator
        self.sessionIndex = sessionIndex
        self.client = ACPClient(locator: locator)
        restoreInspectorWidth()
        restoreInspectorPanes()
        restoreWorkingDirectory()
        restoreProductSurface()
        refreshAll()
        firstRunReason = bootstrapReason()
        refreshWorkspace()
        refreshAccountUsage()
        bindClient()
        if DemoStudio.isEnabled {
            applyDemoStudio()
        }
        AttentionCenter.shared.onOpenSession = { [weak self] id in
            self?.openWaitingSession(id)
        }
        ChatLinkActions.previewFile = { [weak self] url in
            self?.previewFile(url)
        }
    }

    func previewFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue {
            ChatLinkActions.open(standardized)
            return
        }
        // Defer past the current hit-test / constraint pass. Mutating
        // inspector width + inserting a preview during click crashes AppKit.
        afterHitTest { [weak self] in
            guard let self else { return }
            self.previewedFile = standardized
            self.showInspector = true
            self.inspectorDetailsVisible = false
            if self.inspectorWidth <= GrokTheme.inspectorWidth {
                self.setInspectorWidth(GrokTheme.inspectorPreviewWidth)
            }
            if self.destination != .build {
                self.destination = .build
            }
        }
    }

    func clearPreview() {
        afterHitTest { [weak self] in
            self?.previewedFile = nil
            self?.inspectorDetailsVisible = true
        }
    }

    func setInspectorWidth(_ width: CGFloat) {
        let next = GrokTheme.clampInspectorWidth(width)
        guard inspectorWidth != next else { return }
        inspectorWidth = next
        UserDefaults.standard.set(Double(next), forKey: "inspectorWidth")
    }

    func resetInspectorWidth() {
        setInspectorWidth(previewedFile == nil ? GrokTheme.inspectorWidth : GrokTheme.inspectorPreviewWidth)
    }

    func inspectorPaneVisible(_ pane: InspectorPane) -> Bool {
        !hiddenInspectorPanes.contains(pane.rawValue)
    }

    func hideInspectorPane(_ pane: InspectorPane) {
        afterHitTest { [weak self] in
            guard let self else { return }
            self.hiddenInspectorPanes.insert(pane.rawValue)
            self.persistInspectorPanes()
        }
    }

    func showInspectorPane(_ pane: InspectorPane) {
        afterHitTest { [weak self] in
            guard let self else { return }
            self.hiddenInspectorPanes.remove(pane.rawValue)
            self.inspectorDetailsVisible = true
            self.persistInspectorPanes()
        }
    }

    func showAllInspectorPanes() {
        afterHitTest { [weak self] in
            guard let self else { return }
            self.hiddenInspectorPanes.removeAll()
            self.inspectorDetailsVisible = true
            self.persistInspectorPanes()
        }
    }

    var hiddenInspectorPaneList: [InspectorPane] {
        InspectorPane.allCases.filter { hiddenInspectorPanes.contains($0.rawValue) }
    }

    var displayedContextPercent: Int {
        if workspace.contextPercent > 0 { return workspace.contextPercent }
        return contextBreakdown.percent
    }

    var displayedContextUsed: Int {
        max(workspace.contextUsed, contextBreakdown.used)
    }

    var displayedContextWindow: Int {
        let window = workspace.contextWindow > 0 ? workspace.contextWindow : contextBreakdown.window
        return window > 0 ? window : 200_000
    }

    private func applyDemoStudio() {
        account = DemoStudio.account
        accountUsage = DemoStudio.usage
        sessions = DemoStudio.sessions()
        namedProjects = [DemoStudio.project]
        skills = []
        automations = []
        officialWorkflows = []
        mcpServers = []
        firstRunReason = nil
        didOpenWebChat = false
        destination = .build
        lastBuildDestination = .build
        showInspector = true
        inspectorDetailsVisible = true
        hiddenInspectorPanes = []
        previewedFile = nil
        client.applyDemo(
            items: DemoStudio.items,
            todos: DemoStudio.todos,
            hunks: DemoStudio.hunks,
            planEntries: DemoStudio.plan,
            gitDiff: DemoStudio.gitDiff,
            cwd: DemoStudio.cwd
        )
        workspace = DemoStudio.workspace
        refreshContextBreakdown()
        if let url = DemoStudio.screenshotURL {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                let ok = DemoStudio.writeScreenshot(model: self, to: url)
                fputs(ok ? "Wrote demo screenshot \(url.path)\n" : "Failed to write demo screenshot\n", stderr)
                if DemoStudio.shouldExitAfterScreenshot {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func afterHitTest(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            work()
        }
    }

    private func persistInspectorPanes() {
        UserDefaults.standard.set(Array(hiddenInspectorPanes), forKey: "hiddenInspectorPanes")
    }

    private func restoreInspectorPanes() {
        if let stored = UserDefaults.standard.array(forKey: "hiddenInspectorPanes") as? [String] {
            hiddenInspectorPanes = Set(stored)
        }
    }

    private func restoreInspectorWidth() {
        let stored = UserDefaults.standard.double(forKey: "inspectorWidth")
        if stored >= Double(GrokTheme.inspectorMinWidth) {
            inspectorWidth = GrokTheme.clampInspectorWidth(CGFloat(stored))
        }
    }

    private func bindClient() {
        clientCancellables.removeAll()
        client.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.syncAttention()
            }
            .store(in: &clientCancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncAttention()
            }
            .store(in: &clientCancellables)
    }

    func prepareAttention() {
        if notifyThinking {
            AttentionCenter.shared.prepare()
        }
        syncAttention()
    }

    func openWaitingSession(_ id: String) {
        if client.focusIfLoaded(id) {
            destination = .build
            showInspector = true
            return
        }
        if let record = sessions.first(where: { $0.id == id }) {
            open(record)
            return
        }
        destination = .build
    }

    func dispatchWork(_ text: String) {
        let trimmed = applyGoalIfNeeded(text)
        guard !trimmed.isEmpty else { return }
        recordPrompt(trimmed)
        destination = .dashboard
        Task {
            do {
                try await client.newSession(cwd: client.workingDirectory)
                try await client.send(text: trimmed)
                if !isPrivateChat {
                    refreshSessions()
                }
                refreshWorkspace()
            } catch {
                present(error)
            }
        }
    }

    var attentionNeeds: [AttentionNeed] {
        let chinese = language.resolved() == .chinese
        return client.liveWorkspaces.compactMap { workspace in
            if workspace.userQuestion != nil {
                return AttentionNeed(
                    sessionID: workspace.id,
                    kind: .question,
                    title: chinese ? "Grok 在等你回答" : "Grok is waiting for an answer",
                    body: workspace.title.isEmpty
                        ? workspace.cwd.lastPathComponent
                        : workspace.title
                )
            }
            if workspace.permission != nil {
                return AttentionNeed(
                    sessionID: workspace.id,
                    kind: .permission,
                    title: chinese ? "Grok 在等你批准" : "Grok needs approval",
                    body: workspace.title.isEmpty
                        ? workspace.cwd.lastPathComponent
                        : workspace.title
                )
            }
            return nil
        }
    }

    func syncAttention() {
        AttentionCenter.shared.sync(
            needs: attentionNeeds,
            focusedSessionID: client.sessionID,
            destinationIsChat: destination == .build,
            enabled: notifyThinking
        )
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
        automations = automationStore.load()
        namedProjects = projectStore.load()
        grokConfig = configStore.load()
        showThinkingBlocks = grokConfig.showThinking
        officialWorkflows = workflowCatalog.load(cwd: client.workingDirectory)
        refreshWorkflowRuns()
        refreshCatalogs()
        refreshAgentCatalog()
    }

    func refreshCatalogs(force: Bool = false) {
        if DemoStudio.isEnabled { return }
        let cwd = client.workingDirectory
        let key = cwd.standardizedFileURL.path
        if !force, GrokInspect.isFresh(cwd: cwd), catalogsCwd == key, !skills.isEmpty {
            return
        }
        if skills.isEmpty, let cached = GrokInspect.cached(cwd: cwd) {
            applyCatalogs(skills: cached.skills, mcp: cached.mcp, listed: [], cwd: key)
        }
        if catalogsTask != nil, !force { return }
        catalogsLoading = skills.isEmpty
        let grokLocator = locator
        catalogsTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) { () -> (
                skills: [SkillRecord],
                mcp: [MCPServerRecord],
                listed: [MCPServerRecord],
                plugins: [PluginRecord],
                hooks: [HookDefinition],
                marketplaces: [MarketplaceSource]
            ) in
                let listed = MCPCatalog().load(locator: grokLocator, cwd: cwd)
                let catalog = PluginCatalog.load(locator: grokLocator, cwd: cwd)
                if let inspect = GrokInspect.load(locator: grokLocator, cwd: cwd, force: force) {
                    return (
                        inspect.skills,
                        inspect.mcp,
                        listed,
                        PluginCatalog.merge(inspect: inspect.plugins, listed: catalog.plugins),
                        inspect.hooks,
                        catalog.marketplaces
                    )
                }
                let disk = SkillCatalog().load(cwd: cwd)
                return (disk, listed, listed, catalog.plugins, [], catalog.marketplaces)
            }.value
            await MainActor.run {
                guard let self else { return }
                self.catalogsTask = nil
                self.catalogsLoading = false
                self.applyCatalogs(
                    skills: snapshot.skills,
                    mcp: snapshot.mcp,
                    listed: snapshot.listed,
                    plugins: snapshot.plugins,
                    hooks: snapshot.hooks,
                    marketplaces: snapshot.marketplaces,
                    cwd: key
                )
            }
        }
    }

    private func applyCatalogs(
        skills: [SkillRecord],
        mcp: [MCPServerRecord],
        listed: [MCPServerRecord],
        plugins: [PluginRecord] = [],
        hooks: [HookDefinition] = [],
        marketplaces: [MarketplaceSource] = [],
        cwd: String
    ) {
        grokConfig = configStore.load()
        let disabled = Set(grokConfig.disabledSkills.map { $0.lowercased() })
        if !skills.isEmpty {
            self.skills = skills.map { $0.marking(enabled: !disabled.contains($0.slug.lowercased())) }
        }
        if !mcp.isEmpty {
            mcpServers = MCPCatalog.merge(inspect: mcp, listed: listed)
        } else if !listed.isEmpty {
            mcpServers = listed
        }
        if !plugins.isEmpty {
            self.plugins = plugins
        }
        if !hooks.isEmpty {
            hookDefinitions = hooks
        }
        if !marketplaces.isEmpty {
            self.marketplaces = marketplaces
        }
        catalogsCwd = cwd
        extensions = ExtensionInventory.load(mcpNames: grokConfig.mcpNames)
    }

    func refreshAgentCatalog() {
        agentDefinitions = agentCatalog.loadAgents(cwd: client.workingDirectory)
        personaDefinitions = agentCatalog.loadPersonas(cwd: client.workingDirectory)
        personas = personaDefinitions.map(\.slug)
    }

    func refreshContextBreakdown() {
        contextBreakdown = ContextBreakdown.make(
            items: client.items,
            sessionDirectory: client.sessionDirectory,
            skillCount: skills.count,
            mcpCount: mcpServers.count,
            model: client.buildModel.rawValue,
            sessionID: client.sessionID ?? ""
        )
    }

    var findHits: [ChatSearchHit] {
        if findTimeline {
            return ChatSearch.timeline(in: client.items)
        }
        return ChatSearch.hits(in: client.items, query: findQuery)
    }

    var rewindTurns: [RewindTurn] {
        ChatSearch.rewindTurns(in: client.items, dates: client.itemDates)
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

    func flash(_ text: String, duration: TimeInterval = 2.6) {
        toast = text
        let token = UUID()
        toastToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    func copySelection(_ text: String) {
        copyText(text)
        flash(copy.copied, duration: 1.2)
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
        let chinese = language.resolved() == .chinese
        return visible.filter { SessionSearch.matches($0, query: query, chinese: chinese) }
    }

    var historyFolders: [HistoryFolder] {
        HistoryFolder.group(filteredSessions, namedProjects: namedProjects, untitled: copy.otherProject)
    }

    func isHistoryFolderExpanded(_ folder: HistoryFolder) -> Bool {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let override = historyFolderExpanded[folder.id] {
            return override
        }
        if historyFolders.count <= 1 {
            return true
        }
        if folder.id == historyFolders.first?.id {
            return true
        }
        let current = client.workingDirectory.standardizedFileURL.path
        if !folder.path.isEmpty, folder.path == current {
            return true
        }
        if let sessionID = client.sessionID, folder.sessions.contains(where: { $0.id == sessionID }) {
            return true
        }
        return false
    }

    func toggleHistoryFolder(_ folder: HistoryFolder) {
        guard search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        historyFolderExpanded[folder.id] = !isHistoryFolderExpanded(folder)
    }

    func expandHistoryFolder(path: String) {
        let key = HistoryFolder.standardizedPath(path)
        guard !key.isEmpty else { return }
        historyFolderExpanded[key] = true
    }

    func isCurrentHistoryFolder(_ folder: HistoryFolder) -> Bool {
        !folder.path.isEmpty
            && folder.path == client.workingDirectory.standardizedFileURL.path
    }

    var visibleProjects: [NamedProject] {
        NamedProject.merged(named: namedProjects, sessionPaths: projectPaths)
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
        destination == .build && client.items.isEmpty && firstRunReason == nil
    }

    var isHomeDirectory: Bool {
        client.workingDirectory.standardizedFileURL.path
            == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }

    var filteredSkills: [SkillRecord] {
        let query = skillsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
                || $0.slug.localizedCaseInsensitiveContains(query)
        }
    }

    var skillGroups: [(id: String, title: String, items: [SkillRecord])] {
        let chinese = language.resolved() == .chinese
        let order: [(String, String)] = [
            ("project", chinese ? "项目" : "Project"),
            ("user", chinese ? "个人" : "Personal"),
            ("bundled", chinese ? "内置" : "Bundled"),
            ("plugin", chinese ? "插件" : "Plugins")
        ]
        return order.compactMap { key, title in
            let items = filteredSkills.filter { $0.sourceKind == key }
            guard !items.isEmpty else { return nil }
            return (key, title, items)
        }
    }

    var filteredMCPServers: [MCPServerRecord] {
        let query = skillsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return mcpServers }
        return mcpServers.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    func refreshSessions() {
        if DemoStudio.isEnabled {
            sessions = DemoStudio.sessions()
            return
        }
        sessions = sessionIndex.load()
        refreshWorkspace()
    }

    func refreshWorkspace() {
        if DemoStudio.isEnabled {
            workspace = DemoStudio.workspace
            refreshContextBreakdown()
            return
        }
        refreshContextBreakdown()
        let cwd = client.workingDirectory
        let sessionDir = sessions.first(where: { $0.id == client.sessionID })?.directory ?? client.sessionDirectory
        if workspace.path != cwd.path {
            workspace = WorkspaceSnapshot(path: cwd.path, name: cwd.lastPathComponent)
        }
        Task { [weak self] in
            let loaded = await Task.detached {
                WorkspaceSnapshot.load(cwd: cwd, sessionDirectory: sessionDir)
            }.value
            guard let self else { return }
            guard self.client.workingDirectory.standardizedFileURL.path == cwd.standardizedFileURL.path else { return }
            self.workspace = loaded
        }
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
        destination = .build
        rememberBuildDestination()
        client.resetConversation()
        firstRunReason = locator.locate() == nil ? .missingCLI : nil
    }

    func openWebChat() {
        didOpenWebChat = true
        showPalette = false
        showAttachMenu = false
        mentionQuery = nil
        destination = .webChat
        UserDefaults.standard.set("webChat", forKey: "productSurface")
        Task { await refreshWebChatAuth() }
    }

    func openBuildSurface() {
        if destination == .webChat {
            destination = lastBuildDestination == .webChat ? .build : lastBuildDestination
        }
        rememberBuildDestination()
        UserDefaults.standard.set("build", forKey: "productSurface")
    }

    func rememberBuildDestination() {
        if destination.isBuildSurface {
            lastBuildDestination = destination
        }
    }

    private func restoreProductSurface() {
        if UserDefaults.standard.string(forKey: "productSurface") == "webChat" {
            didOpenWebChat = true
            destination = .webChat
        }
    }

    func refreshWebChatAuth() async {
        webChatSignedIn = await GrokWebSession.chatLikelySignedIn()
    }

    func startNewSession() {
        startNewSession(cwd: client.workingDirectory)
    }

    func startNewSession(cwd: URL) {
        destination = .build
        expandHistoryFolder(path: cwd.path)
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
        let key = project.standardizedPath
        if namedProjects.isEmpty {
            namedProjects = projectPaths.map { NamedProject(id: $0.path, name: $0.name, path: $0.path) }
        }
        namedProjects.removeAll { $0.standardizedPath == key }
        namedProjects.insert(project, at: 0)
        projectStore.save(namedProjects)
        showCreateProject = false
        newProjectName = ""
        newProjectFolder = nil
        startNewSession(cwd: folder)
    }

    func open(_ record: SessionRecord) {
        destination = .build
        isPrivateChat = false
        firstRunReason = nil
        sidebarNotice = nil
        expandHistoryFolder(path: record.cwd)
        if client.focusIfLoaded(record.id) {
            refreshWorkspace()
            Task { await client.refreshGit() }
            return
        }
        Task {
            do {
                try await client.loadSession(id: record.id, cwd: URL(fileURLWithPath: record.cwd), directory: record.directory)
                guard client.sessionID == record.id else { return }
                refreshWorkspace()
                await client.refreshGit()
            } catch {
                guard client.sessionID == record.id else { return }
                sidebarNotice = copy.t("Couldn't resume “\(record.title)”", "无法恢复「\(record.title)」")
                flash(sidebarNotice ?? error.localizedDescription)
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
        let backup = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/last-copy.txt")
        try? text.write(to: backup, atomically: true, encoding: .utf8)
    }

    func restorePromptToComposer(_ text: String) {
        let shown = PromptMedia.displayText(text)
        draft = shown.isEmpty ? text : shown
        destination = .build
        showPalette = false
        mentionQuery = nil
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
        destination = .build
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
        suppressSuggest = true
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

    func applyGoalIfNeeded(_ text: String) -> String {
        SessionFold.applyGoal(text, enabled: goalMode)
    }

    func toggleGoalMode() {
        goalMode.toggle()
        showAttachMenu = false
        mentionQuery = nil
        showPalette = false
    }

    func sendDraft() {
        let text = applyGoalIfNeeded(draft)
        historyCursor = nil
        recordPrompt(text)
        draft = ""
        destination = .build
        let aside = SessionFold.isAside(text)
        Task {
            do {
                try await client.send(text: text, kind: aside ? .aside : .followUp)
                if !isPrivateChat {
                    refreshSessions()
                }
                refreshWorkspace()
                refreshWorkflowRuns()
            } catch {
                present(error)
            }
        }
    }

    func sendImagine(_ text: String) {
        let trimmed = applyGoalIfNeeded(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        historyCursor = nil
        recordPrompt(trimmed)
        showPalette = false
        Task {
            do {
                try await client.send(text: trimmed, kind: SessionFold.isAside(trimmed) ? .aside : .followUp)
                if !isPrivateChat {
                    refreshSessions()
                }
                refreshWorkspace()
            } catch {
                present(error)
            }
        }
    }

    func enqueueAside(_ text: String) {
        destination = .build
        draft = ""
        showPalette = false
        Task {
            do {
                try await client.send(text: text, kind: .aside)
            } catch {
                present(error)
            }
        }
    }



    func beginBusySend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingBusySend = applyGoalIfNeeded(trimmed)
        draft = ""
        showAttachMenu = false
        showPalette = false
    }

    func confirmBusySendNow() {
        guard let text = pendingBusySend else { return }
        pendingBusySend = nil
        historyCursor = nil
        recordPrompt(text)
        destination = .build
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
        if DemoStudio.isEnabled {
            accountUsage = DemoStudio.usage
            return
        }
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
        guard skill.enabled else {
            flash(copy.t("Skill is off. Turn it on first.", "这个技能关了。先打开。"))
            return
        }
        destination = .build
        draft = skill.invocation
        sendDraft()
    }

    func toggleSkill(_ skill: SkillRecord) {
        var disabled = Set(grokConfig.disabledSkills)
        if skill.enabled {
            disabled.insert(skill.slug)
        } else {
            disabled.remove(skill.slug)
        }
        let names = disabled.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        do {
            try configStore.set(section: "skills", key: "disabled", array: names)
            grokConfig = configStore.load()
            if let index = skills.firstIndex(where: { $0.slug == skill.slug }) {
                skills[index].enabled = !skill.enabled
            }
        } catch {
            flash(error.localizedDescription)
        }
    }

    var filteredPlugins: [PluginRecord] {
        let query = skillsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = plugins
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
                || $0.marketplace.localizedCaseInsensitiveContains(query)
        }
    }

    var installedPlugins: [PluginRecord] {
        filteredPlugins.filter(\.isInstalled)
    }

    var availablePlugins: [PluginRecord] {
        filteredPlugins.filter(\.isAvailable)
    }

    func confirmInstall(_ plugin: PluginRecord) {
        pluginPending = plugin
    }

    func installPendingPlugin() {
        guard let plugin = pluginPending else { return }
        pluginPending = nil
        runPlugin(
            ["install", plugin.installSource, "--trust"],
            success: copy.t("Installed \(plugin.name)", "已安装 \(plugin.name)")
        )
    }

    func installPluginSource() {
        let source = pluginSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        pluginSource = ""
        runPlugin(
            ["install", source, "--trust"],
            success: copy.t("Installed plugin", "已安装插件")
        )
    }

    func addMarketplaceSource() {
        let source = pluginSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        pluginSource = ""
        runPlugin(
            ["marketplace", "add", source],
            success: copy.t("Added marketplace", "已添加市场")
        )
    }

    func togglePlugin(_ plugin: PluginRecord) {
        let verb = plugin.enabled ? "disable" : "enable"
        runPlugin(
            [verb, plugin.name],
            success: plugin.enabled
                ? copy.t("Disabled \(plugin.name)", "已关闭 \(plugin.name)")
                : copy.t("Enabled \(plugin.name)", "已打开 \(plugin.name)")
        )
    }

    func uninstallPlugin(_ plugin: PluginRecord) {
        runPlugin(
            ["uninstall", plugin.name],
            success: copy.t("Removed \(plugin.name)", "已卸载 \(plugin.name)")
        )
    }

    func runPlugin(_ arguments: [String], success: String) {
        pluginBusy = true
        let cwd = client.workingDirectory
        Task {
            let output = await Task.detached { [locator] in
                guard let binary = locator.locate() else { return (1 as Int32, "grok not found") }
                let process = Process()
                process.executableURL = binary
                process.arguments = ["plugin"] + arguments
                process.currentDirectoryURL = cwd
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    return (1, error.localizedDescription)
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                return (process.terminationStatus, text)
            }.value
            pluginBusy = false
            refreshCatalogs(force: true)
            if output.0 == 0 {
                flash(success)
            } else {
                cliReportTitle = "grok plugin \(arguments.joined(separator: " "))"
                cliReportBody = output.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? copy.t("Command failed.", "命令失败。")
                    : output.1
                showCLIReport = true
            }
        }
    }

    func refreshMemoryFiles() {
        memoryFiles = MemoryCatalog.load()
    }

    func openMemoryFile(_ file: MemoryFile) {
        previewedFile = file.url
        showInspector = true
        destination = .build
        showMemory = false
    }

    func refreshWorktrees() {
        worktrees = WorktreeCatalog.load(locator: locator, cwd: client.workingDirectory)
    }

    func openWorktree(_ tree: WorktreeRecord) {
        showWorktrees = false
        startNewSession(cwd: tree.url)
    }

    func createWorktree() {
        let name = newWorktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let url = try WorktreeCatalog.create(named: name, cwd: client.workingDirectory)
            newWorktreeName = ""
            showWorktrees = false
            startNewSession(cwd: url)
            flash(copy.t("Opened worktree \(name)", "已打开 worktree \(name)"))
        } catch {
            flash(error.localizedDescription)
        }
    }

    func removeWorktree(_ tree: WorktreeRecord) {
        runGrokCLI(arguments: ["worktree", "rm", tree.path], title: "/worktree rm")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshWorktrees()
        }
    }

    func openSubagent(_ agent: AgentSubagent) {
        let id = agent.childSessionId.isEmpty ? agent.id : agent.childSessionId
        if client.focusIfLoaded(id) {
            destination = .build
            showInspector = true
            return
        }
        if let record = sessions.first(where: { $0.id == id }) ?? sessionIndex.record(id: id) {
            open(record)
            return
        }
        flash(copy.t("No transcript for this subagent yet.", "这个子 agent 还没有 transcript。"))
    }

    func cancelScheduledTask(_ task: ScheduledTask) {
        destination = .build
        draft = "Cancel scheduled task \(task.id) (\(task.title))"
        sendDraft()
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
        destination = .build
        draft = record.prompt
        sendDraft()
    }

    func runWorkflow(_ record: WorkflowRecord) {
        launchWorkflow(named: record.name)
    }

    func openFind(query: String, timeline: Bool) {
        findQuery = query
        findTimeline = timeline
        showFind = true
        destination = .build
    }

    func jumpToHit(_ hit: ChatSearchHit) {
        jumpTarget = hit.id
        showFind = false
        destination = .build
    }

    func handleWorkflowCommand(_ rest: String) {
        let parts = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.isEmpty {
            automationsTab = 0
            destination = .automations
            return
        }
        let verb = parts[0].lowercased()
        if ["pause", "resume", "stop", "save"].contains(verb), parts.count >= 2 {
            controlWorkflow(name: parts[1], verb: verb)
            return
        }
        launchWorkflow(named: parts[0], extra: parts.dropFirst().joined(separator: " "))
    }

    func launchWorkflow(named name: String, extra: String = "") {
        let display = uniqueWorkflowName(name)
        workflowRuns.insert(WorkflowRun(name: display, status: "running", note: extra), at: 0)
        workflowRunStore.save(workflowRuns)
        destination = .build
        automationsTab = 0
        let line = extra.isEmpty ? "/workflow \(name)" : "/workflow \(name) \(extra)"
        draft = line
        sendDraft()
        refreshWorkflowRuns()
    }

    func refreshWorkflowRuns() {
        if DemoStudio.isEnabled { return }
        let overlay = workflowRunStore.load()
        let disk = WorkflowRunStore.scan(
            sessionsRoot: sessionIndex.sessionsRoot,
            currentSession: client.sessionDirectory
        )
        let liveTitles = client.tasks.filter(\.isRunning).map(\.title)
            + client.subagents.filter(\.isRunning).map { $0.detail.isEmpty ? $0.type : $0.detail }
        let reconciled = WorkflowRunStore.reconcile(
            overlay: overlay,
            disk: disk,
            liveTitles: liveTitles,
            turnRunning: client.isTurnRunning
        )
        workflowRuns = reconciled
        workflowRunStore.save(reconciled)
    }

    func controlWorkflow(name: String, verb: String) {
        if let index = workflowRuns.firstIndex(where: { $0.name == name || $0.id == name }) {
            switch verb {
            case "pause": workflowRuns[index].status = "paused"
            case "resume": workflowRuns[index].status = "running"
            case "stop": workflowRuns[index].status = "stopped"
            default: break
            }
            workflowRunStore.save(workflowRuns)
        }
        destination = .build
        draft = "/workflow \(verb) \(name)"
        sendDraft()
        refreshWorkflowRuns()
    }

    func uniqueWorkflowName(_ name: String) -> String {
        let existing = Set(workflowRuns.map(\.name))
        if !existing.contains(name) { return name }
        var index = 2
        while existing.contains("\(name)-\(index)") { index += 1 }
        return "\(name)-\(index)"
    }

    func rewindTo(_ turn: RewindTurn) {
        showRewind = false
        Task {
            await client.rewind(toPromptIndex: turn.promptIndex)
            refreshSessions()
            flash(copy.t("Rewound to turn \(turn.promptIndex + 1)", "已回退到第 \(turn.promptIndex + 1) 轮"))
        }
    }

    func createUserPersona() {
        do {
            _ = try agentCatalog.createPersona(name: newPersonaName, detail: newPersonaDetail, instructions: newPersonaBody)
            newPersonaName = ""
            newPersonaDetail = ""
            newPersonaBody = ""
            refreshAgentCatalog()
            flash(copy.t("Saved persona", "已保存人设"))
        } catch {
            flash(error.localizedDescription)
        }
    }

    func createUserAgent() {
        do {
            _ = try agentCatalog.createAgent(name: newAgentName, detail: newAgentDetail)
            newAgentName = ""
            newAgentDetail = ""
            refreshAgentCatalog()
            flash(copy.t("Saved agent", "已保存 agent"))
        } catch {
            flash(error.localizedDescription)
        }
    }

    func deletePersona(_ persona: PersonaDefinition) {
        do {
            try agentCatalog.deletePersona(persona)
            refreshAgentCatalog()
        } catch {
            flash(error.localizedDescription)
        }
    }

    func deleteAgentDefinition(_ agent: AgentDefinition) {
        do {
            try agentCatalog.deleteAgent(agent)
            refreshAgentCatalog()
        } catch {
            flash(error.localizedDescription)
        }
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
            automationsTab = 1
            destination = .automations
            flash(copy.t("Saved \(record.name).rhai", "已保存 \(record.name).rhai"))
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
            grokConfig = configStore.load()
            showAddMCP = false
            mcpName = ""
            mcpCommand = ""
            mcpArgs = ""
            refreshCatalogs(force: true)
            flash(copy.t("Added MCP server", "已添加 MCP"))
        } catch {
            flash(error.localizedDescription)
        }
    }

    func removeMCPServer(_ record: MCPServerRecord) {
        guard record.managed else {
            flash(copy.t("This connector is inherited. Edit it in the plugin or Claude MCP config.", "这个连接器是继承来的。请在插件或 Claude MCP 配置里改。"))
            return
        }
        do {
            try mcpCatalog.remove(name: record.name, locator: locator)
            refreshCatalogs(force: true)
        } catch {
            flash(error.localizedDescription)
        }
    }

    func toggleMCPServer(_ record: MCPServerRecord) {
        guard record.managed else {
            flash(copy.t("This connector is inherited. Edit it in the plugin or Claude MCP config.", "这个连接器是继承来的。请在插件或 Claude MCP 配置里改。"))
            return
        }
        do {
            try mcpCatalog.setEnabled(record.name, enabled: !record.enabled, locator: locator)
            refreshCatalogs(force: true)
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
        destination = .build
    }

    func handleCommand(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(line.split(separator: " ").first ?? "").lowercased()
        let rest = line.dropFirst(line.split(separator: " ").first?.count ?? 0).trimmingCharacters(in: .whitespaces)
        switch name {
        case "/new", "/clear":
            startNewSession()
        case "/settings", "/config", "/prefs", "/preferences":
            showSettings = true
        case "/dashboard", "/sessions", "/agents-dashboard":
            destination = .dashboard
            sidebarCollapsed = false
        case "/home", "/welcome":
            openChat()
        case "/resume":
            if !rest.isEmpty { search = rest }
            showResumePicker = true
            sidebarCollapsed = false
            showSearchField = true
        case "/continue":
            continueLastInFolder()
        case "/history":
            showPromptHistory = true
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
            copyReply(argument: rest)
        case "/fork":
            forkCurrent()
        case "/plan":
            client.setMode(.plan)
            if !rest.isEmpty {
                draft = rest
                sendDraft()
            }
        case "/view-plan", "/show-plan", "/plan-view":
            destination = .build
            showInspector = true
            client.setMode(.plan)
        case "/jump":
            if rest.isEmpty {
                jumpLatest()
            } else {
                openFind(query: rest, timeline: false)
            }
        case "/timeline":
            openFind(query: "", timeline: true)
        case "/find":
            openFind(query: rest, timeline: false)
        case "/rewind", "/undo":
            showRewind = true
        case "/compact":
            Task { await client.compact(note: rest) }
        case "/model", "/m":
            applyModelCommand(rest)
        case "/effort":
            applyEffortCommand(rest)
        case "/always-approve":
            client.setMode(client.mode == .alwaysApprove ? .normal : .alwaysApprove)
            flash(client.mode.title(chinese: language.resolved() == .chinese))
        case "/auto":
            client.setMode(client.mode == .auto ? .normal : .auto)
            flash(client.mode.title(chinese: language.resolved() == .chinese))
        case "/multiline", "/ml":
            requireCmdEnter.toggle()
            flash(requireCmdEnter ? copy.requireCmdEnter : copy.t("Enter sends", "Enter 发送"))
        case "/compact-mode":
            compactChat.toggle()
        case "/timestamps":
            showTimestamps.toggle()
        case "/theme", "/t":
            applyThemeCommand(rest)
        case "/feedback":
            if rest.isEmpty {
                feedbackDraft = ""
                showFeedbackSheet = true
            } else {
                draft = "/feedback \(rest)"
                sendDraft()
            }
        case "/logout":
            logout()
        case "/login":
            login()
        case "/context", "/session-info", "/status", "/info":
            refreshContextBreakdown()
            showContextSheet = true
        case "/docs", "/howto", "/guides":
            openDocsCommand(rest)
        case "/changelog", "/release-notes":
            openChangelog()
        case "/tutorial", "/tour", "/onboarding":
            docsPickerTutorial = true
            showDocsPicker = true
        case "/imagine":
            destination = .imagine
            if !rest.isEmpty {
                sendImagine("/imagine \(rest)")
            }
        case "/imagine-video":
            destination = .imagine
            if !rest.isEmpty {
                sendImagine("/imagine-video \(rest)")
            }
        case "/usage", "/cost":
            if rest == "manage" {
                openAccountUsage()
            } else {
                openUsage()
            }
        case "/privacy":
            settingsSection = .dataControls
            showSettings = true
        case "/skills":
            destination = .skills
            skillsTab = 0
        case "/hooks", "/hooks-list", "/hooks-trust", "/hooks-add", "/hooks-remove", "/hooks-untrust":
            destination = .build
            showInspector = true
            showInspectorPane(.hooks)
            showSettings = false
        case "/plugins":
            if rest.isEmpty {
                destination = .skills
                skillsTab = 2
            } else {
                let parts = rest.split(whereSeparator: \.isWhitespace).map(String.init)
                runPlugin(parts, success: copy.t("Plugin command finished", "插件命令完成"))
            }
        case "/marketplace":
            destination = .skills
            skillsTab = 2
        case "/mcps":
            if rest.hasPrefix("doctor") {
                let extra = rest.split(whereSeparator: \.isWhitespace).dropFirst().map(String.init)
                runGrokCLI(arguments: ["mcp", "doctor"] + extra, title: "/mcps doctor")
            } else {
                settingsSection = .extensions
                showSettings = true
            }
        case "/workflows":
            automationsTab = 0
            destination = .automations
        case "/workflow":
            handleWorkflowCommand(rest)
        case "/agents", "/config-agents":
            agentsTab = 0
            refreshAgentCatalog()
            showAgents = true
        case "/personas":
            agentsTab = 1
            refreshAgentCatalog()
            showAgents = true
        case "/doctor":
            runGrokCLI(arguments: rest == "fix" ? ["doctor", "fix"] : ["doctor"], title: "/doctor")
        case "/terminal-setup", "/terminal-check", "/terminal-info":
            presentTerminalReport()
        case "/inspect":
            presentInspectReport()
        case "/du", "/disk-usage":
            runGrokCLI(arguments: ["du"], title: "/du")
        case "/models":
            runGrokCLI(arguments: ["models"], title: "/models")
        case "/update":
            runGrokCLI(arguments: ["update", "--check"], title: "/update")
        case "/shortcuts", "/keys":
            showShortcuts = true
        case "/vim-mode", "/minimal", "/fullscreen", "/full", "/edit-prompt", "/expand":
            flash(copy.t("That command is terminal-only.", "这个命令只在终端 TUI 里有。"))
        case "/memory", "/mem":
            applyMemoryCommand(rest)
        case "/btw":
            if rest.isEmpty {
                insertSlashPrompt("/btw")
            } else {
                enqueueAside("/btw \(rest)")
            }
        case "/remember", "/flush", "/dream", "/loop", "/goal", "/deep-research":
            if rest.isEmpty, name == "/remember" || name == "/loop" || name == "/goal" || name == "/deep-research" {
                insertSlashPrompt(name)
            } else {
                draft = rest.isEmpty ? name : "\(name) \(rest)"
                sendDraft()
            }
        case "/import-claude":
            presentClaudeImport()
        case "/worktree":
            let parts = rest.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.isEmpty || parts[0] == "list" || parts[0] == "ls" {
                refreshWorktrees()
                showWorktrees = true
            } else {
                runGrokCLI(arguments: ["worktree"] + parts, title: "/worktree")
            }
        case "/quit", "/exit":
            NSApp.terminate(nil)
        default:
            draft = line
            sendDraft()
        }
        showPalette = false
    }

    func continueLastInFolder() {
        let cwd = client.workingDirectory.path
        if let last = sessions.first(where: { $0.cwd == cwd }) {
            open(last)
        } else {
            flash(copy.t("No previous session in this folder.", "这个文件夹还没有会话。"))
        }
    }

    func applyHistory(_ text: String) {
        draft = text
        historyCursor = promptHistory.firstIndex(of: text)
        showPromptHistory = false
        showPalette = false
        suppressSuggest = true
    }

    func recallHistory(delta: Int) {
        let items = promptHistory
        guard !items.isEmpty else { return }
        let current = historyCursor ?? -1
        let next = current + delta
        if next < 0 {
            historyCursor = nil
            draft = ""
            suppressSuggest = true
            return
        }
        guard next < items.count else { return }
        historyCursor = next
        draft = items[next]
        suppressSuggest = true
        showPalette = false
        mentionQuery = nil
    }

    func handleEscape() -> Bool {
        if mentionQuery != nil || showPalette || showAttachMenu {
            dismissComposerSuggestions()
            return true
        }
        if showPromptHistory { showPromptHistory = false; return true }
        if showDocsPicker { showDocsPicker = false; return true }
        if showFeedbackSheet { showFeedbackSheet = false; return true }
        if showShortcuts { showShortcuts = false; return true }
        if showClaudeImport { showClaudeImport = false; return true }
        if showCLIReport { showCLIReport = false; return true }
        if client.hasActiveWork && !client.isStopping {
            client.stopWork()
            return true
        }
        let now = Date()
        if let armed = escapeArmedAt, now.timeIntervalSince(armed) < 0.8 {
            escapeArmedAt = nil
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Task { await client.rewind() }
            } else {
                recordPrompt(trimmed)
                draft = ""
                historyCursor = nil
                flash(copy.t("Prompt cleared", "已清空输入"))
            }
            return true
        }
        escapeArmedAt = now
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flash(copy.t("Press Esc again to clear", "再按一次 Esc 清空"))
        }
        return true
    }

    func handleComposerKey(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        guard destination == .build else { return false }
        if showSettings || showAbout || showResumePicker || showPromptHistory || showCLIReport
            || showDocsPicker || showFeedbackSheet || showShortcuts || showClaudeImport || showAddWorkflow || showAddMCP
            || showInAppLogin {
            return false
        }
        if showPalette || mentionQuery != nil || pendingBusySend != nil { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(.deviceIndependentFlagsMask)
        if !flags.isEmpty && flags != .numericPad && flags != .function && flags != [.numericPad, .function] {
            return false
        }
        switch keyCode {
        case 126:
            let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if empty || historyCursor != nil {
                recallHistory(delta: 1)
                return true
            }
        case 125:
            if historyCursor != nil {
                recallHistory(delta: -1)
                return true
            }
        default:
            break
        }
        return false
    }

    func submitFeedback() {
        let text = feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        showFeedbackSheet = false
        feedbackDraft = ""
        draft = text.isEmpty ? "/feedback" : "/feedback \(text)"
        sendDraft()
    }

    func openGuide(_ guide: LocalGuide) {
        showDocsPicker = false
        NSWorkspace.shared.open(guide.url)
    }

    func openDocsCommand(_ rest: String) {
        let query = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty || query == "how-to" || query == "howto" {
            docsPickerTutorial = false
            showDocsPicker = true
            return
        }
        if query == "web" {
            openDocs()
            return
        }
        let guides = LocalGuides.all()
        if let match = LocalGuides.match(query, in: guides) {
            NSWorkspace.shared.open(match.url)
        } else {
            docsPickerTutorial = false
            showDocsPicker = true
            flash(copy.t("No guide matching \(query)", "没有匹配 \(query) 的指南"))
        }
    }

    func presentContextReport() {
        refreshWorkspace()
        let used = workspace.contextUsed
        let window = workspace.contextWindow
        let free = max(window - used, 0)
        let todos = client.todos
        let done = todos.filter { $0.status == "completed" }.count
        cliReportTitle = "/context"
        cliReportBody = [
            "model: \(client.buildModel.rawValue)",
            "effort: \(client.effort.rawValue)",
            "mode: \(client.mode.rawValue)",
            "session: \(client.sessionID ?? "—")",
            "cwd: \(client.workingDirectory.path)",
            "auth: \(client.authPresence.isReady ? "signed in" : "unsigned")",
            "turns: \(client.items.filter { if case .user = $0 { return true }; return false }.count)",
            "messages: \(client.items.count)",
            "context: \(workspace.contextPercent)% (\(used)/\(window), free \(free))",
            "todos: \(done)/\(todos.count)",
            "tasks: \(client.tasks.filter(\.isRunning).count)/\(client.tasks.count)",
            "subagents: \(client.subagents.filter(\.isRunning).count)/\(client.subagents.count)",
            "compacted: \(client.compacted)",
            "loaded: \(client.liveWorkspaces.count) live",
            "skills: \(skills.count)",
            "mcp: \(mcpServers.count)",
            "branch: \(workspace.branch ?? "—")"
        ].joined(separator: "\n")
        showCLIReport = true
    }

    func presentInspectReport() {
        cliReportTitle = "/inspect"
        if client.events.isEmpty {
            cliReportBody = copy.t("No ACP events yet. Send a prompt first.", "还没有 ACP 事件。先发一条提示词。")
        } else {
            cliReportBody = client.events.suffix(40).map { event in
                "\(event.directionLabel) \(event.method)  \(event.preview)"
            }.joined(separator: "\n")
        }
        showCLIReport = true
    }

    func presentTerminalReport() {
        cliReportTitle = "/terminal-info"
        let rows = client.terminals
        var lines = [
            copy.t("This window hosts ACP terminals.", "这个窗口可以托管 ACP 终端。"),
            "capability: terminal + fs.readTextFile + fs.writeTextFile",
            "running: \(rows.filter(\.running).count)/\(rows.count)"
        ]
        if rows.isEmpty {
            lines.append(copy.t("No client terminals right now.", "现在没有客户端终端。"))
        } else {
            lines.append(contentsOf: rows.map { term in
                let state = term.running ? "running" : "exit \(term.exitCode.map(String.init) ?? "?")"
                return "\(term.id.prefix(8))  \(state)  \(term.command)"
            })
        }
        cliReportBody = lines.joined(separator: "\n")
        showCLIReport = true
    }

    func presentClaudeImport() {
        claudeImport = ClaudeImportSnapshot.discover()
        showClaudeImport = true
    }

    func importClaudeMCP() {
        let existing = Set(mcpServers.map { $0.name.lowercased() })
        var imported = 0
        var skipped = 0
        var failed: [String] = []
        for server in claudeImport.servers {
            if existing.contains(server.name.lowercased()) {
                skipped += 1
                continue
            }
            do {
                try mcpCatalog.add(
                    name: server.name,
                    transport: server.transport,
                    commandOrURL: server.commandOrURL,
                    args: server.args,
                    locator: locator
                )
                imported += 1
            } catch {
                failed.append("\(server.name): \(error.localizedDescription)")
            }
        }
        mcpServers = mcpCatalog.load(locator: locator, cwd: client.workingDirectory)
        extensions = ExtensionInventory.load(mcpNames: grokConfig.mcpNames)
        if failed.isEmpty {
            flash(copy.t("Imported \(imported) MCP, skipped \(skipped)", "已导入 \(imported) 个 MCP，跳过 \(skipped) 个"))
        } else {
            cliReportTitle = "/import-claude"
            cliReportBody = (["Imported \(imported), skipped \(skipped)", ""] + failed).joined(separator: "\n")
            showCLIReport = true
        }
    }

    func sendClaudeImportToAgent() {
        showClaudeImport = false
        draft = "/import-claude"
        sendDraft()
    }

    private func recordPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if SlashBuiltins.handles(trimmed) { return }
        var next = promptHistory.filter { $0 != trimmed }
        next.insert(trimmed, at: 0)
        promptHistory = Array(next.prefix(50))
        UserDefaults.standard.set(promptHistory, forKey: "promptHistory")
    }

    private func applyModelCommand(_ rest: String) {
        let parts = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first, !first.isEmpty else {
            insertSlashPrompt("/model")
            return
        }
        let lower = first.lowercased()
        if let match = BuildModel.allCases.first(where: {
            $0.rawValue == lower || $0.shortTitle.lowercased() == lower || $0.menuTitle.lowercased() == lower
        }) {
            client.buildModel = match
        } else if lower.contains("4.6") {
            client.buildModel = .grok46
        } else if lower.contains("4.5") {
            client.buildModel = .grok45
        } else if lower.contains("build") {
            client.buildModel = .grokBuild
        } else {
            flash(copy.t("Unknown model \(first)", "未知模型 \(first)"))
            return
        }
        if parts.count > 1 {
            applyEffortCommand(parts[1])
        }
        flash("\(client.buildModel.rawValue) · \(client.effort.rawValue)")
    }

    private func applyEffortCommand(_ rest: String) {
        let raw = rest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else {
            insertSlashPrompt("/effort")
            return
        }
        let mapped: EffortLevel?
        switch raw {
        case "low", "l", "低": mapped = .low
        case "medium", "med", "m", "中": mapped = .medium
        case "high", "h", "高": mapped = .high
        case "xhigh", "max", "xh", "极高": mapped = .xhigh
        default: mapped = EffortLevel(rawValue: raw)
        }
        guard let mapped else {
            flash(copy.t("Unknown effort \(rest)", "未知推理强度 \(rest)"))
            return
        }
        client.effort = mapped
        flash(mapped.title(chinese: language.resolved() == .chinese))
    }

    private func applyThemeCommand(_ rest: String) {
        let raw = rest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty {
            appearance = appearance == .dark ? .light : (appearance == .light ? .system : .dark)
        } else if raw.contains("dark") || raw.contains("深") {
            appearance = .dark
        } else if raw.contains("light") || raw.contains("浅") {
            appearance = .light
        } else {
            appearance = .system
        }
        flash(appearance.title)
    }

    private func applyMemoryCommand(_ rest: String) {
        let raw = rest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "on":
            try? configStore.set(section: "memory", key: "enabled", bool: true)
            grokConfig = configStore.load()
            flash(copy.t("Memory on", "记忆已开"))
        case "off":
            try? configStore.set(section: "memory", key: "enabled", bool: false)
            grokConfig = configStore.load()
            flash(copy.t("Memory off", "记忆已关"))
        case "clear":
            runGrokCLI(arguments: ["memory", "clear", "--yes", "--workspace"], title: "/memory clear")
        default:
            refreshMemoryFiles()
            showMemory = true
        }
    }

    private func copyReply(argument: String) {
        let replies: [String] = client.items.compactMap {
            if case .assistant(_, let body, _) = $0 { return body }
            return nil
        }
        if argument.isEmpty {
            copyLatestReply()
            return
        }
        if let index = Int(argument), index > 0, replies.count >= index {
            copyText(replies[replies.count - index])
            flash(copy.copied)
            return
        }
        let url = (argument as NSString).expandingTildeInPath
        if let text = replies.last {
            try? text.write(toFile: url, atomically: true, encoding: .utf8)
            flash(url)
        }
    }

    private func openLocalGuide() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/docs/user-guide/01-getting-started.md")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            openDocs()
        }
    }

    func runGrokCLI(arguments: [String], title: String) {
        let cwd = client.workingDirectory
        flash(copy.t("Running \(title)…", "正在运行 \(title)…"))
        Task {
            let output = await Task.detached { [locator] in
                guard let binary = locator.locate() else { return "grok not found" }
                let process = Process()
                process.executableURL = binary
                process.arguments = arguments
                process.currentDirectoryURL = cwd
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    return error.localizedDescription
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            }.value
            cliReportTitle = title
            cliReportBody = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no output)" : output
            showCLIReport = true
        }
    }

    func retryLocate() {
        firstRunReason = bootstrapReason()
        if firstRunReason == nil {
            startNewSession()
        }
    }

    func login() {
        if locator.locate() == nil {
            openWebChat()
            return
        }
        showInAppLogin = true
        inAppLoginURL = nil
        Task {
            do {
                let challenge = try await client.beginLogin()
                inAppLoginURL = challenge.url ?? GrokWebSession.homeURL
                startLoginPoll()
            } catch {
                fallbackLogin()
            }
        }
    }

    func dismissInAppLogin() {
        showInAppLogin = false
        loginPollTask?.cancel()
        loginPollTask = nil
    }

    func openLoginInSystemBrowser() {
        if let url = inAppLoginURL ?? client.authChallenge?.url {
            NSWorkspace.shared.open(url)
        } else {
            fallbackLogin()
        }
    }

    func handleLoginCallback(_ url: URL) {
        Task {
            _ = try? await URLSession.shared.data(from: url)
            if let code = GrokWebSession.callbackCode(in: url) {
                loginCode = code
                do {
                    try await client.submitLoginCode(code)
                } catch {
                    // Local grok listener may have already consumed the callback.
                }
            }
            await finishLoginSuccess()
        }
    }

    func submitLoginCode() {
        let code = loginCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        Task {
            do {
                try await client.submitLoginCode(code)
                loginCode = ""
                await finishLoginSuccess()
            } catch {
                fallbackLogin()
            }
        }
    }

    func logout() {
        if let grok = locator.locate() {
            let process = Process()
            process.executableURL = grok
            process.arguments = ["logout"]
            try? process.run()
            process.waitUntilExit()
        }
        client.refreshAuth()
        account = AccountProfile()
        accountUsage = AccountUsage()
        webChatSignedIn = false
        firstRunReason = bootstrapReason()
        Task { await GrokWebSession.clear() }
    }

    private func startLoginPoll() {
        loginPollTask?.cancel()
        loginPollTask = Task { [weak self] in
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.client.refreshAuth()
                if self.client.authPresence.isReady {
                    await self.finishLoginSuccess()
                    return
                }
            }
        }
    }

    private func finishLoginSuccess() async {
        loginPollTask?.cancel()
        loginPollTask = nil
        client.refreshAuth()
        account = AccountProfile.load()
        firstRunReason = bootstrapReason()
        refreshAccountUsage()
        GrokWebChatHost.shared.reloadHome()
        await refreshWebChatAuth()
        if client.authPresence.isReady || webChatSignedIn {
            showInAppLogin = false
        }
    }

    func exportDiagnostics() {
        let text = DiagnosticExport.make(
            version: "0.1.19",
            grokVersion: client.grokVersion,
            state: String(describing: client.state),
            lastError: client.lastError,
            sessionID: client.sessionID,
            cwd: client.workingDirectory.path,
            stderr: client.stderrLines,
            events: client.events.map(\.line)
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "grok-desktop-diagnostic.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func fallbackLogin() {
        if inAppLoginURL == nil {
            inAppLoginURL = GrokWebSession.homeURL
        }
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
        showAttachMenu = false
        mentionQuery = nil
        let urls = Self.clipboardAttachmentURLs()
        guard !urls.isEmpty else {
            flash(copy.t("Clipboard has no image.", "剪贴板里没有图片。"))
            return
        }
        suppressSuggest = true
        for url in urls {
            insertMention(url)
        }
        suppressSuggest = true
    }

    static func clipboardAttachmentURLs(board: NSPasteboard = .general) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL) {
            if seen.insert(url.path).inserted {
                urls.append(url)
            }
        }

        let fileURLs = (board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        for url in fileURLs where PromptMedia.isImageURL(url) {
            add(url)
        }
        if !urls.isEmpty { return urls }

        if let image = NSImage(pasteboard: board), let url = writePasteImage(image) {
            add(url)
            return urls
        }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        for type in types {
            if let data = board.data(forType: type),
               let image = NSImage(data: data),
               let url = writePasteImage(image) {
                add(url)
                break
            }
        }
        return urls
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
