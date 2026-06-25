import Foundation

enum PreferenceKey {
    static let appLanguage = "appLanguage"
    static let selectedEdition = "selectedEdition"
    static let showStableBuilds = "showStableBuilds"
    static let showRCBuilds = "showRCBuilds"
    static let showBetaBuilds = "showBetaBuilds"
    static let showDevBuilds = "showDevBuilds"
    static let confirmPreviewInstalls = "confirmPreviewInstalls"
    static let refreshOnLaunch = "refreshOnLaunch"
    static let cacheDuration = "cacheDuration"
    static let showReleaseSummary = "showReleaseSummary"
    static let completionNotifications = "completionNotifications"
    static let revealAfterInstall = "revealAfterInstall"
    static let launchAfterInstall = "launchAfterInstall"
    static let downloadConnections = "downloadConnections"
    static let installationLocation = "installationLocation"
    static let installationBehavior = "installationBehavior"
    static let keepDownloadedArchives = "keepDownloadedArchives"
    static let downloadSource = "downloadSource"
    static let customDownloadTemplate = "customDownloadTemplate"
    static let customSourceSupportsPreviews = "customSourceSupportsPreviews"
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.tr("language_system")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var localizationName: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var locale: Locale {
        localizationName.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        let rawValue = defaults.string(forKey: PreferenceKey.appLanguage) ?? ""
        return AppLanguage(rawValue: rawValue) ?? .system
    }
}

enum InstallationBehavior: String, CaseIterable, Identifiable, Sendable {
    case install
    case update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .install: L10n.tr("behavior_install")
        case .update: L10n.tr("behavior_update")
        }
    }

    var help: String {
        switch self {
        case .install: L10n.tr("behavior_install_help")
        case .update: L10n.tr("behavior_update_help")
        }
    }

    static func current(defaults: UserDefaults = .standard) -> InstallationBehavior {
        let rawValue = defaults.string(forKey: PreferenceKey.installationBehavior) ?? ""
        return InstallationBehavior(rawValue: rawValue) ?? .install
    }
}

enum ReleaseCacheDuration: Int, CaseIterable, Identifiable {
    case alwaysRefresh = 0
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case sixHours = 21_600

    var id: Int { rawValue }
    var timeInterval: TimeInterval { TimeInterval(rawValue) }
    static let defaultValue = ReleaseCacheDuration.thirtyMinutes

    var title: String {
        switch self {
        case .alwaysRefresh: L10n.tr("cache_always")
        case .fifteenMinutes: L10n.tr("cache_15_minutes")
        case .thirtyMinutes: L10n.tr("cache_30_minutes")
        case .oneHour: L10n.tr("cache_1_hour")
        case .sixHours: L10n.tr("cache_6_hours")
        }
    }
}

enum InstallationLocation: String, CaseIterable, Identifiable {
    case systemApplications
    case userApplications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemApplications: L10n.tr("system_applications")
        case .userApplications: L10n.tr("user_applications")
        }
    }

    var directoryURL: URL {
        switch self {
        case .systemApplications:
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
                ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        case .userApplications:
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        }
    }
}
