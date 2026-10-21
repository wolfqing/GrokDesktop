import Foundation
import GrokDesktopCore

private final class ParityHTTPBox: @unchecked Sendable {
    var status = 0
    var text = ""
}

/// Calls the shipped decision functions from a fresh start. Names stay inside this function.
func runFeatureParity() {
    let fm = FileManager.default
    let parityRoot = fm.temporaryDirectory.appendingPathComponent("gd-parity-\(UUID().uuidString)", isDirectory: true)
    do {
        try fm.createDirectory(at: parityRoot, withIntermediateDirectories: true)
    } catch {
        fail("parity temp \(error)")
    }
    defer { try? fm.removeItem(at: parityRoot) }

    func attempt(_ message: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            fail("\(message) \(error)")
        }
    }

    func parityHTTP(method: String, url: URL, bearer: String?, body: String?) -> (Int, String) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let gate = DispatchSemaphore(value: 0)
        let box = ParityHTTPBox()
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false
        ]
        config.timeoutIntervalForRequest = 2
        let task = URLSession(configuration: config).dataTask(with: request) { data, response, error in
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            box.text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if box.status == 0, let error {
                box.text = error.localizedDescription
            }
            gate.signal()
        }
        task.resume()
        if gate.wait(timeout: .now() + 4) == .timedOut {
            task.cancel()
            return (0, "")
        }
        return (box.status, box.text)
    }

    let policy = PermissionPolicy.fresh()
    expect(policy.tier == .ask, "permission default ask")
    expect(!policy.isYOLODefault, "yolo is not the default")
    expect(policy.decision(.allowOnce, project: "/repo") == .allowOnce, "allow once answers this prompt")
    let once = policy.setting(.allowOnce, project: "/repo")
    expect(once.decision(nil, project: "/repo") == .ask, "stored allow once falls back to ask")
    let sessioned = policy.setting(.allowSession, project: "/repo")
    expect(sessioned.decision(nil, project: "/repo") == .allowSession, "allow for session sticks")
    expect(sessioned.decision(nil, project: "/other") == .ask, "other project stays ask")
    let denied = sessioned.setting(.deny, project: "/repo")
    expect(denied.decision(nil, project: "/repo") == .deny, "deny that project")
    expect(denied.decision(nil, project: "/other") == .ask, "deny does not spread")
    expect(policy.setting(.yolo, project: "/repo").tier == .yolo, "yolo is explicit")
    expect(PermissionPolicy.fresh().isYOLODefault == false, "fresh policy is still ask")
    var cleared = PermissionPolicy(tier: .ask, projectTiers: ["/repo": .deny])
    cleared = cleared.clearingProject("/repo")
    expect(cleared.projectTiers["/repo"] == nil, "follow default clears the override")
    expect(cleared.decision(nil, project: "/repo") == .ask, "cleared project uses ask")
    parityWait {
        let board = ACPClient(
            locator: GrokBinaryLocator(extraSearchPaths: [], pathEnvironment: "", fileExists: { _ in false }),
            workingDirectory: parityRoot
        )
        for id in ["a", "b", "c", "d"] {
            board.registerLocalSession(id: id, cwd: parityRoot, turnRunning: false)
        }
        let recycled = board.reapSessions(idleSeconds: ["a": 0, "b": 0, "c": 0, "d": 90], focusedID: "a")
        expect(recycled == ["d"], "process cap recycles the idle session")
        expect(!board.hasWorkspace("d"), "recycled session is dropped")
        expect(board.hasWorkspace("a"), "focused session stays")
    }
    parityWait {
        let root = parityRoot.appendingPathComponent("perm-agent", isDirectory: true)
        let bin = try parityInstallStub(at: root)
        try Data("on".utf8).write(to: root.appendingPathComponent("permission.on"))
        let client = ACPClient(locator: parityLocator(bin), workingDirectory: root)
        client.permissionPolicy = PermissionPolicy(tier: .deny)
        defer { client.stop() }
        do {
            try await client.connectIfNeeded()
        } catch {
            fail("permission agent \(error)")
        }
        await parityUntil(8) {
            (try? String(contentsOf: root.appendingPathComponent("rpc.log"), encoding: .utf8))?.contains("reject") == true
        }
        let log = (try? String(contentsOf: root.appendingPathComponent("rpc.log"), encoding: .utf8)) ?? ""
        expect(log.contains("reject"), "permission decision rejects the prompt")
        expect(client.permission == nil, "denied prompt is not left on the bar")
    }
    expect(ModelTier.fast.effort == "low", "fast tier")
    expect(ModelTier.heavy.effort == "xhigh", "heavy uses extra-high")
    expect(EffortLevel.xhigh.rawValue == "xhigh", "xhigh effort exists")
    expect(SessionBoard.processCap == 3, "process cap")
    expect(SessionBoard.idleRecycleSeconds == 30, "idle recycle")
    expect(SessionBoard.lane(needsInput: true, working: true) == .needsInput, "needs input lane")
    expect(SessionBoard.lane(needsInput: false, working: true) == .working, "working lane")
    expect(SessionBoard.lane(needsInput: false, working: false) == .done, "done lane")
    expect(SessionBoard.keepStreaming(focusedID: "focus", liveIDs: ["a", "b"]) == ["a", "b"], "switch keeps streams")
    let dropped = SessionBoard.recycle(idleSeconds: ["old": 40, "fresh": 1], cap: 3, idleLimit: 30)
    expect(dropped == ["old"], "idle session is recycled")
    var references = SessionLinks.attach(references: [], sessionID: "1")
    references = SessionLinks.attach(references: references, sessionID: "2")
    references = SessionLinks.attach(references: references, sessionID: "3")
    expect(SessionLinks.attach(references: references, sessionID: "4") == references, "fourth reference refused")
    expect(SessionLinks.fork(sessionID: "session", turnID: "turn") == "session#turn", "fork id")
    let manualKey = GrokBinaryLocator.manualPathKey
    let previousManual = UserDefaults.standard.string(forKey: manualKey)
    UserDefaults.standard.set("/tmp/manual-grok-parity", forKey: manualKey)
    let manualName = GrokBinaryLocator(extraSearchPaths: [], pathEnvironment: "", fileExists: { _ in false }).candidates().first?.lastPathComponent
    if let previousManual {
        UserDefaults.standard.set(previousManual, forKey: manualKey)
    } else {
        UserDefaults.standard.removeObject(forKey: manualKey)
    }
    expect(manualName == "manual-grok-parity", "manual binary is searched first")
    print("pass permission")

    attempt("session data") {
        let independent = parityRoot.appendingPathComponent("ind", isDirectory: true)
        let shared = parityRoot.appendingPathComponent("shared", isDirectory: true)
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        let sentinel = Data("shared-only\n".utf8)
        try sentinel.write(to: shared.appendingPathComponent("ids.txt"))
        let independentLayout = SessionDataLayout(mode: .independent, independentIDs: ["a"], sharedIDs: ["b"])
        expect(independentLayout.visibleIDs() == ["a"], "independent shows its own ids")
        expect(!independentLayout.visibleIDs().contains("b"), "independent hides shared ids")
        let sharedLayout = SessionDataLayout(mode: .shared, independentIDs: ["a"], sharedIDs: ["b"])
        expect(sharedLayout.visibleIDs() == ["b"], "shared shows its own ids")
        expect(!independentLayout.mergesHistories && !sharedLayout.mergesHistories, "modes do not merge")
        try SessionDataLayout.writeActive(mode: .independent, ids: ["a"], independent: independent, shared: shared)
        expect(try Data(contentsOf: shared.appendingPathComponent("ids.txt")) == sentinel, "shared file unchanged")
        let independentBytes = try Data(contentsOf: independent.appendingPathComponent("ids.txt"))
        try SessionDataLayout.writeActive(mode: .shared, ids: ["b"], independent: independent, shared: shared)
        expect(try Data(contentsOf: independent.appendingPathComponent("ids.txt")) == independentBytes, "independent file unchanged")

        let keepFile = parityRoot.appendingPathComponent("keep.txt")
        try "stay".write(to: keepFile, atomically: true, encoding: .utf8)
        let removed = ProjectTrust.remove(projects: [NamedProject(id: "p1", name: "keep", path: keepFile.path)], id: "p1")
        expect(removed.isEmpty, "project leaves the list")
        expect(fm.fileExists(atPath: keepFile.path), "removing a project keeps the file")
        expect(!ProjectTrust.allowsWrite(path: "/tmp/nope", trusted: [parityRoot.path], enforce: true), "untrusted folder cannot write")
        expect(!SandboxMode.allowsWrite(trusted: false, profile: "workspace"), "untrusted sandbox blocks write")
        expect(!SandboxMode.allowsWrite(trusted: true, profile: "strict"), "strict sandbox blocks write")
        expect(SandboxMode.allowsWrite(trusted: true, profile: "off"), "trusted folder can write")

        let sessionsRoot = parityRoot.appendingPathComponent("sessions", isDirectory: true)
        let sessionDir = sessionsRoot.appendingPathComponent("proj", isDirectory: true).appendingPathComponent("sid1", isDirectory: true)
        try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let summary = #"{"generated_title":"Hello","num_messages":1,"info":{"id":"sid1","cwd":"/tmp/proj"}}"#
        try summary.write(to: sessionDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        expect(SessionIndex(sessionsRoot: sessionsRoot).load().contains { $0.id == "sid1" }, "session is listed")
        let archived = try SessionArchive.move(sessionDirectory: sessionDir, archiveRoot: SessionArchive.root(sessionsRoot: sessionsRoot))
        expect(fm.fileExists(atPath: archived.appendingPathComponent("summary.json").path), "archive keeps the session")
        expect(!SessionIndex(sessionsRoot: sessionsRoot).load().contains { $0.id == "sid1" }, "archive drops it from the index")

        let source = parityRoot.appendingPathComponent("cli-src", isDirectory: true)
        let destination = parityRoot.appendingPathComponent("cli-dst", isDirectory: true)
        let sourceSession = source.appendingPathComponent("repo", isDirectory: true).appendingPathComponent("only1", isDirectory: true)
        try fm.createDirectory(at: sourceSession, withIntermediateDirectories: true)
        try summary.replacingOccurrences(of: "sid1", with: "only1").write(to: sourceSession.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        expect(CLISessionImport.candidates(source: source, destination: destination) == ["only1"], "import lists the missing id")
        try CLISessionImport.copy(id: "only1", source: source, destination: destination)
        expect(SessionIndex(sessionsRoot: source).load().contains { $0.id == "only1" }, "import copies")
        expect(SessionIndex(sessionsRoot: destination).load().contains { $0.id == "only1" }, "import lands in the destination")
    }
    print("pass session-data")

    let trees = [WorktreeRecord(path: "/tmp/repo-a", branch: "main")]
    expect(WorktreeSwitch.cwd(current: "/tmp/repo", worktrees: trees, selected: "/tmp/repo-a") == "/tmp/repo-a", "listed worktree becomes cwd")
    expect(WorktreeSwitch.cwd(current: "/tmp/repo", worktrees: trees, selected: "/tmp/missing") == nil, "unknown worktree is refused")
    print("pass worktree")

    attempt("diff") {
        let diffRoot = parityRoot.appendingPathComponent("diff", isDirectory: true)
        let files = [
            ReviewedFile(path: "one.txt", baseline: "base-one", working: "work-one"),
            ReviewedFile(path: "two.txt", baseline: "base-two", working: "work-two")
        ]
        let rejected = try DiffReview.apply(action: .reject, files: files, paths: ["one.txt"], root: diffRoot)
        expect(rejected[0].working == "base-one" && rejected[1].working == "work-two", "reject one file")
        expect(try String(contentsOf: diffRoot.appendingPathComponent("one.txt"), encoding: .utf8) == "base-one", "reject writes baseline")
        expect(!fm.fileExists(atPath: diffRoot.appendingPathComponent("two.txt").path), "other file stays untouched")
        let accepted = try DiffReview.apply(action: .accept, files: files, paths: ["one.txt", "two.txt"], root: diffRoot)
        expect(accepted.allSatisfy(\.accepted), "batch accept")
        expect(try String(contentsOf: diffRoot.appendingPathComponent("two.txt"), encoding: .utf8) == "work-two", "accept writes working bytes")
        _ = try DiffReview.apply(action: .revert, files: files, paths: ["one.txt", "two.txt"], root: diffRoot)
        expect(try String(contentsOf: diffRoot.appendingPathComponent("one.txt"), encoding: .utf8) == "base-one", "revert one")
        expect(try String(contentsOf: diffRoot.appendingPathComponent("two.txt"), encoding: .utf8) == "base-two", "revert batch")
    }
    print("pass diff")

    attempt("text") {
        let editURL = parityRoot.appendingPathComponent("note.txt")
        try "two".write(to: editURL, atomically: true, encoding: .utf8)
        let reloaded = TextEditSync.reload(editor: TextEditStamp(text: "one", modified: .distantPast), url: editURL)
        expect(reloaded.text == "two", "editor reloads a newer disk write")
    }
    print("pass text-edit")

    attempt("media") {
        let trusted = parityRoot.appendingPathComponent("proj", isDirectory: true)
        try fm.createDirectory(at: trusted, withIntermediateDirectories: true)
        let shot = trusted.appendingPathComponent("shot.png")
        fm.createFile(atPath: shot.path, contents: Data([0x89]))
        expect(MediaPathScope.allows(path: shot.path, trustedRoots: [trusted.path], appData: "/tmp/gd-app", temp: "/tmp", grants: []), "trusted preview")
        expect(!MediaPathScope.allows(path: "/Users/ada/.ssh/id_rsa", trustedRoots: [trusted.path], appData: "/tmp/gd-app", temp: "/tmp", grants: []), "ssh key denied")
        expect(!MediaPathScope.allows(path: trusted.appendingPathComponent("secrets.json").path, trustedRoots: [trusted.path], appData: "/tmp/gd-app", temp: "/tmp", grants: []), "secrets denied")
        expect(!MediaPathScope.allows(path: trusted.appendingPathComponent("../.ssh/config").path, trustedRoots: [trusted.path], appData: "/tmp/gd-app", temp: "/tmp", grants: []), "escaped ssh denied")
        expect(FilePreview.classify(extension: "mp4") == .video, "video kind")
        expect(FilePreview.classify(extension: "mp3") == .audio, "audio kind")
        expect(FilePreview.classify(extension: "pdf") == .pdf, "pdf kind")
        expect(FilePreview.classify(extension: "docx") == .office, "office kind")
    }
    print("pass media-scope")

    for channel in IMChannel.allCases {
        let incomplete = IMBridgeConfig(channel: channel, fields: [:])
        expect(!incomplete.isComplete, "incomplete \(channel.rawValue)")
        expect(IMRouter.accept(payload: IMRouter.fixturePayload(channel), config: incomplete) == nil, "reject incomplete \(channel.rawValue)")
        let inbound = IMRouter.accept(payload: IMRouter.fixturePayload(channel), config: IMRouter.fixtureConfig(channel))
        expect(inbound?.text == "ping", "fixture \(channel.rawValue)")
    }
    let trustedProjects = ["/Users/ada/Projects/app"]
    let started = IMRouter.route(
        inbound: IMInbound(channel: .telegram, sender: "fixture", text: "/p app fix the bug"),
        trustedProjects: trustedProjects,
        sessions: [],
        boundProject: nil
    )
    expect(started == .start(project: "/Users/ada/Projects/app", prompt: "fix the bug"), "/p starts a trusted project")
    let untrusted = IMRouter.route(
        inbound: IMInbound(channel: .telegram, sender: "fixture", text: "/p secret nope"),
        trustedProjects: trustedProjects,
        sessions: [],
        boundProject: nil
    )
    expect(untrusted == .rejectedUntrusted, "/p refuses an untrusted name")
    let resumed = IMRouter.route(
        inbound: IMInbound(channel: .slack, sender: "fixture", text: "/r s1 continue"),
        trustedProjects: trustedProjects,
        sessions: ["s1"],
        boundProject: "/Users/ada/Projects/app"
    )
    expect(resumed == .resume(sessionID: "s1", prompt: "continue"), "/r resumes")
    let resumedUntrusted = IMRouter.route(
        inbound: IMInbound(channel: .slack, sender: "fixture", text: "/r s1 continue"),
        trustedProjects: trustedProjects,
        sessions: ["s1"],
        boundProject: "/tmp/nope"
    )
    expect(resumedUntrusted == .rejectedUntrusted, "/r refuses an untrusted project")
    let turned = IMRouter.route(
        inbound: IMInbound(channel: .discord, sender: "fixture", text: "hello"),
        trustedProjects: trustedProjects,
        sessions: [],
        boundProject: "/Users/ada/Projects/app"
    )
    expect(turned == .turn(project: "/Users/ada/Projects/app", prompt: "hello"), "plain text is a turn")
    let turnedAway = IMRouter.route(
        inbound: IMInbound(channel: .discord, sender: "fixture", text: "hello"),
        trustedProjects: trustedProjects,
        sessions: [],
        boundProject: "/tmp/nope"
    )
    expect(turnedAway == .rejectedUntrusted, "plain text needs a trusted project")
    parityWait {
        let cold = ACPClient(
            locator: GrokBinaryLocator(extraSearchPaths: [], pathEnvironment: "", fileExists: { _ in false }),
            workingDirectory: parityRoot
        )
        let rejected = await IMDelivery.deliver(route: turnedAway, client: cold)
        expect(rejected == false, "rejected inbound does not send")
        expect(cold.launchedExecutable.isEmpty, "rejected inbound does not start an agent")
        let root = parityRoot.appendingPathComponent("im-agent", isDirectory: true)
        let bin = try parityInstallStub(at: root)
        let client = ACPClient(locator: parityLocator(bin), workingDirectory: root)
        defer { client.stop() }
        let project = root.path
        let startedRoute = IMRouter.route(
            inbound: IMInbound(channel: .telegram, sender: "fixture", text: "/p \(root.lastPathComponent) fix-from-im"),
            trustedProjects: [project],
            sessions: [],
            boundProject: nil
        )
        expect(startedRoute == .start(project: project, prompt: "fix-from-im"), "live /p route")
        expect(await IMDelivery.deliver(route: startedRoute, client: client), "/p starts a turn")
        await parityUntil(8) { parityLog(root).contains("fix-from-im") }
        expect(parityLog(root).contains("fix-from-im"), "/p prompt reached the agent")
        let session = client.sessionID ?? ""
        expect(client.hasWorkspace(session), "/p created the session")
        let resumeRoute = IMRouter.route(
            inbound: IMInbound(channel: .slack, sender: "fixture", text: "/r \(session) resume-from-im"),
            trustedProjects: [project],
            sessions: client.workspaceIDs,
            boundProject: project
        )
        expect(await IMDelivery.deliver(route: resumeRoute, client: client), "/r continues")
        await parityUntil(8) { parityLog(root).contains("resume-from-im") }
        let turnRoute = IMRouter.route(
            inbound: IMInbound(channel: .discord, sender: "fixture", text: "ping"),
            trustedProjects: [project],
            sessions: client.workspaceIDs,
            boundProject: project
        )
        expect(await IMDelivery.deliver(route: turnRoute, client: client), "plain text continues")
        await parityUntil(8) { parityLog(root).contains("ping") }
        expect(parityLog(root).contains("ping"), "fixture text reached the agent")
    }
    print("pass im")

    let api = SessionAPIServer()
    let bearer = "parity-bearer"
    do {
        let port = try api.start(token: bearer, exposure: .loopback)
        expect(api.boundHost == "127.0.0.1", "session api binds loopback")
        expect(MirrorExposure.lan.bindAddress == "0.0.0.0", "lan bind")
        expect(MirrorExposure.tunnel.bindAddress == "127.0.0.1", "tunnel stays on loopback")
        expect(MirrorBind.uiToken(stored: bearer) == "••••", "token is masked")
        expect(!MirrorBind.uiToken(stored: bearer).contains(bearer), "ui hides the bearer")
        api.update(sessions: [SessionAPIServer.ListedSession(id: "busy1", busy: true)])
        let listURL = URL(string: "http://127.0.0.1:\(port)/v1/sessions")!
        var listed = (0, "")
        for _ in 0..<6 {
            listed = parityHTTP(method: "GET", url: listURL, bearer: bearer, body: nil)
            if listed.0 == 200 { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        expect(port != 0, "session api port")
        expect(listed.0 == 200, "session list status \(listed.0) \(listed.1)")
        expect(listed.1.contains("busy1"), "session list body \(listed.1)")
        let queued = parityHTTP(
            method: "POST",
            url: URL(string: "http://127.0.0.1:\(port)/v1/sessions/busy1/continue")!,
            bearer: bearer,
            body: #"{"text":"follow up"}"#
        )
        expect(queued.0 == 202 && queued.1.contains("queued"), "busy session queues")
        expect(api.snapshot().count == 1, "queue does not create a session")
        expect(api.queuedText(id: "busy1").contains("follow up"), "queued text is kept")
        let unknown = parityHTTP(
            method: "POST",
            url: URL(string: "http://127.0.0.1:\(port)/v1/sessions/missing/continue")!,
            bearer: bearer,
            body: #"{"text":"x"}"#
        )
        expect(unknown.0 == 404, "unknown session")
        expect(api.snapshot().count == 1, "unknown id is not created")
        let deniedAPI = parityHTTP(method: "GET", url: listURL, bearer: nil, body: nil)
        expect(deniedAPI.0 == 401, "missing bearer")
        api.update(sessions: [SessionAPIServer.ListedSession(id: "busy1", busy: false)])
        let accepted = parityHTTP(
            method: "POST",
            url: URL(string: "http://127.0.0.1:\(port)/v1/sessions/busy1/continue")!,
            bearer: bearer,
            body: #"{"text":"later"}"#
        )
        expect(accepted.0 == 200 && accepted.1.contains("accepted"), "idle continue is accepted")
        expect(api.snapshot().count == 1, "accept does not add a session")
        let signal = ParitySignal()
        api.onQueued = { id, text in
            signal.id = id
            signal.text = text
        }
        let callback = parityHTTP(
            method: "POST",
            url: URL(string: "http://127.0.0.1:\(port)/v1/sessions/busy1/continue")!,
            bearer: bearer,
            body: #"{"text":"callback-text"}"#
        )
        expect(callback.0 == 200, "callback continue")
        expect(signal.id == "busy1" && signal.text == "callback-text", "continue notifies the session")
        parityWait {
            let mirrorRoot = parityRoot.appendingPathComponent("mirror-agent", isDirectory: true)
            let mirrorBin = try parityInstallStub(at: mirrorRoot)
            let mirror = ACPClient(locator: parityLocator(mirrorBin), workingDirectory: mirrorRoot)
            defer { mirror.stop() }
            mirror.registerLocalSession(id: "busy1", cwd: mirrorRoot, turnRunning: true)
            await mirror.deliverMirrorContinues(server: api, sessionID: "missing")
            expect(mirror.workspaceIDs == ["busy1"], "unknown continue does not create a session")
            await mirror.deliverMirrorContinues(server: api, sessionID: "busy1")
            let queuedTexts = mirror.queuedTexts(sessionID: "busy1")
            expect(queuedTexts.contains("follow up"), "busy continue reaches the session queue")
            expect(queuedTexts.contains("callback-text"), "later continue stays queued")
            expect(mirror.launchedExecutable.isEmpty, "busy continue does not start a second agent")
            expect(!parityLog(mirrorRoot).contains("follow up"), "busy queue is not sent yet")
            mirror.setTurnRunning("busy1", false)
            try await mirror.drainFollowUps(sessionID: "busy1")
            await parityUntil(8) { parityLog(mirrorRoot).contains("follow up") }
            expect(parityLog(mirrorRoot).contains("follow up"), "drained continue reaches send")
            let tunnel = MirrorTunnel()
            try tunnel.launch(port: 9)
            expect(tunnel.launchedArguments == MirrorBind.tunnelCommand(port: 9), "quick tunnel command")
            expect(tunnel.launchedPID > 0, "quick tunnel launched")
            tunnel.stop()
        }
        api.stop()
    } catch {
        api.stop()
        fail("session api \(error)")
    }
    print("pass session-api")

    expect(SSHWorkspace.agentArgv(host: "devbox") == ["ssh", "devbox", "grok agent stdio"], "ssh argv")
    expect(SSHWorkspace.localCwd(remotePath: "devbox:~/src") == nil, "remote path is not a local cwd")
    expect(SSHWorkspace.relative("src/main.swift") == "src/main.swift", "relative path")
    expect(SSHWorkspace.relative("src/../secret") == nil, "dotdot refused")
    let parsedHosts = SSHWorkspace.hosts(configText: "Host devbox\n  HostName 10.0.0.8\n")
    expect(parsedHosts.contains { $0.alias == "devbox" && $0.hostName == "10.0.0.8" }, "ssh config host")
    expect(SSHWorkspace.sessionHost("devbox:~/src") == nil, "remote path is not a host")
    let readArgv = SSHWorkspace.remoteReadArgv(host: "devbox", relativePath: "src/main.swift")
    expect(readArgv == ["ssh", "devbox", "cat -- src/main.swift"], "remote read argv")
    expect(SSHWorkspace.remoteReadArgv(host: "devbox", relativePath: "src/../secret") == nil, "remote read rejects dotdot")
    expect(SSHWorkspace.remoteWriteArgv(host: "devbox", relativePath: "src/main.swift")?.dropFirst().first == "devbox", "remote write keeps the host")
    expect(SSHWorkspace.testArgv(host: "devbox")?.contains("devbox") == true, "ssh test argv")
    expect(SSHWorkspace.watchArgv(host: "devbox")?.last == "devbox", "ssh watch argv")
    expect(SSHWorkspace.skillsArgv(host: "devbox") == ["ssh", "devbox", "grok skills list"], "remote skills argv")
    expect(SSHWorkspace.forwardArgv(host: "devbox", localPort: 8787, remotePort: 8787)?.last == "devbox", "loopback forward argv")
    expect(SSHWorkspace.terminalArguments(host: "devbox") == ["-t", "devbox"], "remote terminal argv")
    let agentArgs = SSHWorkspace.agentArguments("devbox")
    expect(agentArgs.contains("devbox"), "remote agent host argument")
    expect(agentArgs.contains("BatchMode=yes"), "remote agent does not prompt")
    parityWait(20) {
        let keep = SSHKeep()
        try keep.launch(executable: "/bin/sleep", arguments: ["12"])
        try await Task.sleep(nanoseconds: 5_000_000_000)
        expect(keep.isAlive(), "ssh keep stays up past the old timeout")
        keep.stop()
        expect(!keep.isAlive(), "ssh keep stops")
        let root = parityRoot.appendingPathComponent("ssh-agent", isDirectory: true)
        let bin = try parityInstallStub(at: root)
        let client = ACPClient(locator: parityLocator(bin), workingDirectory: root)
        defer { client.stop() }
        try await client.connectIfNeeded()
        expect(client.launchedExecutable == bin.path, "local agent starts first")
        client.remoteHost = "127.0.0.1"
        do {
            try await client.connectIfNeeded()
        } catch {
            _ = error
        }
        expect(client.launchedExecutable == "/usr/bin/ssh", "remote session starts ssh")
        expect(client.launchedArguments.contains("127.0.0.1"), "ssh target is the host")
        expect(client.reportedSessionCWD(localPath: "/Users/me/proj") == ".", "remote session cwd is not a local path")
        client.remoteHost = ""
        expect(client.reportedSessionCWD(localPath: "/Users/me/proj") == "/Users/me/proj", "local cwd stays local")
    }
    print("pass ssh")

    let pendingPR = #"{"number":7,"comments":[{"id":"c1"}],"reviews":[],"statusCheckRollup":[{"state":"PENDING"}]}"#
    let failingPR = #"{"number":7,"comments":[{"id":"c1"},{"id":"c2"}],"reviews":[{"id":"r1"}],"statusCheckRollup":[{"state":"FAILURE"}]}"#
    let greenPR = #"{"number":7,"comments":[{"id":"c1"},{"id":"c2"}],"reviews":[{"id":"r1"}],"statusCheckRollup":[{"state":"SUCCESS"}]}"#
    let opened = PRWatch.followUps(previousJSON: [pendingPR], currentJSON: [failingPR])
    expect(opened.contains { $0.reason == "comment" }, "new comment")
    expect(opened.contains { $0.reason == "review" }, "new review")
    expect(opened.contains { $0.reason == "ci-failing" }, "ci becomes failing")
    let passed = PRWatch.followUps(previousJSON: [failingPR], currentJSON: [greenPR])
    expect(passed.contains { $0.reason == "ci-green" }, "ci becomes green")
    expect(PRWatch.followUps(previousJSON: [pendingPR], currentJSON: ["nope"]).isEmpty, "unreadable gh output")
    expect(PRWatch.classify(before: [PRSnapshot(number: 7, commentIDs: ["c1"], reviewIDs: [], ci: .pending)], after: [PRSnapshot(number: 7, commentIDs: ["c1", "c2"], reviewIDs: [], ci: .failing)], ghReadable: false).isEmpty, "gh flag blocks follow-ups")
    parityWait {
        let watcher = ACPClient(
            locator: GrokBinaryLocator(extraSearchPaths: [], pathEnvironment: "", fileExists: { _ in false }),
            workingDirectory: parityRoot
        )
        watcher.registerLocalSession(id: "pr1", cwd: parityRoot, turnRunning: true)
        await watcher.enqueueFollowUps(opened, sessionID: "pr1")
        expect(watcher.queuedTexts(sessionID: "pr1").count == opened.count, "every pull request follow-up is queued")
        expect(opened.count >= 3, "comment review and ci are separate")
        expect(watcher.launchedExecutable.isEmpty, "queued follow-ups do not start a new agent")
    }
    print("pass pr-watch")

    attempt("relay") {
        let independentHome = parityRoot.appendingPathComponent("relay-ind", isDirectory: true)
        let sharedHome = parityRoot.appendingPathComponent("relay-shared", isDirectory: true)
        try fm.createDirectory(at: sharedHome, withIntermediateDirectories: true)
        let sharedSentinel = Data("shared-relay\n".utf8)
        try sharedSentinel.write(to: sharedHome.appendingPathComponent("relay.json"))
        let profile = RelayProfile(
            preset: RelayPreset.openrouter.rawValue,
            baseURL: RelayPresets.baseURL(RelayPreset.openrouter.rawValue),
            defaultModel: "grok-4.7",
            keyAccount: "relay-account"
        )
        _ = try RelayHome.apply(mode: .independent, profile: profile, independentRoot: independentHome, sharedRoot: sharedHome)
        expect(try Data(contentsOf: sharedHome.appendingPathComponent("relay.json")) == sharedSentinel, "shared home unchanged")
        let independentBytes = try Data(contentsOf: independentHome.appendingPathComponent("relay.json"))
        let independentText = String(data: independentBytes, encoding: .utf8) ?? ""
        expect(!independentText.contains("sk-live"), "relay file has no key")
        _ = try RelayHome.apply(mode: .shared, profile: profile, independentRoot: independentHome, sharedRoot: sharedHome)
        expect(try Data(contentsOf: independentHome.appendingPathComponent("relay.json")) == independentBytes, "independent home unchanged")
        for preset in [RelayPreset.openrouter, .requesty, .deepseek, .ai98pro] {
            expect(!RelayPresets.baseURL(preset.rawValue).isEmpty, "preset \(preset.rawValue)")
        }
        expect(RelayProbe.classify(httpStatus: 401, urlErrorCode: nil) == .auth, "probe auth")
        expect(RelayProbe.classify(httpStatus: nil, urlErrorCode: NSURLErrorTimedOut) == .timeout, "probe timeout")
        expect(RelayProbe.classify(httpStatus: nil, urlErrorCode: NSURLErrorCannotFindHost) == .dns, "probe dns")
        let home = parityRoot.appendingPathComponent("agent-home", isDirectory: true)
        let hooks = home.appendingPathComponent("hooks", isDirectory: true)
        try fm.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"{"hooks":[{"event":"SessionStart","command":"echo desk-hook"}]}"#.write(
            to: hooks.appendingPathComponent("ping.json"),
            atomically: true,
            encoding: .utf8
        )
        let specs = ExtensionGate.specNames(hooksDirectory: hooks, event: "SessionStart", command: "echo desk-hook")
        expect(specs == ["global/ping:session_start[0].hooks[0]"], "hook spec \(specs)")
        var toggles = ExtensionToggles.set([], kind: "hook", name: specs[0], enabled: false)
        toggles = ExtensionToggles.set(toggles, kind: "mcp", name: "local", enabled: false)
        toggles = ExtensionToggles.set(toggles, kind: "plugin", name: "demo", enabled: false)
        toggles = ExtensionToggles.set(toggles, kind: "agent", name: "reviewer", enabled: false)
        try ExtensionGate.apply(home: home, toggles: toggles)
        let disabledHooks = try String(contentsOf: home.appendingPathComponent("disabled-hooks"), encoding: .utf8)
        expect(disabledHooks.contains("global/ping:session_start[0].hooks[0]"), "disabled hook line")
        let config = try String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8)
        expect(config.contains("local") && config.contains("demo") && config.contains("reviewer"), "extension config \(config)")
        let store = home.appendingPathComponent("toggles.json")
        ExtensionGate.save(toggles, url: store)
        expect(!ExtensionToggles.isEnabled(ExtensionGate.load(url: store), kind: "mcp", name: "local"), "toggles persist")
    }
    parityWait {
        let home = parityRoot.appendingPathComponent("agent-home", isDirectory: true)
        let bin = try parityInstallStub(at: home)
        let client = ACPClient(locator: parityLocator(bin), workingDirectory: home)
        client.grokHome = home.path
        defer { client.stop() }
        try await client.connectIfNeeded()
        await parityUntil(8) {
            (try? String(contentsOf: home.appendingPathComponent("env.log"), encoding: .utf8)) == home.path
        }
        let seen = (try? String(contentsOf: home.appendingPathComponent("env.log"), encoding: .utf8)) ?? ""
        expect(seen == home.path, "independent home is GROK_HOME \(seen)")
    }
    print("pass relay")

    let diagnostic = DiagnosticExport.make(
        version: "0.1.30",
        grokVersion: "test",
        state: "ready",
        lastError: "api_key=sk-live-secret",
        sessionID: "s",
        cwd: "/tmp/app",
        stderr: ["token: super-secret-value"]
    )
    expect(!diagnostic.contains("sk-live-secret"), "diagnostic hides the key")
    expect(!diagnostic.contains("super-secret-value"), "diagnostic hides the token")
    expect(diagnostic.contains("[redacted]"), "diagnostic marks redaction")
    let secretLine = AccountKeychain.logLine(account: "acct", secret: "sk-live-secret")
    expect(!secretLine.contains("sk-live-secret"), "log line hides the secret")
    expect(AccountKeychain.service == "com.wolfqing.GrokDesktop.secrets", "keychain service is this app")
    expect(Doctor.classify(cliFound: false, signedIn: true, probe: nil, agentCrashed: false) == .cliMissing, "doctor cli")
    expect(Doctor.classify(cliFound: true, signedIn: false, probe: nil, agentCrashed: false) == .auth, "doctor auth")
    expect(Doctor.classify(cliFound: true, signedIn: true, probe: .dns, agentCrashed: false) == .network, "doctor network")
    expect(Doctor.classify(cliFound: true, signedIn: true, probe: .ok, agentCrashed: true) == .agentCrash, "doctor crash")
    expect(!Doctor.report(kind: .network, detail: "api_key=sk-live-secret").contains("sk-live-secret"), "doctor report redacts")
    let httpProxy = ProxyInject.environment(base: [:], proxy: "http://127.0.0.1:9")
    expect(httpProxy["HTTP_PROXY"] == "http://127.0.0.1:9" && httpProxy["HTTPS_PROXY"] == "http://127.0.0.1:9", "http proxy")
    expect(ProxyInject.environment(base: [:], proxy: "socks5://127.0.0.1:9")["ALL_PROXY"] == "socks5://127.0.0.1:9", "socks proxy")
    attempt("usage") {
        let ledger = parityRoot.appendingPathComponent("usage-ledger.json")
        UsageLedger.record(provider: "custom", at: Date(), url: ledger)
        let cells = UsageHeatmap.cells(timestamps: UsageLedger.timestamps(url: ledger), now: Date(), days: 7)
        expect(cells.contains { $0.count == 1 }, "usage heatmap")
        expect(UsageHeatmap.quota(used: 1, limit: 2) == 0.5, "quota fraction")
    }
    expect(AutomationDraft.parse("check mail tomorrow").prompt.contains("/loop 1d"), "daily automation")
    expect(AutomationDraft.parse("every hour check").prompt.contains("/loop 1h"), "hourly automation")
    let toggled = ExtensionToggles.set([], kind: "hook", name: "format", enabled: false)
    expect(ExtensionToggles.isEnabled([], kind: "hook", name: "format"), "extensions default on")
    expect(!ExtensionToggles.isEnabled(toggled, kind: "hook", name: "format"), "extension can be disabled")
    let slots = [AccountSlot(id: "work", label: "Work")]
    expect(AccountSwitch.select(slots: slots, id: "missing", active: "work") == "work", "unknown account stays")
    expect(AccountSwitch.select(slots: slots, id: "work", active: "") == "work", "known account switches")
    print("pass redact")

    expect(CompanionDesk.phase(turnRunning: false, needsPermission: true, needsQuestion: false, unseen: false) == .needsInput, "companion needs input")
    expect(CompanionDesk.phase(turnRunning: true, needsPermission: false, needsQuestion: false, unseen: false) == .working, "companion working")
    expect(CompanionDesk.phase(turnRunning: false, needsPermission: false, needsQuestion: false, unseen: true) == .done, "companion done")
    expect(CompanionDesk.phase(turnRunning: false, needsPermission: false, needsQuestion: false, unseen: false) == .idle, "companion idle")
    expect(CompanionDesk.apply(.dictate("  hello "), draft: "", turnRunning: false) == .draft("hello"), "dictate")
    expect(CompanionDesk.apply(.send, draft: " go ", turnRunning: true) == .send("go"), "send")
    expect(CompanionDesk.apply(.stop, draft: "go", turnRunning: true) == .stop, "stop")
    expect(CompanionDesk.apply(.stop, draft: "go", turnRunning: false) == .ignore, "stop waits for a turn")
    print("pass companion")

    let localeKeys = LocaleCatalog.navigationKeys + LocaleCatalog.settingsKeys + LocaleCatalog.errorKeys + LocaleCatalog.firstRunKeys
    for languageID in LocaleCatalog.languageIDs {
        for key in localeKeys {
            expect(!LocaleCatalog.string(key, languageID: languageID).isEmpty, "\(languageID) \(key.rawValue)")
        }
    }
    expect(LocaleCatalog.resolve(preference: "system", preferredLanguages: ["tr-TR"]) == "tr", "turkish locale")
    expect(LocaleCatalog.resolve(preference: nil, preferredLanguages: ["zh-TW"]) == "zh-Hant", "traditional chinese locale")
    expect(LocaleCatalog.languageIDs.count == 16, "language table")
    expect(ShellLocale.chrome(.navSettings, preference: "ja", preferredLanguages: ["en"]) == "設定", "japanese settings nav")
    expect(ShellLocale.chrome(.navChat, preference: "ja", preferredLanguages: ["en"]) == "Chat", "product chat stays")
    expect(ShellLocale.chrome(.navBuild, preference: "ja", preferredLanguages: ["en"]) == "Build", "product build stays")
    expect(ShellLocale.chrome(.settingsAccount, preference: "ja", preferredLanguages: []) == "アカウント", "japanese account")
    expect(ShellLocale.chrome(.settingsTitle, preference: "ja", preferredLanguages: []) == "設定", "japanese settings title")
    expect(ShellLocale.chrome(.errorCLI, preference: "ja", preferredLanguages: []) == "grok が見つかりません。", "japanese missing cli")
    expect(ShellLocale.chrome(.firstRunTitle, preference: "ja", preferredLanguages: []) == "初期設定", "japanese first run")
    expect(ShellLocale.chrome(.firstRunBody, preference: "ja", preferredLanguages: []) == "grok をインストールするか、実行ファイルを指定します。", "japanese first run body")
    print("pass locale")
}

private final class ParitySignal: @unchecked Sendable {
    var id = ""
    var text = ""
}

private func parityLog(_ root: URL) -> String {
    (try? String(contentsOf: root.appendingPathComponent("rpc.log"), encoding: .utf8)) ?? ""
}

private func parityWait(_ seconds: TimeInterval = 20, _ body: @escaping @MainActor () async throws -> Void) {
    let sem = DispatchSemaphore(value: 0)
    let box = ParitySignal()
    Task { @MainActor in
        do {
            try await body()
        } catch {
            box.text = "\(error)"
        }
        sem.signal()
    }
    let deadline = Date().addingTimeInterval(seconds)
    while sem.wait(timeout: .now() + 0.05) == .timedOut {
        if Date() > deadline {
            fail("parity wait timed out")
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    if !box.text.isEmpty {
        fail(box.text)
    }
}

private func parityUntil(_ seconds: TimeInterval, _ check: @MainActor () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if check() { return }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

private func parityInstallStub(at root: URL) throws -> URL {
    let fm = FileManager.default
    let binDir = root.appendingPathComponent("bin", isDirectory: true)
    try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
    let url = binDir.appendingPathComponent("grok")
    try parityStubSource.write(to: url, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private func parityLocator(_ bin: URL) -> GrokBinaryLocator {
    let path = bin.standardizedFileURL.path
    return GrokBinaryLocator(
        extraSearchPaths: [],
        pathEnvironment: bin.deletingLastPathComponent().path,
        fileExists: { $0.standardizedFileURL.path == path }
    )
}

private let parityStubSource = """
#!/usr/bin/env python3
import json, os, sys
if "--version" in sys.argv:
    print("0.test")
    raise SystemExit(0)
base = os.path.dirname(os.path.abspath(sys.argv[0]))
root = os.path.dirname(base)
with open(os.path.join(root, "env.log"), "w") as handle:
    handle.write(os.environ.get("GROK_HOME", ""))
def log(line):
    with open(os.path.join(root, "rpc.log"), "a") as handle:
        handle.write(line + "\\n")
permission = os.path.exists(os.path.join(root, "permission.on"))
while True:
    raw = sys.stdin.readline()
    if raw == "":
        break
    line = raw.strip()
    if not line:
        continue
    log(line)
    try:
        msg = json.loads(line)
    except Exception:
        continue
    mid = msg.get("id")
    method = msg.get("method")
    if method == "initialize":
        if permission:
            req = {"jsonrpc":"2.0","id":9001,"method":"session/request_permission","params":{"sessionId":"s","title":"write file","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},{"optionId":"reject","name":"Reject","kind":"reject"}]}}
            sys.stdout.write(json.dumps(req) + "\\n")
            sys.stdout.flush()
        sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":1}}) + "\\n")
        sys.stdout.flush()
    elif method in ("session/new", "session/load"):
        sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"sessionId":"sess-1"}}) + "\\n")
        sys.stdout.flush()
    elif method == "session/prompt":
        sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"stopReason":"end_turn"}}) + "\\n")
        sys.stdout.flush()
    elif mid is not None and method:
        sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,"result":{}}) + "\\n")
        sys.stdout.flush()
"""
