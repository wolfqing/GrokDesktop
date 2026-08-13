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

let planUpdate = SessionUpdate.parse(params: [
    "update": [
        "sessionUpdate": "plan",
        "entries": [["content": "Do the thing", "status": "in_progress", "priority": "high"]]
    ]
])
expect(planUpdate.kind == .plan, "plan kind")
expect(planUpdate.planEntries.count == 1, "plan parse")

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

print("GrokDesktopSmoke ok")
