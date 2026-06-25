import Foundation

enum L10n {
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let language = AppLanguage.current()
        let format = bundle(for: language).localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let localizationName = language.localizationName,
              let path = Bundle.main.path(forResource: localizationName, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
