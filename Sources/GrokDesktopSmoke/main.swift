import Foundation
import GrokDesktopCore

func fail(_ message: String) -> Never {
    fputs("FAIL \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

let missing = GrokBinaryLocator(
    extraSearchPaths: [],
    pathEnvironment: "/empty",
    fileExists: { _ in false }
)
expect(missing.locate() == nil, "missing grok should be nil")

let fake = URL(fileURLWithPath: "/tmp/fake-grok-bin/grok")
let found = GrokBinaryLocator(
    extraSearchPaths: [fake],
    pathEnvironment: "/does/not/exist",
    fileExists: { $0 == fake }
)
expect(found.locate() == fake, "should find extra search path")

let chunk = """
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}}}
"""
guard let envelope = try? JSONRPCEnvelope.decode(Data(chunk.utf8)) else {
    fail("decode session/update")
}
let update = SessionUpdate.parse(params: envelope.params)
expect(update.kind == .agentMessageChunk, "kind")
expect(update.text == "Hello", "text")
expect(update.sessionId == "s1", "sessionId")

let permissionJSON = """
{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{"sessionId":"s1","options":[{"optionId":"proceed_once","name":"Allow","kind":"allow_once"},{"optionId":"cancel","name":"Reject","kind":"reject_once"}],"toolCall":{"title":"run tests"}}}
"""
guard let permissionEnvelope = try? JSONRPCEnvelope.decode(Data(permissionJSON.utf8)),
      let id = permissionEnvelope.id
else {
    fail("decode permission")
}
let request = PermissionRequest.parse(id: id, params: permissionEnvelope.params)
expect(request.title == "run tests", "permission title")
expect(request.options.count == 2, "permission options")

let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Tests/GrokDesktopTests/Fixtures/summary.json")
expect(FileManager.default.fileExists(atPath: fixture.path), "fixture exists at \(fixture.path)")
let record = SessionIndex().decode(summaryURL: fixture)
expect(record?.id == "019ffa28-09d5-7f90-8d39-bbe1edba511b", "session id")
expect(record?.title == "macOS GUI Version from Grok Build", "title")
expect(record?.cwdName == "GrokDesktop", "cwd name")

let updates = fixture.deletingLastPathComponent().appendingPathComponent("updates.jsonl")
expect(FileManager.default.fileExists(atPath: updates.path), "updates fixture")
let transcript = TranscriptLoader.load(sessionDirectory: updates.deletingLastPathComponent())
expect(transcript.items.contains(where: {
    if case .user(_, let text) = $0 { return text.contains("Hello") }
    return false
}), "transcript user")
expect(transcript.items.contains(where: {
    if case .assistant(_, let text, _) = $0 { return text.contains("Hi there") }
    return false
}), "transcript assistant")
expect(transcript.planEntries.first?.content == "Step one", "plan entries")
expect(transcript.recap.contains("App.swift"), "transcript recap from fold")
expect(transcript.compacted, "transcript compacted from fold")
expect(transcript.subagents.count == 1, "transcript subagent from fold")

let planUpdate = SessionUpdate.parse(params: [
    "update": [
        "sessionUpdate": "plan",
        "entries": [["content": "Do the thing", "status": "in_progress", "priority": "high"]]
    ]
])
expect(planUpdate.kind == .plan, "plan kind")
expect(planUpdate.planEntries.count == 1, "plan parse")

var toolItems: [ConversationItem] = []
var toolPlan: [PlanEntry] = []
var toolDates: [String: Date] = [:]
var toolImages: [String: [URL]] = [:]
var toolTodos: [AgentTodo] = []
var toolTasks: [AgentTask] = []
var toolAssistant: String?
var toolThought: String?
TranscriptLoader.apply(
    update: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "tool_call",
            "toolCallId": "t-todo",
            "title": "todo_write",
            "rawInput": ["todos": [["id": "1", "content": "One", "status": "in_progress"]]]
        ]
    ] as [String: Any]),
    items: &toolItems,
    planEntries: &toolPlan,
    assistantID: &toolAssistant,
    thoughtID: &toolThought,
    itemDates: &toolDates,
    itemImages: &toolImages,
    todos: &toolTodos,
    tasks: &toolTasks
)
TranscriptLoader.apply(
    update: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "t-todo",
            "title": "Updating plan",
            "rawInput": ["merge": true, "todos": [["id": "1", "status": "completed"]]]
        ]
    ] as [String: Any]),
    items: &toolItems,
    planEntries: &toolPlan,
    assistantID: &toolAssistant,
    thoughtID: &toolThought,
    itemDates: &toolDates,
    itemImages: &toolImages,
    todos: &toolTodos,
    tasks: &toolTasks
)
if case .tool(_, let liveTitle, let liveStatus, _) = toolItems[0] {
    expect(liveTitle == "Updating plan", "todo title updates")
    expect(liveStatus == "running", "nil status does not reset tool")
} else {
    fail("expected tool item")
}
expect(toolTodos.first?.status == "completed", "todo status follows merge")
TranscriptLoader.apply(
    update: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "t-todo",
            "status": "completed",
            "rawOutput": ["type": "Todo", "TodosUpdated": [
                "todos": [["content": "One", "status": "completed"]],
                "state": ["todos": ["1": ["content": "One", "status": "completed"]]]
            ]]
        ]
    ] as [String: Any]),
    items: &toolItems,
    planEntries: &toolPlan,
    assistantID: &toolAssistant,
    thoughtID: &toolThought,
    itemDates: &toolDates,
    itemImages: &toolImages,
    todos: &toolTodos,
    tasks: &toolTasks
)
if case .tool(_, _, let doneStatus, _) = toolItems[0] {
    expect(doneStatus == "completed", "tool completed status kept")
} else {
    fail("expected completed tool")
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("grok-config-test.toml")
try? "[models]\ndefault = \"grok-4.6\"\n".write(to: tmp, atomically: true, encoding: .utf8)
let loaded = ConfigStore(fileURL: tmp).load()
expect(loaded.defaultModel == "grok-4.6", "config default model")
try? ConfigStore(fileURL: tmp).set(section: "ui", key: "permission_mode", value: "ask")
let reloaded = ConfigStore(fileURL: tmp).load()
expect(reloaded.permissionMode == "ask", "config write")

let mapped = ModelTier.auto.applied(config: loaded)
expect(mapped.model == .grok46, "auto maps default model")

expect(AuthPresence.probe(environment: ["XAI_API_KEY": "xai-test"]).isReady, "api key counts as signed in")
expect(AuthPresence.probe(authURL: URL(fileURLWithPath: "/tmp/missing-auth.json"), environment: [:]) == .signedOut, "missing auth is signed out")

let ws = SessionWorkspace(id: "abc", cwd: URL(fileURLWithPath: "/tmp"), title: "t")
expect(ws.isLive == false, "empty workspace not live")
ws.isTurnRunning = true
expect(ws.isLive, "running workspace is live")
ws.todos = [AgentTodo(id: "1", content: "One", status: "in_progress")]
ws.markWorkStopped()
expect(ws.stopRequested, "stop requested")
expect(ws.isTurnRunning == false, "stop clears turn")
expect(ws.todos[0].status == "cancelled", "stop cancels todos")
expect(ws.isLive == false, "stopped workspace is not live")

expect(DiagnosticExport.redact("token: xai-SECRET123 and ok") .contains("[redacted]"), "redact api key")
expect(DiagnosticExport.redact("hello").contains("hello"), "keep plain text")

let caps = AgentCapabilities.parse([
    "agentCapabilities": ["loadSession": true, "terminal": true],
    "authMethods": [["id": "browser"]],
    "_meta": ["methods": ["x.ai/git/status"]]
] as [String: Any])
expect(caps.loadSession, "loadSession cap")
expect(caps.authMethods.contains("browser"), "auth methods")
expect(caps.supports("x.ai/git/status"), "extension methods")

let mcpTOML = """
[mcp_servers.github]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
enabled = true
"""
let parsedMCP = MCPCatalog.parseTOML(mcpTOML)
expect(parsedMCP.count == 1, "mcp parse count")
expect(parsedMCP[0].name == "github", "mcp name")
expect(parsedMCP[0].args.contains("-y"), "mcp args")

let rhai = """
let meta = #{
    name: "review-changes",
    description: "Review a diff",
};
"""
let parsedWF = WorkflowCatalog.parse(rhai, url: URL(fileURLWithPath: "/tmp/review-changes.rhai"), scope: "user")
expect(parsedWF?.name == "review-changes", "workflow name")
expect(parsedWF?.detail == "Review a diff", "workflow detail")

let billing = AccountUsageService.parseBilling([
    "config": [
        "creditUsagePercent": 3.0,
        "currentPeriod": [
            "type": "USAGE_PERIOD_TYPE_WEEKLY",
            "start": "2026-08-07T09:33:03.170256+00:00",
            "end": "2026-08-14T09:33:03.170256+00:00"
        ],
        "prepaidBalance": ["val": 1.5],
        "onDemandCap": ["val": 0],
        "onDemandUsed": ["val": 0],
        "productUsage": [
            ["product": "GrokBuild", "usagePercent": 3.0],
            ["product": "GrokChat"]
        ]
    ]
] as [String: Any])
expect(billing.creditPercent == 3, "billing percent")
expect(billing.periodKind == .weekly, "billing period")
expect(billing.prepaidDollars == 1.5, "prepaid wrapper")
expect(billing.products.count == 2, "product rows")
expect(billing.products[0].name == "Grok Build", "build product name")
expect(billing.displayPercent == 3, "display prefers Grok Build")
expect(billing.periodEnd != nil, "period end parsed")

let remoteProfile = AccountUsageService.parseProfile([
    "email": "user@example.com",
    "firstName": "Ada",
    "lastName": "Lovelace",
    "userId": "u1",
    "teamId": "t1",
    "hasGrokCodeAccess": true
] as [String: Any])
expect(remoteProfile.email == "user@example.com", "usage profile email")
expect(remoteProfile.plan == .superGrok, "usage profile plan")

let envBase = AccountUsageService.proxyBase(
    configURL: URL(fileURLWithPath: "/tmp/missing-grok-config.toml"),
    environment: ["GROK_CLI_CHAT_PROXY_BASE_URL": "https://proxy.example/v1/"]
)
expect(envBase == "https://proxy.example/v1", "proxy base strips slash")

let stamped = SessionUpdate.parse(
    params: [
        "sessionId": "s1",
        "_meta": ["agentTimestampMs": 1_786_622_249_035],
        "update": ["sessionUpdate": "user_message_chunk", "content": ["type": "text", "text": "Hi"]]
    ] as [String: Any]
)
expect(stamped.timestamp != nil, "prompt timestamp from agentTimestampMs")
let stampedText = PromptTimestamp.format(stamped.timestamp!)
expect(stampedText.hasPrefix("2026-"), "prompt date year \(stampedText)")
expect(stampedText.split(separator: " ").count == 2, "prompt date and time \(stampedText)")

var todos: [AgentTodo] = []
PromptTimestamp.applyTodos(
    from: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "tool_call",
            "title": "todo_write",
            "rawInput": [
                "merge": false,
                "todos": [
                    ["id": "1", "content": "One", "status": "in_progress"],
                    ["id": "2", "content": "Two", "status": "pending"]
                ]
            ]
        ]
    ] as [String: Any]),
    into: &todos
)
expect(todos.count == 2, "todo parse count")
PromptTimestamp.applyTodos(
    from: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "tool_call_update",
            "title": "todo_write",
            "rawInput": [
                "merge": true,
                "todos": [["id": "1", "status": "completed"]]
            ]
        ]
    ] as [String: Any]),
    into: &todos
)
expect(todos[0].status == "completed", "todo merge status")
expect(todos[0].content == "One", "todo merge keeps content")
expect(PromptTimestamp.progress(for: todos).done == 1, "todo progress done")
expect(PromptTimestamp.progress(for: todos).total == 2, "todo progress total")

