import AppKit
import Foundation
import GrokDesktopCore
import SwiftUI

enum DemoStudio {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("--demo")
            || args.contains("--demo-screenshot")
            || env["GROK_DESKTOP_DEMO"] == "1"
            || env["GROK_DESKTOP_DEMO_SHOT"] != nil
    }

    static var screenshotURL: URL? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--demo-screenshot"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1])
        }
        if let path = ProcessInfo.processInfo.environment["GROK_DESKTOP_DEMO_SHOT"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static var shouldExitAfterScreenshot: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-screenshot-exit")
    }

    @MainActor
    static func writeScreenshot(model: AppModel, to url: URL) -> Bool {
        _ = model
        let view = DemoPosterView()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 1280, height: 840)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    static let cwd = URL(fileURLWithPath: "/Users/ada/Projects/northwind")

    static let account = AccountProfile(
        email: "ada@northwind.dev",
        name: "Ada Chen",
        userID: "demo",
        plan: .superGrok
    )

    static let usage = AccountUsage(
        creditPercent: 34,
        periodKind: .monthly,
        prepaidDollars: 12,
        products: [AccountUsage.Product(name: "Grok Build", percent: 34)],
        fetchedAt: Date(),
        isLoaded: true
    )

    static let workspace = WorkspaceSnapshot(
        path: cwd.path,
        name: "northwind",
        isRepo: true,
        branch: "main",
        insertions: 48,
        deletions: 11,
        remotes: ["github.com/northwind/northwind"],
        contextPercent: 22,
        contextUsed: 44_000,
        contextWindow: 200_000
    )

    static let project = NamedProject(name: "northwind", path: cwd.path)

    static func sessions(now: Date = Date()) -> [SessionRecord] {
        [
            SessionRecord(
                id: "demo-northwind",
                cwd: cwd.path,
                title: "Fix login retry on 401",
                updatedAt: now.addingTimeInterval(-80),
                model: "grok-4.6",
                directory: cwd,
                messageCount: 6,
                preview: "The retry helper was swallowing 401s."
            ),
            SessionRecord(
                id: "demo-docs",
                cwd: cwd.path,
                title: "Rewrite the CLI help text",
                updatedAt: now.addingTimeInterval(-3600 * 5),
                model: "grok-4.6",
                directory: cwd,
                messageCount: 4,
                preview: "Short flags first, then examples."
            ),
            SessionRecord(
                id: "demo-tests",
                cwd: cwd.path,
                title: "Add fixtures for auth errors",
                updatedAt: now.addingTimeInterval(-3600 * 26),
                model: "grok-4.6",
                directory: cwd,
                messageCount: 8,
                preview: "Cover 401, 429, and timeout."
            ),
            SessionRecord(
                id: "demo-review",
                cwd: "/Users/ada/Projects/lighthouse",
                title: "Review the upload pipeline",
                updatedAt: now.addingTimeInterval(-3600 * 50),
                model: "grok-4.6",
                directory: URL(fileURLWithPath: "/Users/ada/Projects/lighthouse"),
                messageCount: 3,
                preview: "Keep the checksum on the worker."
            )
        ]
    }

    static let items: [ConversationItem] = [
        .user(
            id: "u1",
            text: "Login retry swallows the 401 and spins forever. Walk AuthClient and fix it."
        ),
        .tool(id: "t1", title: "Read AuthClient.swift", status: "completed", detail: "northwind/Sources/AuthClient.swift"),
        .tool(id: "t2", title: "Read Retry.swift", status: "completed", detail: "northwind/Sources/Retry.swift"),
        .tool(id: "t3", title: "Edit AuthClient.swift", status: "completed", detail: "stop retrying on 401"),
        .assistant(
            id: "a1",
            text: """
The retry helper treated every HTTP error as transient. A 401 is a credential failure, so it should stop.

```swift
if status == 401 {
    throw AuthError.unauthorized
}
```

Tests in `AuthClientTests` cover 401, 429, and timeout. Ready when you are.
""",
            done: true
        )
    ]

    static let todos: [AgentTodo] = [
        AgentTodo(id: "d1", content: "Trace the login retry loop", status: "completed"),
        AgentTodo(id: "d2", content: "Stop retrying on 401", status: "completed"),
        AgentTodo(id: "d3", content: "Add AuthClient fixtures", status: "in_progress")
    ]

    static let hunks: [FileHunk] = [
        FileHunk(id: "h1", path: "Sources/AuthClient.swift", added: 18, removed: 6),
        FileHunk(id: "h2", path: "Tests/AuthClientTests.swift", added: 24, removed: 0)
    ]

    static let plan: [PlanEntry] = [
        PlanEntry(content: "Find where 401 is classified", status: "completed"),
        PlanEntry(content: "Fail fast on unauthorized", status: "completed"),
        PlanEntry(content: "Add fixtures for auth errors", status: "in_progress")
    ]

    static let gitDiff = """
diff --git a/Sources/AuthClient.swift b/Sources/AuthClient.swift
--- a/Sources/AuthClient.swift
+++ b/Sources/AuthClient.swift
@@ -40,6 +40,10 @@
         for attempt in 1...3 {
             let response = try await send(request)
+            if response.status == 401 {
+                throw AuthError.unauthorized
+            }
             if response.ok { return response }
         }
"""
}
