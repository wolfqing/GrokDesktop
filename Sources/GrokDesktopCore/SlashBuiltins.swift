import Foundation

public enum SlashBuiltins {
    public static let names: Set<String> = [
        "/new", "/clear",
        "/settings", "/config", "/prefs", "/preferences",
        "/dashboard", "/sessions", "/agents-dashboard",
        "/home", "/welcome",
        "/resume", "/continue",
        "/history",
        "/rename", "/title",
        "/delete",
        "/export",
        "/copy",
        "/fork",
        "/plan",
        "/view-plan", "/show-plan", "/plan-view",
        "/jump", "/timeline", "/find",
        "/rewind", "/undo",
        "/compact",
        "/model", "/m",
        "/effort",
        "/always-approve",
        "/auto",
        "/multiline", "/ml",
        "/compact-mode",
        "/timestamps",
        "/theme", "/t",
        "/feedback",
        "/logout", "/login",
        "/context", "/session-info", "/status", "/info",
        "/docs", "/howto", "/guides",
        "/changelog", "/release-notes",
        "/tutorial", "/tour", "/onboarding",
        "/imagine", "/imagine-video",
        "/usage", "/cost",
        "/privacy",
        "/skills",
        "/hooks", "/hooks-list", "/hooks-trust", "/hooks-add", "/hooks-remove", "/hooks-untrust",
        "/plugins",
        "/marketplace",
        "/mcps",
        "/workflows", "/workflow",
        "/agents", "/config-agents", "/personas",
        "/doctor", "/terminal-setup", "/terminal-check", "/terminal-info",
        "/inspect",
        "/du", "/disk-usage",
        "/models",
        "/memory", "/mem",
        "/remember", "/flush", "/dream",
        "/loop", "/goal", "/deep-research", "/btw",
        "/import-claude",
        "/worktree",
        "/update",
        "/shortcuts", "/keys",
        "/vim-mode", "/minimal", "/fullscreen", "/full", "/edit-prompt", "/expand",
        "/quit", "/exit"
    ]

    public static func name(in raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first ?? "")
            .lowercased()
    }

    public static func handles(_ raw: String) -> Bool {
        names.contains(name(in: raw))
    }
}