var tasks: [AgentTask] = []
PromptTimestamp.applyTask(
    from: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "task_backgrounded",
            "task_id": "t1",
            "command": "swift build",
            "description": "Compile"
        ]
    ] as [String: Any]),
    into: &tasks
)
expect(tasks.count == 1, "task backgrounded")
expect(tasks[0].isRunning, "task running")
PromptTimestamp.applyTask(
    from: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "task_completed",
            "task_snapshot": [
                "task_id": "t1",
                "command": "swift build",
                "start_time": ["secs_since_epoch": 100, "nanos_since_epoch": 0],
                "end_time": ["secs_since_epoch": 118, "nanos_since_epoch": 0]
            ]
        ]
    ] as [String: Any]),
    into: &tasks
)
expect(tasks[0].status == "completed", "task completed")
expect(abs((tasks[0].elapsed ?? 0) - 18) < 0.01, "task elapsed")

let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("grok-media-test.png")
try? Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: imageURL)
let mentioned = PromptMedia.imageURLs(in: "@\(imageURL.path) look at this")
expect(mentioned.count == 1, "extract @image path")
expect(mentioned[0].path == imageURL.path, "extract keeps image path")
expect(PromptMedia.displayText("@\(imageURL.path) look at this") == "look at this", "strip @image from display")
expect(PromptMedia.displayText("[Image #1] look at this [Image #2]") == "look at this", "strip image tokens")
expect(PromptMedia.samePrompt("@\(imageURL.path) look at this", "[Image #1] look at this"), "same prompt after image tokens")
let imageUpdate = SessionUpdate.parse(params: [
    "update": [
        "sessionUpdate": "user_message_chunk",
        "content": [
            "type": "image",
            "mimeType": "image/png",
            "uri": imageURL.absoluteString,
            "_meta": ["xai.dev/imageDisplayNumber": 1]
        ]
    ]
] as [String: Any])
expect(imageUpdate.imageURLs.count == 1, "parse image uri")
expect(imageUpdate.imageDisplayNumber == 1, "parse image display number")
expect(imageUpdate.text.isEmpty, "image chunk has no text")
var mediaItems: [ConversationItem] = []
var mediaPlan: [PlanEntry] = []
var mediaDates: [String: Date] = [:]
var mediaImages: [String: [URL]] = [:]
var mediaTodos: [AgentTodo] = []
var mediaTasks: [AgentTask] = []
var mediaAssistant: String?
var mediaThought: String?
TranscriptLoader.apply(
    update: SessionUpdate.parse(params: [
        "update": [
            "sessionUpdate": "user_message_chunk",
            "content": ["type": "text", "text": "[Image #1] look at this"]
        ]
    ] as [String: Any]),
    items: &mediaItems,
    planEntries: &mediaPlan,
    assistantID: &mediaAssistant,
    thoughtID: &mediaThought,
    itemDates: &mediaDates,
    itemImages: &mediaImages,
    todos: &mediaTodos,
    tasks: &mediaTasks
)
TranscriptLoader.apply(
    update: imageUpdate,
    items: &mediaItems,
    planEntries: &mediaPlan,
    assistantID: &mediaAssistant,
    thoughtID: &mediaThought,
    itemDates: &mediaDates,
    itemImages: &mediaImages,
    todos: &mediaTodos,
    tasks: &mediaTasks
)
expect(mediaItems.count == 1, "image chunk stays on same user turn")
if case .user(let mediaID, let mediaText) = mediaItems[0] {
    expect(mediaText == "[Image #1] look at this", "image chunk does not append empty text")
    expect(mediaImages[mediaID]?.count == 1, "image attached to user prompt")
    expect(PromptMedia.displayText(mediaText) == "look at this", "history display hides image token")
} else {
    fail("expected user item with image")
}
let blocks = PromptMedia.promptBlocks(from: "@\(imageURL.path) look at this")
expect(blocks.count == 2, "prompt sends text + image")
expect(blocks[0]["type"] as? String == "text", "first block is text")
expect((blocks[0]["text"] as? String)?.contains("[Image #1]") == true, "text uses image token")
expect(blocks[1]["type"] as? String == "image", "second block is image")

