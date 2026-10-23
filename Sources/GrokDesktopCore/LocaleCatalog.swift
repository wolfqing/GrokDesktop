import Foundation

public enum LocaleKey: String, CaseIterable, Sendable {
    case navChat
    case navBuild
    case navSettings
    case settingsTitle
    case settingsAccount
    case settingsAppearance
    case errorGeneric
    case errorCLI
    case firstRunTitle
    case firstRunBody
}

public enum LocaleCatalog {
    public static let languageIDs = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "ru",
        "es", "pt-BR", "it", "id", "ta", "uk", "fil", "tr"
    ]

    public static let navigationKeys: [LocaleKey] = [.navChat, .navBuild, .navSettings]
    public static let settingsKeys: [LocaleKey] = [.settingsTitle, .settingsAccount, .settingsAppearance]
    public static let errorKeys: [LocaleKey] = [.errorGeneric, .errorCLI]
    public static let firstRunKeys: [LocaleKey] = [.firstRunTitle, .firstRunBody]

    public static func endonym(_ id: String) -> String {
        switch id {
        case "en": return "English"
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "de": return "Deutsch"
        case "fr": return "Français"
        case "ru": return "Русский"
        case "es": return "Español"
        case "pt-BR": return "Português (Brasil)"
        case "it": return "Italiano"
        case "id": return "Bahasa Indonesia"
        case "ta": return "தமிழ்"
        case "uk": return "Українська"
        case "fil": return "Filipino"
        case "tr": return "Türkçe"
        default: return id
        }
    }

    public static func resolve(preference: String?, preferredLanguages: [String]) -> String {
        let raw = preference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty, raw != "system", languageIDs.contains(raw) { return raw }
        return match(preferredLanguages) ?? "en"
    }

    /// Maps a desk locale onto a speech-recognizer identifier.
    public static func speechIdentifier(preference: String?, preferredLanguages: [String]) -> String {
        switch resolve(preference: preference, preferredLanguages: preferredLanguages) {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "pt-BR": return "pt-BR"
        case "fil": return "fil-PH"
        case "en": return "en-US"
        case let id: return id
        }
    }

    public static func string(_ key: LocaleKey, languageID: String) -> String {
        let id = languageIDs.contains(languageID) ? languageID : "en"
        return table[id]?[key] ?? table["en"]?[key] ?? ""
    }

    public static func string(_ key: LocaleKey, preference: String?, preferredLanguages: [String]) -> String {
        string(key, languageID: resolve(preference: preference, preferredLanguages: preferredLanguages))
    }

    private static func match(_ languages: [String]) -> String? {
        for language in languages {
            let lower = language.lowercased().replacingOccurrences(of: "_", with: "-")
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") || lower.hasPrefix("zh-mo") {
                return "zh-Hant"
            }
            if lower.hasPrefix("zh") { return "zh-Hans" }
            if lower.hasPrefix("pt") { return "pt-BR" }
            if lower.hasPrefix("fil") || lower.hasPrefix("tl") { return "fil" }
            if lower.hasPrefix("ja") { return "ja" }
            if lower.hasPrefix("ko") { return "ko" }
            if lower.hasPrefix("de") { return "de" }
            if lower.hasPrefix("fr") { return "fr" }
            if lower.hasPrefix("ru") { return "ru" }
            if lower.hasPrefix("es") { return "es" }
            if lower.hasPrefix("it") { return "it" }
            if lower.hasPrefix("id") { return "id" }
            if lower.hasPrefix("ta") { return "ta" }
            if lower.hasPrefix("uk") { return "uk" }
            if lower.hasPrefix("tr") { return "tr" }
            if lower.hasPrefix("en") { return "en" }
        }
        return nil
    }

    private static let table: [String: [LocaleKey: String]] = [
        "en": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Settings",
            .settingsTitle: "Settings", .settingsAccount: "Account", .settingsAppearance: "Appearance",
            .errorGeneric: "Something went wrong.", .errorCLI: "The grok CLI is missing.",
            .firstRunTitle: "Set up Grok Desktop", .firstRunBody: "Install the grok CLI, or choose the binary yourself."
        ],
        "zh-Hans": [
            .navChat: "对话", .navBuild: "构建", .navSettings: "设置",
            .settingsTitle: "设置", .settingsAccount: "账号", .settingsAppearance: "外观",
            .errorGeneric: "出了点问题。", .errorCLI: "找不到 grok 命令行。",
            .firstRunTitle: "开始使用", .firstRunBody: "安装 grok，或手动指定程序路径。"
        ],
        "zh-Hant": [
            .navChat: "對話", .navBuild: "建置", .navSettings: "設定",
            .settingsTitle: "設定", .settingsAccount: "帳號", .settingsAppearance: "外觀",
            .errorGeneric: "發生問題。", .errorCLI: "找不到 grok 命令列。",
            .firstRunTitle: "開始使用", .firstRunBody: "安裝 grok，或手動指定程式路徑。"
        ],
        "ja": [
            .navChat: "チャット", .navBuild: "ビルド", .navSettings: "設定",
            .settingsTitle: "設定", .settingsAccount: "アカウント", .settingsAppearance: "外観",
            .errorGeneric: "問題が起きました。", .errorCLI: "grok が見つかりません。",
            .firstRunTitle: "初期設定", .firstRunBody: "grok をインストールするか、実行ファイルを指定します。"
        ],
        "ko": [
            .navChat: "채팅", .navBuild: "빌드", .navSettings: "설정",
            .settingsTitle: "설정", .settingsAccount: "계정", .settingsAppearance: "모양",
            .errorGeneric: "문제가 발생했습니다.", .errorCLI: "grok 명령을 찾을 수 없습니다.",
            .firstRunTitle: "시작 설정", .firstRunBody: "grok를 설치하거나 실행 파일을 지정하세요."
        ],
        "de": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Einstellungen",
            .settingsTitle: "Einstellungen", .settingsAccount: "Konto", .settingsAppearance: "Darstellung",
            .errorGeneric: "Etwas ist schiefgelaufen.", .errorCLI: "Die grok-CLI fehlt.",
            .firstRunTitle: "Einrichtung", .firstRunBody: "Installiere die grok-CLI oder wähle die Datei selbst."
        ],
        "fr": [
            .navChat: "Discussion", .navBuild: "Build", .navSettings: "Réglages",
            .settingsTitle: "Réglages", .settingsAccount: "Compte", .settingsAppearance: "Apparence",
            .errorGeneric: "Quelque chose s'est mal passé.", .errorCLI: "La commande grok est absente.",
            .firstRunTitle: "Première étape", .firstRunBody: "Installez grok ou indiquez le fichier vous-même."
        ],
        "ru": [
            .navChat: "Чат", .navBuild: "Сборка", .navSettings: "Настройки",
            .settingsTitle: "Настройки", .settingsAccount: "Аккаунт", .settingsAppearance: "Оформление",
            .errorGeneric: "Что-то пошло не так.", .errorCLI: "Команда grok не найдена.",
            .firstRunTitle: "Начало работы", .firstRunBody: "Установите grok или укажите файл вручную."
        ],
        "es": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Ajustes",
            .settingsTitle: "Ajustes", .settingsAccount: "Cuenta", .settingsAppearance: "Apariencia",
            .errorGeneric: "Algo salió mal.", .errorCLI: "Falta el comando grok.",
            .firstRunTitle: "Puesta en marcha", .firstRunBody: "Instala grok o elige el archivo tú mismo."
        ],
        "pt-BR": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Ajustes",
            .settingsTitle: "Ajustes", .settingsAccount: "Conta", .settingsAppearance: "Aparência",
            .errorGeneric: "Algo deu errado.", .errorCLI: "O comando grok não está instalado.",
            .firstRunTitle: "Primeiros passos", .firstRunBody: "Instale o grok ou escolha o arquivo manualmente."
        ],
        "it": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Impostazioni",
            .settingsTitle: "Impostazioni", .settingsAccount: "Account", .settingsAppearance: "Aspetto",
            .errorGeneric: "Qualcosa è andato storto.", .errorCLI: "Manca il comando grok.",
            .firstRunTitle: "Per iniziare", .firstRunBody: "Installa grok oppure scegli il file a mano."
        ],
        "id": [
            .navChat: "Obrolan", .navBuild: "Build", .navSettings: "Pengaturan",
            .settingsTitle: "Pengaturan", .settingsAccount: "Akun", .settingsAppearance: "Tampilan",
            .errorGeneric: "Ada yang salah.", .errorCLI: "Perintah grok tidak ada.",
            .firstRunTitle: "Mulai", .firstRunBody: "Pasang grok atau pilih berkasnya sendiri."
        ],
        "ta": [
            .navChat: "அரட்டை", .navBuild: "உருவாக்கம்", .navSettings: "அமைப்புகள்",
            .settingsTitle: "அமைப்புகள்", .settingsAccount: "கணக்கு", .settingsAppearance: "தோற்றம்",
            .errorGeneric: "ஏதோ தவறு நடந்தது.", .errorCLI: "grok கட்டளை கிடைக்கவில்லை.",
            .firstRunTitle: "தொடக்கம்", .firstRunBody: "grok-ஐ நிறுவவும் அல்லது கோப்பைத் தேர்ந்தெடுக்கவும்."
        ],
        "uk": [
            .navChat: "Чат", .navBuild: "Збірка", .navSettings: "Параметри",
            .settingsTitle: "Параметри", .settingsAccount: "Обліковий запис", .settingsAppearance: "Вигляд",
            .errorGeneric: "Сталася помилка.", .errorCLI: "Немає команди grok.",
            .firstRunTitle: "Початок", .firstRunBody: "Встановіть grok або вкажіть файл."
        ],
        "fil": [
            .navChat: "Chat", .navBuild: "Build", .navSettings: "Mga setting",
            .settingsTitle: "Mga setting", .settingsAccount: "Account", .settingsAppearance: "Hitsura",
            .errorGeneric: "May nangyaring mali.", .errorCLI: "Walang grok CLI.",
            .firstRunTitle: "Unang hakbang", .firstRunBody: "I-install ang grok o piliin ang binary."
        ],
        "tr": [
            .navChat: "Sohbet", .navBuild: "Derleme", .navSettings: "Ayarlar",
            .settingsTitle: "Ayarlar", .settingsAccount: "Hesap", .settingsAppearance: "Görünüm",
            .errorGeneric: "Bir şeyler ters gitti.", .errorCLI: "grok komutu yok.",
            .firstRunTitle: "Kurulum", .firstRunBody: "grok'u kurun veya dosyayı seçin."
        ]
    ]
}
