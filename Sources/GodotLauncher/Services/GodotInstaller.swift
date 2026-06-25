import Foundation

enum InstallerError: LocalizedError {
    case archiveUnsupported
    case extractionFailed(String)
    case applicationNotFound
    case invalidApplication
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveUnsupported: L10n.tr("archive_unsupported")
        case let .extractionFailed(message): L10n.tr("extraction_failed", message)
        case .applicationNotFound: L10n.tr("application_not_found")
        case .invalidApplication: L10n.tr("invalid_application")
        case let .installFailed(message): L10n.tr("install_failed", message)
        }
    }
}

actor GodotInstaller {
    func install(
        archiveURL: URL,
        version: String,
        applicationsDirectory: URL,
        behavior: InstallationBehavior,
        didBeginInstallation: @MainActor @Sendable () -> Void
    ) async throws -> URL {
        let workingDirectory = archiveURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        try Task.checkCancellation()
        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw InstallerError.archiveUnsupported
        }

        let stagingDirectory = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let extraction = try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, stagingDirectory.path]
        )
        guard extraction.status == 0 else {
            throw InstallerError.extractionFailed(extraction.output)
        }

        try Task.checkCancellation()
        guard let application = findApplication(in: stagingDirectory) else {
            throw InstallerError.applicationNotFound
        }
        guard FileManager.default.fileExists(
            atPath: application.appendingPathComponent("Contents/MacOS", isDirectory: true).path
        ) else {
            throw InstallerError.invalidApplication
        }

        try FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        let destination = InstallDestinationResolver.destination(
            for: application,
            version: version,
            in: applicationsDirectory,
            behavior: behavior
        )

        await didBeginInstallation()
        let install = try behavior == .update
            ? updateApplication(from: application, to: destination)
            : run(executable: "/usr/bin/ditto", arguments: [application.path, destination.path])
        if install.status != 0 {
            let privileged = try behavior == .update
                ? privilegedUpdate(from: application, to: destination)
                : privilegedInstall(from: application, to: destination)
            guard privileged.status == 0 else {
                throw InstallerError.installFailed(privileged.output.isEmpty ? install.output : privileged.output)
            }
        }

        return destination
    }

    private func updateApplication(from source: URL, to destination: URL) throws -> ProcessResult {
        let directory = destination.deletingLastPathComponent()
        let token = UUID().uuidString
        let staged = directory.appendingPathComponent(
            "\(AppConstants.Installation.stagedPrefix) \(token).app",
            isDirectory: true
        )
        let backup = directory.appendingPathComponent(
            "\(AppConstants.Installation.backupPrefix) \(token).app",
            isDirectory: true
        )
        let fileManager = FileManager.default
        defer {
            try? fileManager.removeItem(at: staged)
        }

        let stageResult = try run(
            executable: "/usr/bin/ditto",
            arguments: [source.path, staged.path]
        )
        guard stageResult.status == 0 else { return stageResult }

        do {
            let hadExistingApplication = fileManager.fileExists(atPath: destination.path)
            if hadExistingApplication {
                try fileManager.moveItem(at: destination, to: backup)
            }
            do {
                try fileManager.moveItem(at: staged, to: destination)
            } catch {
                if hadExistingApplication, fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }
            if hadExistingApplication {
                try fileManager.removeItem(at: backup)
            }
            return ProcessResult(status: 0, output: "")
        } catch {
            if fileManager.fileExists(atPath: backup.path),
               !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            return ProcessResult(status: 1, output: error.localizedDescription)
        }
    }

    private func findApplication(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        let applications = enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension.lowercased() == "app"
        }
        return applications.sorted {
            $0.pathComponents.count < $1.pathComponents.count
        }.first
    }

    private func privilegedInstall(from source: URL, to destination: URL) throws -> ProcessResult {
        let script = [
            "on run argv",
            "do shell script \"/usr/bin/ditto \" & quoted form of item 1 of argv & \" \" & quoted form of item 2 of argv with administrator privileges",
            "end run"
        ]
        var arguments: [String] = []
        for line in script {
            arguments.append(contentsOf: ["-e", line])
        }
        arguments.append(contentsOf: [source.path, destination.path])
        return try run(executable: "/usr/bin/osascript", arguments: arguments)
    }

    private func privilegedUpdate(from source: URL, to destination: URL) throws -> ProcessResult {
        let token = UUID().uuidString
        let directory = destination.deletingLastPathComponent()
        let staged = directory.appendingPathComponent(
            "\(AppConstants.Installation.stagedPrefix) \(token).app",
            isDirectory: true
        )
        let backup = directory.appendingPathComponent(
            "\(AppConstants.Installation.backupPrefix) \(token).app",
            isDirectory: true
        )
        let command = """
        set -eu
        source=\(shellQuote(source.path))
        destination=\(shellQuote(destination.path))
        staged=\(shellQuote(staged.path))
        backup=\(shellQuote(backup.path))
        /bin/rm -rf "$staged" "$backup"
        /usr/bin/ditto "$source" "$staged"
        had_existing=0
        if [ -e "$destination" ]; then
          /bin/mv "$destination" "$backup"
          had_existing=1
        fi
        if /bin/mv "$staged" "$destination"; then
          /bin/rm -rf "$backup"
        else
          /bin/rm -rf "$staged"
          if [ "$had_existing" -eq 1 ] && [ -e "$backup" ]; then
            /bin/mv "$backup" "$destination"
          fi
          exit 1
        fi
        """
        let script = [
            "on run argv",
            "do shell script item 1 of argv with administrator privileges",
            "end run"
        ]
        var arguments: [String] = []
        for line in script {
            arguments.append(contentsOf: ["-e", line])
        }
        arguments.append(command)
        return try run(executable: "/usr/bin/osascript", arguments: arguments)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    private func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ProcessResult(status: process.terminationStatus, output: output)
    }
}
