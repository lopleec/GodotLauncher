import SwiftUI

struct HistoryView: View {
    @AppStorage(PreferenceKey.installationBehavior) private var installationBehaviorRawValue = InstallationBehavior.install.rawValue
    let store: LauncherStore
    let edition: GodotEdition
    @Binding var showStableBuilds: Bool
    @Binding var showRCBuilds: Bool
    @Binding var showBetaBuilds: Bool
    @Binding var showDevBuilds: Bool
    @Binding var inspectedReleaseID: GodotRelease.ID?
    let downloadSource: DownloadSourceConfiguration
    let searchText: String
    @State private var sortOrder = [KeyPathComparator(\ReleaseListRow.publishedAt, order: .reverse)]

    private var rows: [ReleaseListRow] {
        store.releases.filter { release in
            let matchesChannel: Bool = switch release.channel {
            case .stable: showStableBuilds
            case .releaseCandidate: showRCBuilds
            case .beta: showBetaBuilds
            case .development, .preview: showDevBuilds
            }
            let matchesSearch = searchText.isEmpty
                || release.displayVersion.localizedCaseInsensitiveContains(searchText)
                || (release.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesChannel && matchesSearch
        }
        .map { ReleaseListRow(release: $0, edition: edition) }
        .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("history"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.tr("version_count", rows.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                channelMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if rows.isEmpty, !store.isLoading {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("no_matching_versions"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(L10n.tr("enable_more_channels"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                releaseTable
                    .overlay(alignment: .bottom) {
                        if store.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(L10n.tr("refreshing"))
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                        }
                    }
            }
        }
    }

    private var channelMenu: some View {
        Menu {
            Toggle(L10n.tr("channel_stable"), isOn: $showStableBuilds)
            Toggle("RC", isOn: $showRCBuilds)
            Toggle("Beta", isOn: $showBetaBuilds)
            Toggle(L10n.tr("channel_development"), isOn: $showDevBuilds)
            Divider()
            Button(L10n.tr("show_all_channels")) {
                showStableBuilds = true
                showRCBuilds = true
                showBetaBuilds = true
                showDevBuilds = true
            }
        } label: {
            Label(L10n.tr("channels"), systemImage: "line.3.horizontal.decrease")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.tr("channel_filter_help"))
    }

    private var releaseTable: some View {
        Table(rows, selection: $inspectedReleaseID, sortOrder: $sortOrder) {
            TableColumn(L10n.tr("version"), value: \.displayVersion) { row in
                let release = row.release
                HStack(spacing: 8) {
                    Image(systemName: release.channel.systemImage)
                        .foregroundStyle(channelColor(release.channel))
                        .frame(width: 16)
                    Text(verbatim: release.displayVersion)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if store.isInstalled(release, edition: edition) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help(L10n.tr("installed"))
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn(L10n.tr("channel"), value: \.channelTitle) { row in
                Text(verbatim: row.channelTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 68, ideal: 82)

            TableColumn(L10n.tr("released"), value: \.publishedAt) { row in
                Text(verbatim: AppFormatting.releaseDate(row.publishedAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 92, ideal: 105)

            TableColumn(L10n.tr("size"), value: \.packageSize) { row in
                if let asset = row.macAsset {
                    Text(verbatim: AppFormatting.bytes(asset.size))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .help(L10n.tr("no_macos_build", edition.shortTitle))
                }
            }
            .width(min: 72, ideal: 82)

            TableColumn("") { row in
                let release = row.release
                HStack(spacing: 8) {
                    Button {
                        inspectedReleaseID = release.id
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("show_info"))
                    .accessibilityLabel(L10n.tr("show_info"))

                    Link(destination: release.htmlURL) {
                        Image(systemName: "doc.text")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("view_release_notes"))

                    Button(actionTitle(for: release)) {
                        store.requestInstall(release, edition: edition)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isAvailableFromSelectedSource(release) || store.isBusy)
                    .help(downloadHelp(for: release))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 136, ideal: 150)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: GodotRelease.ID.self) { ids in
            if let id = ids.first, let release = rows.first(where: { $0.id == id })?.release {
                Button(L10n.tr("show_info")) {
                    inspectedReleaseID = release.id
                }
                Button(actionTitle(for: release, includeEdition: true)) {
                    store.requestInstall(release, edition: edition)
                }
                .disabled(!isAvailableFromSelectedSource(release) || store.isBusy)
                Link(L10n.tr("view_in_browser"), destination: release.htmlURL)
            }
        }
    }

    private func channelColor(_ channel: ReleaseChannel) -> Color {
        switch channel {
        case .stable: .blue
        case .releaseCandidate: .purple
        case .beta: .orange
        case .development, .preview: .secondary
        }
    }

    private func isAvailableFromSelectedSource(_ release: GodotRelease) -> Bool {
        guard let asset = release.macAsset(for: edition) else { return false }
        return downloadSource.downloadURL(for: release, asset: asset) != nil
    }

    private func downloadHelp(for release: GodotRelease) -> String {
        guard let asset = release.macAsset(for: edition) else {
            return L10n.tr("missing_macos_asset", edition.title)
        }
        return downloadSource.unavailableReason(for: release, asset: asset)
            ?? actionTitle(for: release, includeEdition: true)
    }

    private var installationBehavior: InstallationBehavior {
        InstallationBehavior(rawValue: installationBehaviorRawValue) ?? .install
    }

    private func actionTitle(for release: GodotRelease, includeEdition: Bool = false) -> String {
        if installationBehavior == .update {
            return includeEdition ? L10n.tr("update_edition", edition.title) : L10n.tr("update")
        }
        if includeEdition {
            return L10n.tr("install_edition", edition.title)
        }
        return store.isInstalled(release, edition: edition) ? L10n.tr("reinstall") : L10n.tr("install")
    }
}
