import Foundation

public enum MediaPathScope {
    public static func allows(
        path: String,
        trustedRoots: [String],
        appData: String,
        temp: String,
        grants: [String]
    ) -> Bool {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        if isSecret(standard) { return false }
        let roots = trustedRoots + [appData, temp] + grants
        return roots.contains { isInside(standard, root: URL(fileURLWithPath: $0).standardizedFileURL.path) }
    }

    public static func isSecret(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if url.pathComponents.contains(".ssh") { return true }
        let blocked = [
            "secrets.json", ".env", "credentials.json", ".netrc",
            "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"
        ]
        return blocked.contains(url.lastPathComponent)
    }

    private static func isInside(_ path: String, root: String) -> Bool {
        if root.isEmpty { return false }
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }
}
