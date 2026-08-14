import AppKit
import UniformTypeIdentifiers

@MainActor
enum ChatLinkActions {
    static func open(_ url: URL) {
        if url.isFileURL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                NSWorkspace.shared.open(url)
                return
            }
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parent])
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func open(_ url: URL, with appURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    static func reveal(_ url: URL) {
        if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                let parent = url.deletingLastPathComponent()
                NSWorkspace.shared.open(parent)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func copy(_ url: URL) {
        let value = url.isFileURL ? url.path : url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    static func chooseApp(for url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let app = panel.url else { return }
        open(url, with: app)
    }

    static func applications(for url: URL) -> [URL] {
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if apps.isEmpty, url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) {
            apps = NSWorkspace.shared.urlsForApplications(toOpen: type)
        }
        if apps.isEmpty, url.scheme == "http" || url.scheme == "https",
           let web = URL(string: "https://example.com") {
            apps = NSWorkspace.shared.urlsForApplications(toOpen: web)
        }
        var seen = Set<String>()
        return apps.filter { seen.insert($0.path.lowercased()).inserted }
    }

    static func defaultApplication(for url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    static func appName(_ appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    static func menu(for url: URL, chinese: Bool) -> NSMenu {
        let controller = ChatLinkMenuController(url: url)
        let menu = ChatLinkMenu()
        menu.controller = controller
        menu.autoenablesItems = false

        func item(_ en: String, _ zh: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: chinese ? zh : en, action: action, keyEquivalent: "")
            item.target = controller
            return item
        }

        menu.addItem(item("Open", "打开", #selector(ChatLinkMenuController.open)))

        let apps = applications(for: url)
        if !apps.isEmpty {
            let submenu = NSMenu()
            let defaultApp = defaultApplication(for: url)
            for app in apps.prefix(12) {
                let name = appName(app)
                let title: String
                if app.path == defaultApp?.path {
                    title = chinese ? "\(name)（默认）" : "\(name) (Default)"
                } else {
                    title = name
                }
                let appItem = NSMenuItem(title: title, action: #selector(ChatLinkMenuController.openWith(_:)), keyEquivalent: "")
                appItem.target = controller
                appItem.representedObject = app
                submenu.addItem(appItem)
            }
            submenu.addItem(.separator())
            let other = NSMenuItem(title: chinese ? "其他…" : "Other…", action: #selector(ChatLinkMenuController.chooseApp), keyEquivalent: "")
            other.target = controller
            submenu.addItem(other)

            let openWith = NSMenuItem(title: chinese ? "打开方式" : "Open With", action: nil, keyEquivalent: "")
            menu.addItem(openWith)
            menu.setSubmenu(submenu, for: openWith)
        } else {
            menu.addItem(item("Open With…", "打开方式…", #selector(ChatLinkMenuController.chooseApp)))
        }

        if url.isFileURL {
            menu.addItem(item("Show in Finder", "在 Finder 中显示", #selector(ChatLinkMenuController.reveal)))
        }
        menu.addItem(.separator())
        menu.addItem(item(url.isFileURL ? "Copy Path" : "Copy Link", url.isFileURL ? "复制路径" : "复制链接", #selector(ChatLinkMenuController.copyLink)))
        return menu
    }
}

@MainActor
final class ChatLinkMenu: NSMenu {
    var controller: ChatLinkMenuController?
}

@MainActor
final class ChatLinkMenuController: NSObject {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    @objc func open() {
        ChatLinkActions.open(url)
    }

    @objc func reveal() {
        ChatLinkActions.reveal(url)
    }

    @objc func copyLink() {
        ChatLinkActions.copy(url)
    }

    @objc func chooseApp() {
        ChatLinkActions.chooseApp(for: url)
    }

    @objc func openWith(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        ChatLinkActions.open(url, with: app)
    }
}
