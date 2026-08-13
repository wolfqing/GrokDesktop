import Foundation
import GrokDesktopCore
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> SemanticLanguage {
        switch self {
        case .english: return .english
        case .chinese: return .chinese
        case .system:
            let first = preferredLanguages.first?.lowercased() ?? "en"
            return first.hasPrefix("zh") ? .chinese : .english
        }
    }
}

enum SemanticLanguage: String {
    case english
    case chinese
}

struct L10n {
    var language: SemanticLanguage

    func t(_ en: String, _ zh: String) -> String {
        language == .chinese ? zh : en
    }

    var search: String { t("Search", "搜索") }
    var newChat: String { t("New Chat", "新对话") }
    var imagine: String { t("Imagine", "Imagine") }
    var liveAgents: String { t("Live agents", "进行中") }
    var automations: String { t("Workflows", "工作流") }
    var skillsAndConnectors: String { t("Skills and Connectors", "技能与连接器") }
    var projects: String { t("Projects", "项目") }
    var history: String { t("History", "历史") }
    var addProject: String { t("Add project", "添加项目") }
    var noProjects: String { t("No projects yet", "还没有项目") }
    var collapseSidebar: String { t("Collapse sidebar", "收起侧栏") }
    var settings: String { t("Settings", "设置") }
    var done: String { t("Done", "完成") }
    var whatsOnYourMind: String { t("What's on your mind?", "有什么想法？") }
    var privateChat: String { t("Private", "私密") }
    var privateBanner: String {
        t(
            "This chat won't appear in your history and will not be used to train models.",
            "此对话不会出现在历史记录中，也不会用于训练模型。"
        )
    }
    var think: String { t("Thinking", "思考") }
    var newAutomation: String { t("New Automation", "新建自动化") }
    var suggested: String { t("Suggested", "推荐") }
    var add: String { t("Add", "添加") }
    var newSkill: String { t("New Skill", "新建技能") }
    var skills: String { t("Skills", "技能") }
    var connectors: String { t("Connectors", "连接器") }
    var personal: String { t("Personal", "个人") }
    var searchEllipsis: String { t("Search...", "搜索…") }
    var createProject: String { t("Create Project", "创建项目") }
    var projectName: String { t("Project Name", "项目名称") }
    var addFiles: String { t("Add Files", "添加文件") }
    var create: String { t("Create", "创建") }
    var chooseFolder: String { t("Choose Folder", "选择文件夹") }
    var account: String { t("Account", "账号") }
    var appearance: String { t("Appearance", "外观") }
    var behavior: String { t("Behavior", "行为") }
    var customize: String { t("Customize", "自定义") }
    var billing: String { t("Billing", "账单") }
    var usage: String { t("Usage", "用量") }
    var dataControls: String { t("Data Controls", "数据控制") }
    var general: String { t("General", "通用") }
    var grok: String { t("Grok", "Grok") }
    var payments: String { t("Payments", "付款") }
    var dataAndInformation: String { t("Data & Information", "数据与信息") }
    var manage: String { t("Manage", "管理") }
    var change: String { t("Change", "更改") }
    var languageTitle: String { t("Language", "语言") }
    var systemLanguage: String { t("System", "跟随系统") }
    var english: String { t("English", "English") }
    var chinese: String { t("简体中文", "简体中文") }
    var theme: String { t("Theme", "主题") }
    var light: String { t("Light", "浅色") }
    var dark: String { t("Dark", "深色") }
    var system: String { t("System", "系统") }
    var wrapCode: String { t("Wrap Long Lines For Code Blocks By Default", "代码块默认自动换行") }
    var enableAutoScroll: String { t("Enable Auto Scroll", "启用自动滚动") }
    var notifyThinking: String { t("Notify When Grok Finishes Thinking", "Grok 完成思考时通知") }
    var requireCmdEnter: String { t("Require Cmd+Enter To Submit", "使用 Cmd+Enter 发送") }
    var requireCmdEnterHelp: String {
        t(
            "When enabled, press Cmd+Enter (or Ctrl+Enter) to submit. Enter will add a new line.",
            "开启后需按 Cmd+Enter（或 Ctrl+Enter）发送，Enter 用于换行。"
        )
    }
    var richTextEditor: String { t("Enable Rich Text Editor", "启用富文本编辑器") }
    var richTextHelp: String { t("Enable code blocks and lists in the query bar", "在输入栏中支持代码块和列表") }
    var customizeResponse: String { t("Customize Grok's Response", "自定义 Grok 的回复风格") }
    var agentLibrary: String { t("Agent Library", "Agent 库") }
    var createAgent: String { t("+ Create", "+ 创建") }
    var custom: String { t("Custom", "自定义") }
    var concise: String { t("Concise", "简洁") }
    var formal: String { t("Formal", "正式") }
    var tutor: String { t("Tutor", "导师") }
    var comprehensive: String { t("Comprehensive", "详尽") }
    var currentPlan: String { t("Current Plan", "当前方案") }
    var extraCredits: String { t("Extra Usage Credits", "额外用量额度") }
    var invoices: String { t("Invoices", "发票") }
    var switchPlan: String { t("Switch Plan", "更换方案") }
    var buyMore: String { t("Buy More", "加购") }
    var viewUsage: String { t("View Usage", "查看用量") }
    var weeklyLimit: String { t("Weekly SuperGrok Limit", "每周 SuperGrok 额度") }
    var used: String { t("used", "已用") }
    var loginGrok: String { t("Sign in with grok login", "使用 grok login 登录") }
    var notSignedIn: String { t("Not signed in", "未登录") }
    var noConnectors: String { t("No connectors yet. Add an MCP server in ~/.grok/config.toml.", "还没有连接器。在 ~/.grok/config.toml 中添加 MCP 服务器。") }
    var runAutomation: String { t("Run", "运行") }
    var uploadFile: String { t("Upload a file", "上传文件") }
    var recent: String { t("Recent", "最近") }
    var project: String { t("Project", "项目") }
    var addConnector: String { t("Add connector", "添加连接器") }
    var environment: String { t("Environment", "环境信息") }
    var changes: String { t("Changes", "变更") }
    var local: String { t("Local", "本地") }
    var commitOrPush: String { t("Commit or push", "提交或推送") }
    var compareBranch: String { t("Compare branch", "比较分支") }
    var subagents: String { t("Subagents", "子智能体") }
    var running: String { t("running", "运行中") }
    var completed: String { t("done", "完成") }
    var sources: String { t("Sources", "来源") }
    var webSearch: String { t("Web search", "网页搜索") }
    var viewAll: String { t("View all", "查看全部") }
    var mainAgent: String { t("Main Agent", "主 Agent") }
    var askAnything: String { t("Ask anything, @ to mention, / for actions", "随便问，@ 引用文件，/ 执行命令") }
    var helpApprove: String { t("Help me approve", "帮我批准") }
    var artifacts: String { t("Artifacts", "产物") }
    var files: String { t("Files", "文件") }
    var backgroundTasks: String { t("Background tasks", "后台任务") }
    var tasks: String { t("Tasks", "任务") }
    var noTasks: String { t("No tasks yet.", "还没有任务。") }
    var inspector: String { t("Inspector", "右边栏") }
    var weeklyPlanLimit: String { t("Weekly limit", "每周额度") }
    var monthlyPlanLimit: String { t("Monthly limit", "每月额度") }
    var openGrokUsage: String { t("Manage on grok.com", "在 grok.com 管理") }
    var openAPIUsage: String { t("Open API console usage", "打开 API 控制台用量") }
    var usageForAccount: String { t("Usage for", "当前账号") }
    var sendNow: String { t("Send now", "立即发送") }
    var editPrompt: String { t("Edit", "编辑") }
    var cancelPrompt: String { t("Cancel", "取消") }
    var busySendTitle: String { t("Agent is still working", "任务还在进行") }
    var busySendDetail: String {
        t(
            "Send now cancels the current turn and runs this next. Edit keeps the text. Cancel drops it.",
            "立即发送会取消当前回合并马上发这条。编辑回到输入框。取消则丢弃。"
        )
    }
    var nextReset: String { t("Next reset", "下次重置") }
    var refreshUsage: String { t("Refresh", "刷新") }
    var usageUnavailable: String { t("Couldn't load account usage", "无法同步账号用量") }
    var sessionContext: String { t("This session context", "当前会话上下文") }
    var grokBuildUsage: String { t("Grok Build usage", "Grok Build 用量") }

    func planTitle(_ plan: SubscriptionPlan) -> String {
        plan.wordmark
    }
}

private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10n(language: .english)
}

extension EnvironmentValues {
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}
