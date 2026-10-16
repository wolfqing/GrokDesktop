import AppKit
import Foundation
import GrokDesktopCore

enum AppUpdateNotice: Equatable {
    case downloading(String)
    case ready(String)
    case moveToApplications
    case failed(AppUpdateFailure)
}

enum AppUpdateDefaults {
    nonisolated static let installErrorKey = "appUpdateInstallError"
}

/// Checks GitHub Releases, downloads a newer zip, and swaps it in on the next launch.
@MainActor
final class AppUpdateCenter {
    private weak var model: AppModel?
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var lastCheck: Date?
    private var installing = false
    private let cache = AppUpdateCache(root: AppUpdateCache.defaultRoot())

    func start(model: AppModel) {
        guard Self.monitoringEnabled else { return }
        self.model = model
        if let raw = UserDefaults.standard.string(forKey: AppUpdateDefaults.installErrorKey),
           let failure = AppUpdateFailure(rawValue: raw) {
            UserDefaults.standard.removeObject(forKey: AppUpdateDefaults.installErrorKey)
            model.appUpdateNotice = .failed(failure)
            model.appUpdateFailure = failure
        }
        if let destination = RunningApp.bundleURL() {
            AppUpdateInstaller.removeIncoming(beside: destination)
        }
        adoptStagedUpdate()
        let timer = Timer(timeInterval: AppUpdateFeed.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check(userInitiated: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkIfStale()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.check(userInitiated: false)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.removePreviousBundle()
        }
    }

    func check(userInitiated: Bool) {
        guard Self.monitoringEnabled else { return }
        if checkTask != nil || downloadTask != nil { return }
        lastCheck = Date()
        model?.appUpdateChecking = true
        let current = AppBuild.version
        checkTask = Task { [weak self] in
            let outcome = await Self.fetch(current: current)
            guard let self else { return }
            self.checkTask = nil
            self.model?.appUpdateChecking = false
            self.apply(outcome, userInitiated: userInitiated)
        }
    }

    func installDownloadedUpdate() {
        guard !installing else { return }
        guard case .ready(let raw) = model?.appUpdateNotice, let version = AppVersion(parsing: raw) else { return }
        guard let destination = RunningApp.bundleURL(), RunningApp.blocker(appURL: destination) == nil else {
            model?.appUpdateNotice = .moveToApplications
            return
        }
        guard let staged = cache.verifiedApp(version: version) else {
            model?.appUpdateNotice = .failed(.badArchive)
            model?.appUpdateFailure = .badArchive
            return
        }
        installing = true
        do {
            try AppUpdateInstaller.swap(stagedApp: staged, destination: destination)
        } catch {
            installing = false
            model?.appUpdateNotice = .failed(.installFailed)
            model?.appUpdateFailure = .installFailed
            return
        }
        cache.clear()
        relaunch(destination)
    }

    private func checkIfStale() {
        guard let lastCheck else { return }
        if Date().timeIntervalSince(lastCheck) >= AppUpdateFeed.checkInterval {
            check(userInitiated: false)
        }
    }

    private func apply(_ outcome: FetchOutcome, userInitiated: Bool) {
        switch outcome {
        case .upToDate(let latest):
            model?.appUpdateLatest = latest
            model?.appUpdateFailure = nil
            if case .ready = model?.appUpdateNotice {
                cache.clear()
            }
            switch model?.appUpdateNotice {
            case .failed, .ready, .moveToApplications:
                model?.appUpdateNotice = nil
            case .downloading, .none:
                break
            }
        case .download(let release):
            model?.appUpdateLatest = release.version.raw
            model?.appUpdateFailure = nil
            if cache.verifiedApp(version: release.version) != nil {
                model?.appUpdateNotice = .ready(release.version.raw)
                return
            }
            guard let destination = RunningApp.bundleURL() else { return }
            if RunningApp.blocker(appURL: destination) != nil {
                model?.appUpdateNotice = .moveToApplications
                return
            }
            download(release)
        case .failed(let failure):
            model?.appUpdateFailure = failure
            if case .ready = model?.appUpdateNotice { return }
            if case .downloading = model?.appUpdateNotice { return }
            if userInitiated {
                model?.appUpdateNotice = .failed(failure)
            }
        }
    }

    private func download(_ release: AppRelease) {
        model?.appUpdateNotice = .downloading(release.version.raw)
        let cache = self.cache
        downloadTask = Task { [weak self] in
            let failure = await Task.detached(priority: .utility) {
                Self.prepare(release, cache: cache)
            }.value
            guard let self else { return }
            self.downloadTask = nil
            if let failure {
                self.model?.appUpdateNotice = .failed(failure)
                self.model?.appUpdateFailure = failure
            } else {
                self.model?.appUpdateFailure = nil
                self.model?.appUpdateNotice = .ready(release.version.raw)
            }
        }
    }

    private func adoptStagedUpdate() {
        guard let staged = cache.load(), let version = AppVersion(parsing: staged.version) else { return }
        if version <= AppBuild.version {
            cache.clear()
            return
        }
        guard cache.verifiedApp(version: version) != nil else {
            cache.clear()
            return
        }
        model?.appUpdateLatest = version.raw
        model?.appUpdateNotice = .ready(version.raw)
    }

    private func removePreviousBundle() {
        guard let destination = RunningApp.bundleURL() else { return }
        AppUpdateInstaller.removePrevious(beside: destination)
    }

    private func relaunch(_ destination: URL) {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = [destination.path]
        do {
            try opener.run()
        } catch {
            model?.appUpdateNotice = .failed(.installFailed)
            model?.appUpdateFailure = .installFailed
            installing = false
            return
        }
        exit(0)
    }

    private static var monitoringEnabled: Bool {
        if DemoStudio.isEnabled { return false }
        if ProcessInfo.processInfo.environment["GROK_DESKTOP_NO_UPDATE"] == "1" { return false }
        return RunningApp.bundleURL() != nil
    }

    nonisolated private static func fetch(current: AppVersion) async -> FetchOutcome {
        var request = URLRequest(url: AppUpdateFeed.latestReleaseURL)
        request.setValue("GrokDesktop/\(current.raw)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed(.unavailable)
            }
            switch AppUpdateFeed.parseLatest(data, current: current) {
            case .success(.upToDate):
                return .upToDate(latest: current.raw)
            case .success(.download(let release)):
                return .download(release)
            case .failure(let failure):
                return .failed(failure)
            }
        } catch {
            return .failed(.unavailable)
        }
    }

