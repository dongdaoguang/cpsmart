import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    private static let defaultsKey = "appLanguage"

    static func selected(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system
    }

    static func select(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(language.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .system: return L10n.tr("跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    func resolvedCode(preferredLanguage: String?) -> String {
        switch self {
        case .system:
            return preferredLanguage?.hasPrefix("zh") == true ? "zh-Hans" : "en"
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
}

enum L10n {
    private static let placeholderPattern = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static var languageCode: String {
        AppLanguage.selected().resolvedCode(preferredLanguage: Locale.preferredLanguages.first)
    }

    static func tr(_ key: String, language: String? = nil) -> String {
        let code = language ?? languageCode
        #if SWIFT_PACKAGE
        let resources = Bundle.main.bundleIdentifier == "com.cpsmart.app"
            ? Bundle.main : Bundle.module
        guard let path = resources.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
        #else
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/\(code).lproj/Localizable.strings")
        guard let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: String] else { return key }
        return values[key] ?? key
        #endif
    }

    static func format(_ key: String, _ arguments: [Any], language: String? = nil) -> String {
        var result = tr(key, language: language)
        let matches = placeholderPattern.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: result),
                  let number = Int(result[numberRange]),
                  arguments.indices.contains(number),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(describing: arguments[number]))
        }
        return result
    }
}
