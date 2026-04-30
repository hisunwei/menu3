import Foundation

enum AppLanguage: String, CaseIterable {
    case en = "en"
    case zhHans = "zh-Hans"
    case ja = "ja"
    case ko = "ko"

    var displayName: String {
        switch self {
        case .zhHans: return L("中文")
        case .en: return L("英文")
        case .ja: return L("日文")
        case .ko: return L("韩文")
        }
    }
}

final class LanguageManager {
    static let shared = LanguageManager()

    private let selectedLanguageKey = "menu3.selectedLanguage"

    var currentLanguage: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: selectedLanguageKey),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return fallbackFromSystem()
    }

    func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: selectedLanguageKey)
    }

    func localizedString(_ key: String) -> String {
        let language = currentLanguage.rawValue
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    private func fallbackFromSystem() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("en") { return .en }
        if preferred.hasPrefix("zh-hans") { return .zhHans }
        if preferred.hasPrefix("ja") { return .ja }
        if preferred.hasPrefix("ko") { return .ko }
        return .en
    }
}

@inline(__always)
func L(_ key: String) -> String {
    LanguageManager.shared.localizedString(key)
}

@inline(__always)
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}
