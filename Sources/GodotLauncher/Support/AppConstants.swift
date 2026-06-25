import Foundation

enum AppConstants {
    static let displayName = "Godot Launcher"
    static let executableName = "GodotLauncher"
    static let mainWindowID = "main"
    static let supportDirectoryName = executableName
    static let defaultShortVersion = "1.0"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? defaultShortVersion
    }

    static var userAgent: String {
        "\(executableName)/\(shortVersion)"
    }

    enum Network {
        static let githubPerPage = 100
        static let maxGitHubReleasePages = 20
        static let requestTimeout: TimeInterval = 30
        static let releaseFetchTimeout: TimeInterval = 90
        static let downloadRequestTimeout: TimeInterval = 60
        static let downloadResourceTimeout: TimeInterval = 60 * 60
        static let artworkRequestTimeout: TimeInterval = 20
        static let minimumMultipartSize: Int64 = 8 * 1_024 * 1_024
        static let progressUpdateInterval: TimeInterval = 0.08
    }

    enum Downloads {
        static let defaultConnections = 6
        static let maximumConnections = 8
        static let keptArchivesFolderName = "Godot Downloads"
        static let mergeBufferSize = 1_048_576
    }

    enum Progress {
        static let speedSampleInterval: TimeInterval = 0.35
        static let previousSpeedWeight = 0.72
        static let instantSpeedWeight = 0.28
    }

    enum Installation {
        static let updateDestinationName = "Godot.app"
        static let stagedPrefix = ".Godot Launcher Staged"
        static let backupPrefix = ".Godot Launcher Backup"
    }

    enum Cache {
        static let currentReleaseCacheFileName = "releases-v2.json"
        static let legacyReleaseCacheFileName = "releases.json"
        static let receiptsFileName = "installations.json"
    }

    enum URLs {
        static let godotWebsiteHost = "godotengine.org"
        static let godotArchiveBase = "https://godotengine.org/download/archive"
        static let githubReleasesAPI = requiredURL(
            "https://api.github.com/repos/godotengine/godot-builds/releases"
        )
        static let godotHubDownloadPage = requiredURL("https://godothub.com/download")
        static let godotHubReleaseBase = "https://atomgit.com/godothub/godot/releases/download"

        static func godotArchivePageURL(encodedTag: String) -> URL? {
            URL(string: "\(godotArchiveBase)/\(encodedTag)/")
        }

        static func godotHubDownloadURL(encodedTag: String, encodedAssetName: String) -> URL? {
            URL(string: "\(godotHubReleaseBase)/\(encodedTag)/\(encodedAssetName)")
        }

        private static func requiredURL(_ value: String) -> URL {
            guard let url = URL(string: value) else {
                preconditionFailure("Invalid built-in URL: \(value)")
            }
            return url
        }
    }
}

enum AppDirectories {
    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(AppConstants.supportDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
