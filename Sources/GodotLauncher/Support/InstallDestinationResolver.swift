import Foundation

enum InstallDestinationResolver {
    static func destination(
        for extractedApplication: URL,
        version: String,
        in applicationsDirectory: URL,
        behavior: InstallationBehavior = .install,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL {
        if behavior == .update {
            return applicationsDirectory.appendingPathComponent(
                AppConstants.Installation.updateDestinationName,
                isDirectory: true
            )
        }

        let baseName = extractedApplication.deletingPathExtension().lastPathComponent
        let plain = applicationsDirectory.appendingPathComponent("\(baseName).app", isDirectory: true)
        guard fileManager.fileExists(atPath: plain.path) else { return plain }

        let safeVersion = sanitized(version)
        let versioned = applicationsDirectory.appendingPathComponent(
            "\(baseName) \(safeVersion).app",
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: versioned.path) else { return versioned }

        let timestamp = AppFormatting.installTimestamp(now)
        let timestampedName = "\(baseName) \(safeVersion) \(timestamp)"
        var candidate = applicationsDirectory.appendingPathComponent("\(timestampedName).app", isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = applicationsDirectory.appendingPathComponent(
                "\(timestampedName) \(suffix).app",
                isDirectory: true
            )
            suffix += 1
        }
        return candidate
    }

    private static func sanitized(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:")
        return value.components(separatedBy: disallowed).joined(separator: "-")
    }
}