    /// Returns a failure, or nil when the zip is staged and verified.
    nonisolated private static func prepare(_ release: AppRelease, cache: AppUpdateCache) -> AppUpdateFailure? {
        let files = FileManager.default
        do {
            try files.createDirectory(at: cache.root, withIntermediateDirectories: true)
        } catch {
            return .badArchive
        }
        let zip = cache.zipURL(version: release.version)
        if files.fileExists(atPath: zip.path), AppUpdateInstaller.looksLikeZip(zip),
           AppUpdateInstaller.stage(zip: zip, version: release.version, cache: cache) != nil {
            removeOtherArchives(in: cache, keeping: release.version)
            return nil
        }
        try? files.removeItem(at: zip)
        let partial = cache.partialURL(version: release.version)
        try? files.removeItem(at: partial)
        let downloader = ZipDownloader(destination: partial)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: release.zipURL)
        request.setValue("GrokDesktop/\(release.version.raw)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let task = session.downloadTask(with: request)
        task.resume()
        let downloadError = downloader.wait()
        if downloader.rejected {
            try? files.removeItem(at: partial)
            return .untrusted
        }
        if downloadError != nil {
            try? files.removeItem(at: partial)
            return .unavailable
        }
        guard let finalURL = downloader.response?.url, AppUpdateFeed.isTrustedRedirect(finalURL) else {
            try? files.removeItem(at: partial)
            return .untrusted
        }
        guard let http = downloader.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? files.removeItem(at: partial)
            return .unavailable
        }
        let size = (try? files.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= AppUpdateFeed.maxZipBytes else {
            try? files.removeItem(at: partial)
            return .tooLarge
        }
        do {
            try files.moveItem(at: partial, to: zip)
        } catch {
            return .badArchive
        }
        guard AppUpdateInstaller.looksLikeZip(zip),
              AppUpdateInstaller.stage(zip: zip, version: release.version, cache: cache) != nil
        else {
            try? files.removeItem(at: zip)
            return .badArchive
        }
        removeOtherArchives(in: cache, keeping: release.version)
        return nil
    }

    nonisolated private static func removeOtherArchives(in cache: AppUpdateCache, keeping version: AppVersion) {
        let keep = cache.zipURL(version: version).lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cache.root,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("Grok-Desktop-") && file.lastPathComponent != keep {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private enum FetchOutcome: Sendable {
    case upToDate(latest: String)
    case download(AppRelease)
    case failed(AppUpdateFailure)
}

/// Moves the zip out of the system temp file before that file is deleted.
private final class ZipDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var rejectedRedirect = false
    private var finishedResponse: URLResponse?
    private var finishedError: Error?

    init(destination: URL) {
        self.destination = destination
    }

    var rejected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejectedRedirect
    }

    var response: URLResponse? {
        lock.lock()
        defer { lock.unlock() }
        return finishedResponse
    }

    func wait() -> Error? {
        let timeout = semaphore.wait(timeout: .now() + 180)
        lock.lock()
        let error = finishedError
        lock.unlock()
        if timeout == .timedOut { return URLError(.timedOut) }
        return error
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, AppUpdateFeed.isTrustedRedirect(url) else {
            lock.lock()
            rejectedRedirect = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.lock()
            finishedError = error
            lock.unlock()
        }
        lock.lock()
        finishedResponse = downloadTask.response
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if finishedResponse == nil {
            finishedResponse = task.response
        }
        if finishedError == nil {
            finishedError = error
        }
        lock.unlock()
        semaphore.signal()
    }
}

enum AppUpdateLaunch {
    /// If a verified newer bundle is already staged, swap it in before the window opens.
    static func installStagedAndRelaunchIfNeeded() {
        guard ProcessInfo.processInfo.environment["GROK_DESKTOP_NO_UPDATE"] != "1" else { return }
        guard !DemoStudio.isEnabled else { return }
        guard let destination = RunningApp.bundleURL() else { return }
        guard RunningApp.blocker(appURL: destination) == nil else { return }
        let cache = AppUpdateCache(root: AppUpdateCache.defaultRoot())
        guard let staged = cache.load(), let version = AppVersion(parsing: staged.version) else { return }
        if version <= AppBuild.version {
            cache.clear()
            return
        }
        guard let app = cache.verifiedApp(version: version) else {
            cache.clear()
            return
        }
        AppUpdateInstaller.removeIncoming(beside: destination)
        do {
            try AppUpdateInstaller.swap(stagedApp: app, destination: destination)
        } catch {
            UserDefaults.standard.set(AppUpdateFailure.installFailed.rawValue, forKey: AppUpdateDefaults.installErrorKey)
            return
        }
        cache.clear()
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = [destination.path]
        try? opener.run()
        exit(0)
    }
}