let markdown = ChatMarkdown.blocks(in: "Hello **world**\n```swift\nlet x = 1\n```\nDone")
expect(markdown.count == 3, "markdown splits prose and fence")
if case .code(let language, let code) = markdown[1] {
    expect(language == "swift", "code language")
    expect(code.contains("let x"), "code body")
} else {
    fail("expected code block")
}
expect(ToolVoice.headline("read_file AppModel.swift", chinese: true).contains("读了"), "tool read headline")
expect(ToolVoice.statusLabel("running", chinese: true) == "进行中", "tool running label")
expect(AgentMode.normal.title(chinese: true) == "询问", "mode ask title")

let storyItems: [ConversationItem] = [
    .user(id: "u1", text: "把一轮工作收成可读叙事"),
    .tool(id: "t1", title: "search_replace ChatView.swift", status: "completed", detail: ""),
    .tool(id: "t2", title: "read_file AppModel.swift", status: "running", detail: "")
]
let story = TurnNarrative.story(
    items: storyItems,
    todos: [AgentTodo(id: "1", content: "改对话区", status: "in_progress")],
    hunks: [FileHunk(id: "h1", path: "/tmp/ChatView.swift", added: 3, removed: 1)],
    chinese: true,
    running: true,
    stopping: false
)
expect(story?.goal.contains("可读叙事") == true, "turn goal from last user")
expect(story?.step == "改对话区", "turn step from active todo")
expect(story?.files.contains("ChatView.swift") == true, "turn files include hunk")
expect(TurnNarrative.fileNames(in: "edited Sources/GrokDesktop/Views/ChatView.swift").contains("ChatView.swift"), "extract file name")

