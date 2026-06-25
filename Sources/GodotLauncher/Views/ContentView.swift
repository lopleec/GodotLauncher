import SwiftUI

struct ContentView: View {
    @Bindable var store: LauncherStore
    @AppStorage(PreferenceKey.selectedEdition) private var editionRawValue = GodotEdition.standard.rawValue
    @AppStorage(PreferenceKey.showStableBuilds) private var showStableBuilds = true
    @AppStorage(PreferenceKey.showRCBuilds) private var showRCBuilds = true
    @AppStorage(PreferenceKey.showBetaBuilds) private var showBetaBuilds = true
    @AppStorage(PreferenceKey.showDevBuilds) private var showDevBuilds = true
    @AppStorage(PreferenceKey.showReleaseSummary) private var showReleaseSummary = true
    @AppStorage(PreferenceKey.refreshOnLaunch) private var refreshOnLaunch = false
    @AppStorage(PreferenceKey.downloadSource) private var downloadSourceRawValue = DownloadSource.official.rawValue
    @AppStorage(PreferenceKey.customDownloadTemplate) private var customDownloadTemplate = ""
    @AppStorage(PreferenceKey.customSourceSupportsPreviews) private var customSourceSupportsPreviews = false
    @State private var searchText = ""
    @State private var inspectedReleaseID: GodotRelease.ID?

    private var edition: GodotEdition {
        GodotEdition(rawValue: editionRawValue) ?? .standard
    }

    private var inspectedRelease: GodotRelease? {
        if let inspectedReleaseID,
           let release = store.releases.first(where: { $0.id == inspectedReleaseID }) {
            return release
        }
        return store.latestStable
    }

    private var downloadSourceConfiguration: DownloadSourceConfiguration {
        DownloadSourceConfiguration(
            source: DownloadSource(rawValue: downloadSourceRawValue) ?? .official,
            customTemplate: customDownloadTemplate,
            customSupportsPreviews: customSourceSupportsPreviews
        )
    }

    var body: some View {
        NavigationSplitView {
            LatestReleaseView(
                store: store,
                release: inspectedRelease,
                edition: edition,
                downloadSource: downloadSourceConfiguration,
                showReleaseSummary: showReleaseSummary
            )
            .navigationSplitViewColumnWidth(min: 350, ideal: 400, max: 460)
        } detail: {
            HistoryView(
                store: store,
                edition: edition,
                showStableBuilds: $showStableBuilds,
                showRCBuilds: $showRCBuilds,
                showBetaBuilds: $showBetaBuilds,
                showDevBuilds: $showDevBuilds,
                inspectedReleaseID: $inspectedReleaseID,
                downloadSource: downloadSourceConfiguration,
                searchText: searchText
            )
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let job = store.activeJob {
                ActivityBar(store: store, job: job)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(L10n.tr("edition"), selection: $editionRawValue) {
                    ForEach(GodotEdition.allCases) { edition in
                        Text(verbatim: edition.title).tag(edition.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 164)
                .help(L10n.tr("edition_picker_help"))

                Button {
                    Task { await store.loadReleases(forceRefresh: true) }
                } label: {
                    Label(L10n.tr("refresh_versions"), systemImage: "arrow.clockwise")
                }
                .help(L10n.tr("refresh_help"))
                .disabled(store.isLoading)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: L10n.tr("search_versions"))
        .task {
            if store.releases.isEmpty {
                await store.loadReleases(forceRefresh: refreshOnLaunch)
            }
        }
        .alert(item: $store.completion) { completion in
            Alert(
                title: Text(L10n.tr(completion.behavior == .update ? "update_complete" : "install_complete")),
                message: Text(completion.behavior == .update
                    ? L10n.tr("updated_as", completion.version, completion.applicationURL.lastPathComponent)
                    : L10n.tr("installed_as", completion.version, completion.applicationURL.lastPathComponent)),
                primaryButton: .default(Text(L10n.tr("show_in_finder"))) {
                    store.revealInstalledApplication(completion.applicationURL)
                },
                secondaryButton: .cancel(Text(L10n.tr("done")))
            )
        }
        .alert(item: $store.pendingInstallation) { pending in
            let behavior = InstallationBehavior.current()
            return Alert(
                title: Text(L10n.tr(behavior == .update
                    ? "confirm_preview_update_title"
                    : "confirm_preview_title")),
                message: Text(L10n.tr(behavior == .update
                    ? "confirm_preview_update_message"
                    : "confirm_preview_message", pending.release.displayVersion)),
                primaryButton: .default(Text(behavior.title)) {
                    store.confirmPendingInstallation()
                },
                secondaryButton: .cancel {
                    store.pendingInstallation = nil
                }
            )
        }
    }
}
