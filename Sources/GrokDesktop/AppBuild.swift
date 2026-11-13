import Foundation
import GrokDesktopCore

enum AppBuild {
    /// Version baked into the running bundle. `swift run` has no Info.plist, so it falls back.
    static var marketingVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let version = AppVersion(parsing: trimmed) {
            return version.raw
        }
        return "0.1.34"
    }

    static var version: AppVersion {
        AppVersion(parsing: marketingVersion) ?? AppVersion(parsing: "0.1.34")!
    }
}