let exists: (String) -> Bool = {
    [
        "/Users/demo/app/Sources/GrokDesktop/AppModel.swift",
        "/Users/demo/app/README.md",
        "/tmp/photo.png"
    ].contains($0)
}
let base = URL(fileURLWithPath: "/Users/demo/app")
let webLinks = ChatLinkDetector.detect(
    in: "See https://docs.x.ai/build/overview and www.example.com/path.",
    baseDirectory: base,
    fileExists: exists
)
expect(webLinks.contains(where: { $0.url.host == "docs.x.ai" && $0.kind == .web }), "detect https link")
expect(webLinks.contains(where: { $0.url.host == "www.example.com" && $0.kind == .web }), "detect www link")

let pathLinks = ChatLinkDetector.detect(
    in: "edited Sources/GrokDesktop/AppModel.swift and README.md plus @/tmp/photo.png",
    baseDirectory: base,
    fileExists: exists
)
expect(pathLinks.contains(where: { $0.url.path.hasSuffix("AppModel.swift") && $0.kind == .file }), "detect relative file")
expect(pathLinks.contains(where: { $0.url.path.hasSuffix("README.md") }), "detect existing basename")
expect(pathLinks.contains(where: { $0.url.path == "/tmp/photo.png" }), "detect @ absolute file")

