import Foundation
import Testing
@testable import GodotLauncher

struct GodotLauncherTests {
    @Test("应用语言支持系统、英文和简体中文")
    func resolvesApplicationLanguagePreference() {
        let suiteName = "GodotLauncherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppLanguage.current(defaults: defaults) == .system)
        defaults.set(AppLanguage.english.rawValue, forKey: PreferenceKey.appLanguage)
        #expect(AppLanguage.current(defaults: defaults) == .english)
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: PreferenceKey.appLanguage)
        #expect(AppLanguage.current(defaults: defaults) == .simplifiedChinese)
    }

    @Test("优先选择正确的 macOS 版本类型")
    func selectsCorrectMacAsset() {
        let release = makeRelease(assets: [
            makeAsset(id: 1, name: "Godot_v4.7-stable_linux.x86_64.zip"),
            makeAsset(id: 2, name: "Godot_v4.7-stable_macos.universal.zip"),
            makeAsset(id: 3, name: "Godot_v4.7-stable_mono_macos.universal.zip"),
            makeAsset(id: 4, name: "Godot_v4.7-stable_export_templates.tpz")
        ])

        #expect(release.macAsset(for: .standard)?.id == 2)
        #expect(release.macAsset(for: .dotnet)?.id == 3)
    }

    @Test("兼容旧版 OS X 资源命名")
    func selectsLegacyOSXAsset() {
        let release = makeRelease(assets: [
            makeAsset(id: 5, name: "Godot_v3.2.3-stable_osx.64.zip")
        ])

        #expect(release.macAsset(for: .standard)?.id == 5)
    }

    @Test("按原名、版本号、时间依次解决应用重名")
    func resolvesDestinationCollisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let extracted = root.appendingPathComponent("source/Godot.app")

        let plain = InstallDestinationResolver.destination(
            for: extracted,
            version: "4.7-stable",
            in: root
        )
        #expect(plain.lastPathComponent == "Godot.app")

        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let versioned = InstallDestinationResolver.destination(
            for: extracted,
            version: "4.7-stable",
            in: root
        )
        #expect(versioned.lastPathComponent == "Godot 4.7-stable.app")

        try FileManager.default.createDirectory(at: versioned, withIntermediateDirectories: true)
        let timestamped = InstallDestinationResolver.destination(
            for: extracted,
            version: "4.7-stable",
            in: root,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(timestamped.lastPathComponent.hasPrefix("Godot 4.7-stable "))
        #expect(timestamped.lastPathComponent.hasSuffix(".app"))

        let update = InstallDestinationResolver.destination(
            for: extracted,
            version: "4.7-stable",
            in: root,
            behavior: .update
        )
        #expect(update.lastPathComponent == "Godot.app")
    }

    @Test("更新模式安全替换现有 Godot.app")
    func replacesExistingGodotApplication() async throws {
        let archiveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: archiveDirectory)
            try? FileManager.default.removeItem(at: applicationsDirectory)
        }

        let sourceApplication = archiveDirectory.appendingPathComponent("payload/Godot New.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceApplication.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("new".utf8).write(to: sourceApplication.appendingPathComponent("new-version"))

        let existingApplication = applicationsDirectory.appendingPathComponent("Godot.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: existingApplication.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("old".utf8).write(to: existingApplication.appendingPathComponent("old-version"))

        let archive = archiveDirectory.appendingPathComponent("Godot.zip")
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", sourceApplication.path, archive.path]
        )

        let installedURL = try await GodotInstaller().install(
            archiveURL: archive,
            version: "4.8-stable",
            applicationsDirectory: applicationsDirectory,
            behavior: .update
        ) {}

        #expect(installedURL.lastPathComponent == "Godot.app")
        #expect(FileManager.default.fileExists(atPath: installedURL.appendingPathComponent("new-version").path))
        #expect(!FileManager.default.fileExists(atPath: installedURL.appendingPathComponent("old-version").path))
    }

    @Test("校验 GitHub SHA-256 摘要")
    func verifiesSHA256Digest() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("godot-launcher".utf8).write(to: file)

        let verifier = ArchiveIntegrityVerifier()
        try await verifier.verify(
            fileURL: file,
            expectedDigest: "sha256:ead12bfd036a5fb45526b33463b4fcb27d00f4e6b06967f6934f3044966461c6"
        )
    }

    @Test("识别 Stable、RC、Beta 和开发通道")
    func detectsReleaseChannels() {
        #expect(makeRelease(tag: "4.7-stable", prerelease: false).channel == .stable)
        #expect(makeRelease(tag: "4.8-rc3", prerelease: true).channel == .releaseCandidate)
        #expect(makeRelease(tag: "4.8-beta2", prerelease: true).channel == .beta)
        #expect(makeRelease(tag: "4.8-dev1", prerelease: true).channel == .development)
    }

    @Test("摘要移除 Markdown 并限制长度")
    func sanitizesReleaseSummary() {
        let release = makeRelease(
            notes: "**Godot 4.8** adds [new features](https://godotengine.org).\n\n" + String(repeating: "Details ", count: 80)
        )
        let summary = release.plainSummary(maxLength: 80)

        #expect(summary != nil)
        #expect(summary?.contains("**") == false)
        #expect(summary?.contains("\n") == false)
        #expect((summary?.count ?? 0) <= 81)
    }

    @Test("从官方归档页解析版本图")
    func extractsArtworkFromArchivePage() {
        let html = #"<div class="notes-thumbnail" style="background-image:url(/storage/releases/4.7/images/preview_image.jpg)"></div>"#
        #expect(
            ReleaseArtworkService.extractArtworkPath(from: html)
                == "/storage/releases/4.7/images/preview_image.jpg"
        )
    }

    @Test("解析官方、GodotHub 与自定义下载源")
    func resolvesDownloadSources() {
        let asset = makeAsset(id: 8, name: "Godot_v4.7-stable_macos.universal.zip")
        let stable = makeRelease(tag: "4.7-stable", assets: [asset])
        let releaseCandidate = makeRelease(
            tag: "4.7-rc3",
            prerelease: true,
            assets: [makeAsset(id: 9, name: "Godot_v4.7-rc3_macos.universal.zip")]
        )

        let official = DownloadSourceConfiguration(
            source: .official,
            customTemplate: "",
            customSupportsPreviews: false
        )
        #expect(official.downloadURL(for: stable, asset: asset) == asset.downloadURL)

        let godotHub = DownloadSourceConfiguration(
            source: .godotHub,
            customTemplate: "",
            customSupportsPreviews: false
        )
        #expect(
            godotHub.downloadURL(for: stable, asset: asset)?.absoluteString
                == "https://atomgit.com/godothub/godot/releases/download/4.7-stable/Godot_v4.7-stable_macos.universal.zip"
        )
        #expect(
            godotHub.downloadURL(for: releaseCandidate, asset: releaseCandidate.assets[0]) == nil
        )

        let custom = DownloadSourceConfiguration(
            source: .custom,
            customTemplate: "https://mirror.example/releases/{tag}/{asset}",
            customSupportsPreviews: true
        )
        #expect(
            custom.downloadURL(for: stable, asset: asset)?.absoluteString
                == "https://mirror.example/releases/4.7-stable/Godot_v4.7-stable_macos.universal.zip"
        )
        #expect(custom.customValidationMessage == nil)

        let stableOnlyCustom = DownloadSourceConfiguration(
            source: .custom,
            customTemplate: "https://mirror.example/releases/{tag}/{asset}",
            customSupportsPreviews: false
        )
        #expect(
            stableOnlyCustom.downloadURL(
                for: releaseCandidate,
                asset: releaseCandidate.assets[0]
            ) == nil
        )
    }

    @Test("自定义源要求 HTTPS 和 asset 占位符")
    func validatesCustomSource() {
        let missingAsset = DownloadSourceConfiguration(
            source: .custom,
            customTemplate: "https://mirror.example/{tag}",
            customSupportsPreviews: false
        )
        #expect(missingAsset.customValidationMessage != nil)

        let insecure = DownloadSourceConfiguration(
            source: .custom,
            customTemplate: "http://mirror.example/{tag}/{asset}",
            customSupportsPreviews: false
        )
        #expect(insecure.customValidationMessage != nil)
    }

    @Test("历史列表按当前版本类型的包大小排序")
    func sortsHistoryRowsBySelectedEditionPackageSize() {
        let smallerStandard = makeRelease(
            id: 1,
            tag: "4.7-stable",
            assets: [
                makeAsset(id: 11, name: "Godot_v4.7-stable_macos.universal.zip", size: 100),
                makeAsset(id: 12, name: "Godot_v4.7-stable_mono_macos.universal.zip", size: 900)
            ]
        )
        let largerStandard = makeRelease(
            id: 2,
            tag: "4.8-stable",
            assets: [
                makeAsset(id: 21, name: "Godot_v4.8-stable_macos.universal.zip", size: 800),
                makeAsset(id: 22, name: "Godot_v4.8-stable_mono_macos.universal.zip", size: 200)
            ]
        )

        let standardRows = [
            ReleaseListRow(release: largerStandard, edition: .standard),
            ReleaseListRow(release: smallerStandard, edition: .standard)
        ].sorted(using: [KeyPathComparator(\ReleaseListRow.packageSize)])
        #expect(standardRows.map(\.id) == [1, 2])

        let dotNetRows = [
            ReleaseListRow(release: largerStandard, edition: .dotnet),
            ReleaseListRow(release: smallerStandard, edition: .dotnet)
        ].sorted(using: [KeyPathComparator(\ReleaseListRow.packageSize)])
        #expect(dotNetRows.map(\.id) == [2, 1])
    }

    private func makeRelease(
        id: Int64 = 100,
        tag: String = "4.7-stable",
        prerelease: Bool = false,
        notes: String? = nil,
        assets: [ReleaseAsset] = []
    ) -> GodotRelease {
        GodotRelease(
            id: id,
            tagName: tag,
            name: "Godot 4.7",
            notes: notes,
            publishedAt: Date(),
            htmlURL: URL(string: "https://github.com/godotengine/godot-builds/releases/tag/\(tag)")!,
            prerelease: prerelease,
            draft: false,
            assets: assets
        )
    }

    private func makeAsset(id: Int64, name: String, size: Int64 = 100) -> ReleaseAsset {
        ReleaseAsset(
            id: id,
            name: name,
            size: size,
            downloadURL: URL(string: "https://example.com/\(name)")!,
            downloadCount: 0,
            digest: nil
        )
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
