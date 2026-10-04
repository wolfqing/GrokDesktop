import AppKit
import SwiftTerm

/// Interactive shell for the right sidebar. The view is owned here so SwiftUI
/// redraws do not tear down the pseudo-terminal.
@MainActor
final class SidebarShell {
    let view: LocalProcessTerminalView
    private(set) var directory = ""
    private var startedFor = ""
    private var generation = 0
    private var appliedDark: Bool?
    private let container = SidebarTerminalContainer()

    init() {
        view = LocalProcessTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.caretViewTracksFocus = true
        view.focusRingType = .none
        container.embed(view)
        container.onLayout = { [weak self] in
            self?.startIfNeeded()
        }
    }

    func hostView() -> NSView { container }

    func apply(isDark: Bool) {
        guard appliedDark != isDark else { return }
        appliedDark = isDark
        let background = isDark
            ? NSColor(srgbRed: 0.043, green: 0.043, blue: 0.043, alpha: 1)
            : NSColor(srgbRed: 0.965, green: 0.965, blue: 0.965, alpha: 1)
        let foreground = isDark
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.08, alpha: 1)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = foreground
        view.caretColor = foreground
        view.selectedTextBackgroundColor = isDark
            ? NSColor(white: 0.28, alpha: 1)
            : NSColor(white: 0.78, alpha: 1)
        view.selectedTextForegroundColor = foreground
        container.layer?.backgroundColor = background.cgColor
    }

    func sync(directory: String, isDark: Bool) {
        apply(isDark: isDark)
        let path = Self.standardized(directory)
        guard path != self.directory || startedFor != path else { return }
        self.directory = path
        startIfNeeded()
    }

    func restart(directory: String) {
        self.directory = Self.standardized(directory)
        startedFor = ""
        startIfNeeded(force: true)
    }

    private func startIfNeeded(force: Bool = false) {
        let path = directory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : directory
        directory = path
        guard force || startedFor != path else { return }
        guard view.bounds.width >= 40 else { return }
        generation += 1
        let token = generation
        startedFor = path
        view.terminal.resetToInitialState()
        if view.process.running {
            view.terminate()
        }
        Task { @MainActor in
            for _ in 0..<60 {
                if token != self.generation { return }
                if !self.view.process.running { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard token == self.generation, !self.view.process.running else { return }
            self.view.startProcess(
                executable: Self.shellExecutable(),
                args: ["-i"],
                environment: Self.environment(),
                currentDirectory: path
            )
        }
    }

    private static func standardized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private static func shellExecutable() -> String {
        let preferred = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if FileManager.default.isExecutableFile(atPath: preferred) {
            return preferred
        }
        return "/bin/zsh"
    }

    private static func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }
}

final class SidebarTerminalContainer: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    func embed(_ terminal: NSView) {
        wantsLayer = true
        guard terminal.superview !== self else { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private var announcedSize = false

    override func layout() {
        super.layout()
        guard bounds.width >= 40, !announcedSize else { return }
        announcedSize = true
        DispatchQueue.main.async { [weak self] in
            self?.onLayout?()
        }
    }
}