let skipLinks = ChatLinkDetector.detect(
    in: "run /usage then bump 0.1.2 and e.g. wait",
    baseDirectory: base,
    fileExists: { _ in false }
)
expect(!skipLinks.contains(where: { $0.url.path.contains("usage") }), "slash commands are not files")
expect(skipLinks.isEmpty, "versions and latin abbreviations stay plain")

expect(ChatLinkDetector.resolve("mailto:hi@x.ai")?.kind == .mail, "mailto is mail")
expect(ChatLinkDetector.resolve("hi@x.ai")?.kind == .mail, "bare email is mail")
expect(ChatLinkDetector.resolve("/usage", fileExists: { _ in false }) == nil, "bare slash command is not a file")

let now = Date()
expect(TranscriptLoader.displayUserText("<user_query>fix the bug</user_query>") == "fix the bug", "extract user_query")
expect(TranscriptLoader.displayUserText("<system-reminder>hide</system-reminder>\nhello").contains("hello"), "strip reminder")
expect(TranscriptLoader.parseDiffFiles("diff --git a/App.swift b/App.swift\n+ok") == ["App.swift"], "parse diff files")

let imageDir = FileManager.default.temporaryDirectory.appendingPathComponent("gd-images-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: imageDir.appendingPathComponent("images"), withIntermediateDirectories: true)
let diskImage = imageDir.appendingPathComponent("images/image-1.png")
try! Data([0x89]).write(to: diskImage)
var attached: [String: [URL]] = [:]
TranscriptLoader.attachDiskImages(
    sessionDirectory: imageDir,
    items: [.user(id: "u1", text: "[Image #1] look")],
    itemImages: &attached
)
expect(attached["u1"]?.first?.lastPathComponent == "image-1.png", "attach disk image to user turn")

expect(RelativeTime.format(now.addingTimeInterval(-10), now: now, chinese: true) == "刚刚", "relative just now")
expect(RelativeTime.format(now.addingTimeInterval(-180), now: now, chinese: false) == "3m", "relative minutes")
expect(RelativeTime.meta(
    SessionRecord(
        id: "s",
        cwd: "/tmp/Demo",
        title: "Demo",
        updatedAt: now.addingTimeInterval(-120),
        model: nil,
        directory: URL(fileURLWithPath: "/tmp")
    ),
    now: now,
    chinese: true
).contains("Demo"), "session meta includes folder")

expect(SlashBuiltins.handles("/model grok-4.6"), "model with args is builtin")
expect(SlashBuiltins.handles("/effort high"), "effort is builtin")
expect(SlashBuiltins.handles("/history"), "history is builtin")
expect(SlashBuiltins.handles("/import-claude"), "import-claude is builtin")
expect(!SlashBuiltins.handles("/commit fix typo"), "skills are not builtins")
expect(SlashBuiltins.name(in: "  /Docs web") == "/docs", "slash name is lowercased")

expect(LocalGuides.displayTitle("01-getting-started.md") == "Getting Started", "guide title strips index")
expect(LocalGuides.displayTitle("04-slash-commands.md") == "Slash Commands", "guide title keeps words")
let sampleGuides = [
    LocalGuide(filename: "04-slash-commands.md", title: "Slash Commands", url: URL(fileURLWithPath: "/tmp/04-slash-commands.md")),
    LocalGuide(filename: "19-plan-mode.md", title: "Plan Mode", url: URL(fileURLWithPath: "/tmp/19-plan-mode.md"))
]
expect(LocalGuides.match("plan", in: sampleGuides)?.filename == "19-plan-mode.md", "guide match by title")
expect(LocalGuides.match("04-slash", in: sampleGuides)?.filename == "04-slash-commands.md", "guide match by file")

let claudeJSON = """
{
  "mcpServers": {
    "brave-search": { "command": "npx", "args": ["-y", "brave"], "type": "stdio" },
    "remote": { "url": "https://mcp.example.com", "type": "http" }
  }
}
"""
let claudeURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude-import-\(UUID().uuidString).json")
try! claudeJSON.write(to: claudeURL, atomically: true, encoding: .utf8)
let missingHome = FileManager.default.temporaryDirectory.appendingPathComponent("claude-missing-\(UUID().uuidString)")
let snapshot = ClaudeImportSnapshot.discover(claudeHome: missingHome, claudeJSON: claudeURL)
expect(snapshot.exists, "claude json counts as import source")
expect(snapshot.servers.count == 2, "parses claude mcp servers")
expect(snapshot.servers.contains(where: { $0.name == "brave-search" && $0.transport == "stdio" }), "stdio server")
expect(snapshot.servers.contains(where: { $0.name == "remote" && $0.transport == "http" }), "http server")
expect(snapshot.report.contains("brave-search"), "report names servers")

let questionJSON: [String: Any] = [
    "sessionId": "s1",
    "questions": [[
        "question": "Which approach?",
        "header": "Approach",
        "multi_select": false,
        "options": [
            ["label": "A", "description": "Fast", "preview": "do A"],
            ["label": "B", "description": "Careful"]
        ]
    ]]
]
let parsedQuestion = UserQuestionRequest.parse(id: .int(9), params: questionJSON)
let folded = SessionFold.apply([
    SessionFold.userTurn("look at Sources/App.swift"),
    SessionUpdate(kind: .agentMessageChunk, text: "I'll edit it."),
    SessionUpdate(kind: .sessionRecap, text: "We opened the file."),
    SessionUpdate(kind: .autoCompactCompleted, text: "")
])
expect(folded.items.contains(where: { if case .user(_, let text) = $0 { return text.contains("App.swift") }; return false }), "fold records user")
expect(folded.items.contains(where: { if case .notice(_, let text) = $0 { return text.contains("opened") }; return false }), "fold recap is durable")
expect(folded.items.contains(where: { if case .notice(_, let text) = $0 { return text.contains("compacted") }; return false }), "fold compact is durable")
expect(folded.lastUserPreview.contains("App.swift"), "projection last user")
expect(folded.recap.contains("opened"), "fold stores recap")
expect(folded.compacted, "fold stores compacted")

var cancelSnap = SessionFold.apply([
    SessionUpdate(kind: .toolCall, title: "build", toolCallId: "run1", status: "running"),
    SessionUpdate(kind: .taskBackgrounded, text: "swift build", raw: ["task_id": "bg", "command": "swift build", "description": "Build"]),
    SessionUpdate(kind: .subagentSpawned, raw: ["subagent_id": "kid", "description": "Explore", "subagent_type": "explore"])
])
expect(cancelSnap.tasks.contains(where: { $0.isRunning }), "cancel setup task")
expect(cancelSnap.subagents.contains(where: { $0.isRunning }), "cancel setup subagent")
SessionFold.cancelActiveWork(onto: &cancelSnap)
expect(cancelSnap.items.contains(where: { if case .tool(_, _, let status, _) = $0 { return status == "cancelled" }; return false }), "cancel tools via fold")
expect(cancelSnap.tasks.allSatisfy { !$0.isRunning }, "cancel tasks via fold")
expect(cancelSnap.subagents.allSatisfy { !$0.isRunning }, "cancel subagents via fold")

let workspace = SessionWorkspace(id: "w1", cwd: URL(fileURLWithPath: "/tmp"))
workspace.fold(SessionFold.userTurn("hi"))
workspace.fold(SessionUpdate(kind: .sessionRecap, text: "Said hello"))
workspace.fold(SessionUpdate(kind: .autoCompactCompleted))
expect(workspace.recap == "Said hello", "workspace fold recap")
expect(workspace.compacted, "workspace fold compacted")
workspace.fold(SessionUpdate(kind: .toolCall, title: "run", toolCallId: "x", status: "running"))
workspace.markWorkStopped()
expect(workspace.items.contains(where: { if case .tool(_, _, let status, _) = $0 { return status == "cancelled" }; return false }), "workspace stop uses fold")

expect(FileManager.default.fileExists(atPath: updates.path), "replay fixture exists")
let replayed = SessionReplay.replay(jsonl: updates)
expect(replayed.report.updateCount >= 18, "replay reads fixture updates \(replayed.report.updateCount)")
expect(replayed.report.userCount == 1, "replay users")
expect(replayed.report.assistantCount == 1, "replay assistants")
expect(replayed.report.toolCount >= 2, "replay tools")
expect(replayed.report.todoCount == 2, "replay todos")
expect(replayed.report.taskCount == 1, "replay tasks")
expect(replayed.report.planCount == 1, "replay plan")
expect(replayed.report.compacted, "replay compacted")
expect(replayed.report.recap.contains("App.swift"), "replay recap")
expect(replayed.report.subagentCount == 1, "replay subagent")
expect(replayed.snapshot.subagents.first?.status == "completed", "replay subagent finished")
expect(replayed.snapshot.items.contains(where: { if case .notice(_, let text) = $0 { return text.contains("Retrying") }; return false }), "replay retry notice")

if let liveJSONL = SessionReplay.firstJSONL(
    under: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions")
) {
    let live = SessionReplay.replay(jsonl: liveJSONL)
    expect(live.report.updateCount > 0, "live session replay has updates")
}

let host = TerminalHost()
let termID = try! host.create(command: "printf 'grok-desktop-terminal\\n'")
var termOut = host.output(id: termID)
for _ in 0..<40 {
    if termOut?.exitCode != nil { break }
    Thread.sleep(forTimeInterval: 0.05)
    termOut = host.output(id: termID)
}
expect(termOut?.exitCode == 0, "terminal exit 0")
expect(termOut?.output.contains("grok-desktop-terminal") == true, "terminal captured stdout")
host.release(id: termID)
expect(host.snapshots.isEmpty, "terminal released")

expect(SessionUpdateKind(rawValue: "subagent_spawned") == .subagentSpawned, "subagent kind")
expect(SessionUpdateKind(rawValue: "retry_state") == .retryState, "retry kind")
expect(ACPEvent.preview(method: "session/prompt", params: ["sessionId": "abcdef1234"]).contains("abcd"), "event preview")

let planQ = UserQuestion.parse([
    "question": "Approve this plan?",
    "detail": "1. Fold events",
    "intent": ["kind": "plan-review", "approve": "Approve"],
    "options": [["label": "Approve"], ["label": "Revise"]]
])
if case .planReview(let approve) = planQ?.intent {
    expect(approve == "Approve", "plan-review intent")
} else {
    fail("expected plan-review intent")
}
expect(planQ?.detail.contains("Fold") == true, "question keeps plan detail")

let inferred = UserQuestion.parse([
    "question": "Should I execute the plan?",
    "options": [["label": "批准"], ["label": "打回"]]
])
if case .planReview(let approve) = inferred?.intent {
    expect(approve == "批准", "infer plan-review from 批准")
} else {
    fail("expected inferred plan-review")
}

expect(SessionFold.isAside("/btw also check tests"), "btw is aside")
expect(!SessionFold.isAside("also check tests"), "plain text is follow-up")

expect(parsedQuestion?.questions.count == 1, "parse ask_user_question")
expect(parsedQuestion?.questions.first?.options.count == 2, "question options")
expect(UserQuestionRequest.isMethod("x.ai/ask_user_question"), "ask method suffix")
expect(UserQuestionRequest.isMethod("ask_user_question"), "ask method bare")
expect(!UserQuestionRequest.isMethod("session/update"), "other method is not ask")
let accepted = UserQuestionOutcome.accepted(answers: ["Which approach?": ["A"]], partial: false).json
expect(accepted["type"] as? String == "Accepted", "accepted type")
expect((accepted["answers"] as? [String: Any])?["Which approach?"] as? String == "A", "accepted string or vec")

let richPermission = PermissionRequest.parse(id: .int(3), params: [
    "sessionId": "s1",
    "options": [["optionId": "proceed_once", "name": "Allow", "kind": "allow_once"]],
    "toolCall": [
        "title": "run_terminal_command",
        "kind": "execute",
        "rawInput": ["command": "swift test", "path": "/tmp/App.swift"]
    ]
] as [String: Any])
expect(richPermission.command == "swift test", "permission command")
expect(richPermission.path == "/tmp/App.swift", "permission path")
expect(richPermission.detail.contains("swift test"), "permission detail uses command")

let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
let yesterday = SessionRecord(
    id: "y",
    cwd: "/tmp/Demo",
    title: "Night work",
    updatedAt: yesterdayDate,
    model: "grok-4.6",
    directory: URL(fileURLWithPath: "/tmp")
)
expect(SessionSearch.matches(yesterday, query: "Night", now: now, chinese: true), "search title")
expect(SessionSearch.matches(yesterday, query: "Demo", now: now, chinese: true), "search folder")
expect(SessionSearch.matches(yesterday, query: "昨天", now: now, chinese: true), "search yesterday zh")
expect(SessionSearch.matches(yesterday, query: "yesterday", now: now, chinese: false), "search yesterday en")
expect(!SessionSearch.matches(yesterday, query: "missing-token", now: now, chinese: true), "search miss")

let diff = """
diff --git a/App.swift b/App.swift
--- a/App.swift
+++ b/App.swift
@@ -1,3 +1,4 @@
 keep
-old
+new
"""
let scanned = DiffScan.parse(diff)
expect(scanned.count == 1, "diff file count")
expect(scanned[0].name == "App.swift", "diff file name")
expect(scanned[0].added == 1, "diff added")
expect(scanned[0].removed == 1, "diff removed")
let wrapped = DiffScan.extractPatch("{\"diff\":\"diff --git a/A.swift b/A.swift\\n+ok\"}")
expect(wrapped.contains("diff --git"), "extract patch from json")

let imageRoot = FileManager.default.temporaryDirectory.appendingPathComponent("gd-imagine-\(UUID().uuidString)", isDirectory: true)
let imageFolder = imageRoot.appendingPathComponent("sid/images", isDirectory: true)
try! FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
let thumb = imageFolder.appendingPathComponent("shot.png")
try! Data([0x89, 0x50, 0x4E, 0x47]).write(to: thumb)
let recents = ImagineLibrary.recent(sessionsRoot: imageRoot, limit: 8)
expect(recents.contains(where: { $0.url.lastPathComponent == "shot.png" }), "imagine recent thumb")

expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/note.md")) == .markdown, "md is markdown")
expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/page.HTML")) == .html, "html kind")
expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/shot.PNG")) == .image, "png is image")
expect(FilePreview.kind(for: URL(fileURLWithPath: "/tmp/App.swift")) == .text, "swift is text")
let previewDir = FileManager.default.temporaryDirectory.appendingPathComponent("gd-preview-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
let previewMD = previewDir.appendingPathComponent("readme.md")
try! "# Hello preview\n\nA paragraph.".write(to: previewMD, atomically: true, encoding: .utf8)
let loadedMD = FilePreview.load(previewMD)
expect(loadedMD.kind == .markdown, "load md kind")
expect(loadedMD.text.contains("Hello preview"), "load md text")
expect(loadedMD.exists, "load md exists")
expect(FilePreview.kind(for: previewDir) == .directory, "directory kind")
let missingPreview = FilePreview.load(previewDir.appendingPathComponent("gone.md"))
expect(!missingPreview.exists, "missing md")
expect(missingPreview.kind == .markdown, "missing keeps md kind")

expect(!ChatLinkDetector.likelyContainsLinks("plain hello"), "plain text is not linky")
expect(ChatLinkDetector.likelyContainsLinks("see https://x.ai/build"), "http is linky")
expect(ChatLinkDetector.likelyContainsLinks("open Sources/App.swift"), "relative file is linky")

print("GrokDesktopSmoke ok")

