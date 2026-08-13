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

print("GrokDesktopSmoke ok")
