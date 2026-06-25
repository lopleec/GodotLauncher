import Foundation

actor ArchiveKeeper {
    func keep(_ archive: URL) throws -> URL {
        let downloadsDirectory = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = downloadsDirectory
            .appendingPathComponent(AppConstants.Downloads.keptArchivesFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = archive.deletingPathExtension().lastPathComponent
        let fileExtension = archive.pathExtension
        var destination = directory.appendingPathComponent(archive.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(
                "\(baseName) \(AppFormatting.installTimestamp()).\(fileExtension)"
            )
        }
        try FileManager.default.copyItem(at: archive, to: destination)
        return destination
    }
}
