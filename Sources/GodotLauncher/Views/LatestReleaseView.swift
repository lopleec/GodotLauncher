import AppKit
import SwiftUI

struct LatestReleaseView: View {
    @AppStorage(PreferenceKey.installationBehavior) private var installationBehaviorRawValue = InstallationBehavior.install.rawValue
    let store: LauncherStore
    let release: GodotRelease?
    let edition: GodotEdition
    let downloadSource: DownloadSourceConfiguration
    let showReleaseSummary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(
                    L10n.tr(release?.id == store.latestStable?.id ? "latest" : "version_info"),
                    systemImage: release?.id == store.latestStable?.id ? "sparkles" : "info.circle"
                )
                    .font(.headline)
                Spacer()
                if store.isUsingCachedData {
                    Text(L10n.tr("cached"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            if store.isLoading, store.releases.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(store.loadingPage > 0
                         ? L10n.tr("fetching_page", store.loadingPage)
                         : L10n.tr("connecting_release_service"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if let release {
                latestContent(release)
            } else if let error = store.loadError {
                Spacer()
                ContentUnavailableView {
                    Label(L10n.tr("cannot_load_versions"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(verbatim: error)
                } actions: {
                    Button(L10n.tr("retry")) {
                        Task { await store.loadReleases(forceRefresh: true) }
                    }
                }
                Spacer()
            } else {
                Spacer()
                ContentUnavailableView(L10n.tr("no_available_versions"), systemImage: "shippingbox")
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func latestContent(_ release: GodotRelease) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(nsImage: versionLogo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                    .frame(width: 78, height: 78)
                    .accessibilityHidden(true)

                    Text(verbatim: "Godot \(release.displayVersion)")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Text(verbatim: release.channelTitle)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(channelColor(release.channel).opacity(0.14), in: Capsule())
                            .foregroundStyle(channelColor(release.channel))
                        Text(verbatim: AppFormatting.releaseDate(release.publishedAt))
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox(L10n.tr("package")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let asset = release.macAsset(for: edition) {
                            ReleaseMetadataRow(label: L10n.tr("edition"), value: edition.title)
                            ReleaseMetadataRow(
                                label: L10n.tr("architecture"),
                                value: asset.name.lowercased().contains("universal") ? "Apple Silicon + Intel" : "macOS"
                            )
                            ReleaseMetadataRow(label: L10n.tr("download_size"), value: AppFormatting.bytes(asset.size))
                            ReleaseMetadataRow(label: L10n.tr("download_source"), value: downloadSource.source.title)
                            if asset.digest != nil {
                                ReleaseMetadataRow(label: L10n.tr("integrity"), value: "SHA-256")
                            }
                            if let reason = downloadSource.unavailableReason(for: release, asset: asset) {
                                Label(reason, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Label(
                                L10n.tr("missing_macos_asset", edition.title),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showReleaseSummary, let summary = release.plainSummary() {
                    GroupBox(L10n.tr("release_summary")) {
                        Text(verbatim: summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(7)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ReleaseArtworkView(release: release)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .id(release.id)

        Divider()

        VStack(spacing: 9) {
            Button {
                store.requestInstall(release, edition: edition)
            } label: {
                Label(
                    primaryActionTitle(for: release),
                    systemImage: installationBehavior == .update
                        ? "arrow.triangle.2.circlepath"
                        : "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                release.macAsset(for: edition) == nil
                    || !isAvailableFromSelectedSource(release)
                    || store.isBusy
            )

            Link(destination: release.htmlURL) {
                Label(L10n.tr("view_full_release_notes"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }

    private func channelColor(_ channel: ReleaseChannel) -> Color {
        switch channel {
        case .stable: .green
        case .releaseCandidate: .purple
        case .beta: .orange
        case .development, .preview: .secondary
        }
    }

    private func isAvailableFromSelectedSource(_ release: GodotRelease) -> Bool {
        guard let asset = release.macAsset(for: edition) else { return false }
        return downloadSource.downloadURL(for: release, asset: asset) != nil
    }

    private var installationBehavior: InstallationBehavior {
        InstallationBehavior(rawValue: installationBehaviorRawValue) ?? .install
    }

    private func primaryActionTitle(for release: GodotRelease) -> String {
        if installationBehavior == .update {
            return L10n.tr("update_edition", edition.shortTitle)
        }
        return store.isInstalled(release, edition: edition)
            ? L10n.tr("reinstall")
            : L10n.tr("install_edition", edition.shortTitle)
    }

    private var versionLogo: NSImage {
        guard let url = Bundle.main.url(forResource: "VersionLogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "cube.transparent", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 78, height: 78))
        }
        return image
    }
}

private struct ReleaseMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(verbatim: value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
