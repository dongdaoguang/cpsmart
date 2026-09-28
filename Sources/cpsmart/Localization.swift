import Foundation

enum L10n {
    private static let placeholderPattern = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static var languageCode: String {
        let preference = Locale.preferredLanguages.first ?? "en"
        return preference.hasPrefix("zh") ? "zh-Hans" : "en"
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
