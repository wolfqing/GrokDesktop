import Foundation

/// UI copy for the locales the shell can select. English and Simplified Chinese
/// stay at the call site. Traditional Chinese is converted. Other locales come
/// from the generated table and fall back to English.
public enum PhraseBook {
    public static func translate(_ en: String, zh: String, locale: String) -> String {
        if en == zh { return en }
        switch locale {
        case "", "en":
            return en
        case "zh-Hans":
            return zh
        case "zh-Hant":
            return zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh
        default:
            return PhraseTable.text(en, locale: locale) ?? en
        }
    }
}
