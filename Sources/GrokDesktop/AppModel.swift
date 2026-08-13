import AppKit
import Foundation
import GrokDesktopCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var client: ACPClient
    @Published var sessions: [SessionRecord] = []
    @Published var search = ""
    @Published var draft = ""
    @Published var showSettings = false
    @Published var showPalette = false
    @Published var showInspector = false
    @Published var settingsSection: SettingsSection = .appearance
    @Published var firstRunReason: FirstRunReason?

    let sessionIndex: SessionIndex
    let locator: GrokBinaryLocator

    init(
        locator: GrokBinaryLocator = GrokBinaryLocator(),
        sessionIndex: SessionIndex = SessionIndex()
    ) {
        self.locator = locator
        self.sessionIndex = sessionIndex
        self.client = ACPClient(locator: locator)
        refreshSessions()
        if locator.locate() == nil {
            firstRunReason = .missingCLI
        }
    }

    var filteredSessions: [SessionRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.cwd.localizedCaseInsensitiveContains(query)
        }
    }

    var groupedSessions: [(key: String, values: [SessionRecord])] {
        let groups = Dictionary(grouping: filteredSessions, by: \.cwdName)
        return groups.keys.sorted().map { key in
            (key, groups[key]!.sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    func refreshSessions() {
        sessions = sessionIndex.load()
    }

    func startNewSession() {
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
        panel.prompt = "选择项目"
        panel.directoryURL = client.workingDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        client.workingDirectory = url
        startNewSession()
    }

    func open(_ record: SessionRecord) {
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
        Task {
            do {
                try await client.send(text: text)
                refreshSessions()
            } catch {
                present(error)
            }
        }
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
        case "/home", "/welcome":
            client.resetConversation()
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
    }

    private func present(_ error: Error) {
        if let acp = error as? ACPError, acp == .grokNotFound {
            firstRunReason = .missingCLI
        } else {
            client.lastError.map { _ in }
            firstRunReason = .agent(error.localizedDescription)
        }
    }
}

enum FirstRunReason: Equatable {
    case missingCLI
    case agent(String)
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case language
    case feedback
    case account
    case behavior
    case session
    case agent
    case extensions
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "外观"
        case .language: return "语言"
        case .feedback: return "反馈"
        case .account: return "账号"
        case .behavior: return "行为"
        case .session: return "会话"
        case .agent: return "Agent"
        case .extensions: return "扩展"
        case .advanced: return "高级"
        }
    }
}
