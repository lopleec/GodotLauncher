import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LauncherStore {
    var releases: [GodotRelease] = []
    var isLoading = false
    var loadingPage = 0
    var loadError: String?
    var isUsingCachedData = false
    var activeJob: InstallationJob?
    var completion: InstallationCompletion?
    var pendingInstallation: PendingInstallation?
    var receipts: [InstallationReceipt] = []

    @ObservationIgnored private let releaseService = GitHubReleaseService()
    @ObservationIgnored private let downloadService = ParallelDownloadService()
    @ObservationIgnored private let integrityVerifier = ArchiveIntegrityVerifier()
    @ObservationIgnored private let archiveKeeper = ArchiveKeeper()
    @ObservationIgnored private let installer = GodotInstaller()
    @ObservationIgnored private var installationTask: Task<Void, Never>?
    @ObservationIgnored private var progressSample = ProgressSample()

    private struct ProgressSample {
        var date = Date()
        var bytes: Int64 = 0
        var smoothedSpeed: Double = 0
    }

    init() {
        receipts = Self.readReceipts().filter {
            FileManager.default.fileExists(atPath: $0.applicationURL.path)
        }
        saveReceipts()
    }

    var latestStable: GodotRelease? {
        releases.first { $0.isStable && $0.macAsset(for: .standard) != nil }
    }

    var isBusy: Bool {
        activeJob?.phase.isActive == true
    }

    var canCancelInstallation: Bool {
        activeJob?.phase.canCancel == true
    }

    func loadReleases(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        loadingPage = 0
        loadError = nil
        defer { isLoading = false }

        do {
            let configuredDuration = UserDefaults.standard.integer(forKey: PreferenceKey.cacheDuration)
            let cacheDuration = ReleaseCacheDuration(rawValue: configuredDuration)?.timeInterval
                ?? ReleaseCacheDuration.defaultValue.timeInterval
            let result = try await releaseService.fetchReleases(
                forceRefresh: forceRefresh,
                cacheLifetime: cacheDuration
            ) { [weak self] page in
                self?.loadingPage = page
            }
            releases = result.releases
            isUsingCachedData = result.usedCachedData
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clearReleaseCache() async {
        try? await releaseService.clearCache()
        isUsingCachedData = false
    }

    func requestInstall(_ release: GodotRelease, edition: GodotEdition) {
        guard let asset = release.macAsset(for: edition) else {
            showInstallationFailure(
                release: release,
                edition: edition,
                message: L10n.tr("missing_macos_asset", edition.title)
            )
            return
        }
        let sourceConfiguration = DownloadSourceConfiguration.current()
        guard sourceConfiguration.downloadURL(for: release, asset: asset) != nil else {
            showInstallationFailure(
                release: release,
                edition: edition,
                message: sourceConfiguration.unavailableReason(for: release, asset: asset)
                    ?? L10n.tr("download_source_unavailable", sourceConfiguration.source.title)
            )
            return
        }
        let shouldConfirm = UserDefaults.standard.object(forKey: PreferenceKey.confirmPreviewInstalls) as? Bool ?? true
        if release.prerelease && shouldConfirm {
            pendingInstallation = PendingInstallation(release: release, edition: edition)
        } else {
            install(release, edition: edition)
        }
    }

    func confirmPendingInstallation() {
        guard let pendingInstallation else { return }
        self.pendingInstallation = nil
        install(pendingInstallation.release, edition: pendingInstallation.edition)
    }

    func install(_ release: GodotRelease, edition: GodotEdition) {
        guard !isBusy else { return }
        guard let officialAsset = release.macAsset(for: edition) else {
            showInstallationFailure(
                release: release,
                edition: edition,
                message: L10n.tr("missing_macos_asset", edition.title)
            )
            return
        }
        let sourceConfiguration = DownloadSourceConfiguration.current()
        guard let resolvedDownloadURL = sourceConfiguration.downloadURL(
            for: release,
            asset: officialAsset
        ) else {
            showInstallationFailure(
                release: release,
                edition: edition,
                message: sourceConfiguration.unavailableReason(for: release, asset: officialAsset)
                    ?? L10n.tr("download_source_unavailable", sourceConfiguration.source.title)
            )
            return
        }
        let asset = officialAsset.using(downloadURL: resolvedDownloadURL)
        let installationBehavior = InstallationBehavior.current()

        let jobID = UUID()
        progressSample = ProgressSample()
        activeJob = InstallationJob(
            id: jobID,
            releaseID: release.id,
            version: release.displayVersion,
            edition: edition,
            behavior: installationBehavior,
            phase: .preparing,
            completedBytes: 0,
            totalBytes: asset.size,
            bytesPerSecond: 0,
            errorMessage: nil,
            installedURL: nil
        )

        let connectionCount = max(
            1,
            min(
                AppConstants.Downloads.maximumConnections,
                UserDefaults.standard.integer(forKey: PreferenceKey.downloadConnections)
                    .nonzeroOr(AppConstants.Downloads.defaultConnections)
            )
        )
        let notificationsEnabled = UserDefaults.standard.object(forKey: PreferenceKey.completionNotifications) as? Bool ?? true
        let locationRaw = UserDefaults.standard.string(forKey: PreferenceKey.installationLocation)
        let installLocation = InstallationLocation(rawValue: locationRaw ?? "") ?? .systemApplications

        installationTask = Task { [weak self] in
            guard let self else { return }
            if notificationsEnabled {
                await NotificationService.requestAuthorizationIfNeeded()
            }

            do {
                self.updateJob(id: jobID) { $0.phase = .downloading }
                let archive = try await self.downloadService.download(
                    asset: asset,
                    connections: connectionCount
                ) { [weak self] completed, total in
                    self?.updateProgress(jobID: jobID, completed: completed, total: total)
                }

                try Task.checkCancellation()
                if let digest = asset.digest {
                    self.updateJob(id: jobID) { $0.phase = .verifying }
                    try await self.integrityVerifier.verify(fileURL: archive, expectedDigest: digest)
                }
                if UserDefaults.standard.bool(forKey: PreferenceKey.keepDownloadedArchives) {
                    _ = try await self.archiveKeeper.keep(archive)
                }
                try Task.checkCancellation()
                self.updateJob(id: jobID) { $0.phase = .extracting }
                let installedURL = try await self.installer.install(
                    archiveURL: archive,
                    version: release.displayVersion,
                    applicationsDirectory: installLocation.directoryURL,
                    behavior: installationBehavior
                ) { [weak self] in
                    self?.updateJob(id: jobID) { $0.phase = .installing }
                }
                try Task.checkCancellation()

                self.updateJob(id: jobID) {
                    $0.phase = .completed
                    $0.installedURL = installedURL
                    $0.completedBytes = $0.totalBytes
                    $0.bytesPerSecond = 0
                }

                let receipt = InstallationReceipt(
                    id: UUID(),
                    releaseID: release.id,
                    version: release.displayVersion,
                    edition: edition,
                    installedAt: Date(),
                    applicationURL: installedURL
                )
                self.receipts.removeAll { $0.applicationURL == installedURL }
                self.receipts.insert(receipt, at: 0)
                self.saveReceipts()
                self.completion = InstallationCompletion(
                    version: release.displayVersion,
                    applicationURL: installedURL,
                    behavior: installationBehavior
                )

                let revealAfterInstall = UserDefaults.standard.object(forKey: PreferenceKey.revealAfterInstall) as? Bool ?? true
                if revealAfterInstall {
                    NSWorkspace.shared.activateFileViewerSelecting([installedURL])
                }
                if UserDefaults.standard.bool(forKey: PreferenceKey.launchAfterInstall) {
                    NSWorkspace.shared.open(installedURL)
                }
                if notificationsEnabled {
                    await NotificationService.sendInstallationCompleted(
                        version: release.displayVersion,
                        applicationName: installedURL.lastPathComponent,
                        behavior: installationBehavior
                    )
                }
            } catch is CancellationError {
                self.updateJob(id: jobID) {
                    $0.phase = .cancelled
                    $0.errorMessage = nil
                    $0.bytesPerSecond = 0
                }
            } catch DownloadServiceError.cancelled {
                self.updateJob(id: jobID) {
                    $0.phase = .cancelled
                    $0.errorMessage = nil
                    $0.bytesPerSecond = 0
                }
            } catch {
                self.updateJob(id: jobID) {
                    $0.phase = .failed
                    $0.errorMessage = error.localizedDescription
                    $0.bytesPerSecond = 0
                }
            }
        }
    }

    func cancelInstallation() {
        guard canCancelInstallation else { return }
        installationTask?.cancel()
    }

    func dismissActivity() {
        guard activeJob?.phase.isActive != true else { return }
        activeJob = nil
    }

    func revealInstalledApplication(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func launchInstalledApplication(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func isInstalled(_ release: GodotRelease, edition: GodotEdition) -> Bool {
        receipts.contains {
            ($0.releaseID == release.id || $0.version == release.displayVersion) && $0.edition == edition
        }
    }

    private func updateProgress(jobID: UUID, completed: Int64, total: Int64) {
        let now = Date()
        let interval = now.timeIntervalSince(progressSample.date)
        if interval >= AppConstants.Progress.speedSampleInterval {
            let instantSpeed = Double(max(0, completed - progressSample.bytes)) / interval
            progressSample.smoothedSpeed = progressSample.smoothedSpeed == 0
                ? instantSpeed
                : (
                    progressSample.smoothedSpeed * AppConstants.Progress.previousSpeedWeight
                        + instantSpeed * AppConstants.Progress.instantSpeedWeight
                )
            progressSample.date = now
            progressSample.bytes = completed
        }
        updateJob(id: jobID) {
            $0.completedBytes = completed
            $0.totalBytes = total
            $0.bytesPerSecond = progressSample.smoothedSpeed
        }
    }

    private func showInstallationFailure(
        release: GodotRelease,
        edition: GodotEdition,
        message: String
    ) {
        activeJob = InstallationJob(
            id: UUID(),
            releaseID: release.id,
            version: release.displayVersion,
            edition: edition,
            behavior: InstallationBehavior.current(),
            phase: .failed,
            completedBytes: 0,
            totalBytes: release.macAsset(for: edition)?.size ?? 0,
            bytesPerSecond: 0,
            errorMessage: message,
            installedURL: nil
        )
    }

    private func updateJob(id: UUID, _ change: (inout InstallationJob) -> Void) {
        guard var job = activeJob, job.id == id else { return }
        change(&job)
        activeJob = job
    }

    private static var receiptsURL: URL? {
        guard let directory = try? AppDirectories.applicationSupportDirectory() else { return nil }
        return directory.appendingPathComponent(AppConstants.Cache.receiptsFileName)
    }

    private static func readReceipts() -> [InstallationReceipt] {
        guard let url = receiptsURL,
              let data = try? Data(contentsOf: url),
              let receipts = try? JSONDecoder().decode([InstallationReceipt].self, from: data) else {
            return []
        }
        return receipts
    }

    private func saveReceipts() {
        guard let url = Self.receiptsURL,
              let data = try? JSONEncoder().encode(receipts) else { return }
        try? data.write(to: url, options: .atomic)
    }

}

private extension Int {
    func nonzeroOr(_ fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
