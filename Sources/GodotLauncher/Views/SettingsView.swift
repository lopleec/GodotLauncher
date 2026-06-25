import SwiftUI

struct SettingsView: View {
    let store: LauncherStore

    @AppStorage(PreferenceKey.appLanguage) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(PreferenceKey.selectedEdition) private var selectedEdition = GodotEdition.standard.rawValue
    @AppStorage(PreferenceKey.showStableBuilds) private var showStableBuilds = true
    @AppStorage(PreferenceKey.showRCBuilds) private var showRCBuilds = true
    @AppStorage(PreferenceKey.showBetaBuilds) private var showBetaBuilds = true
    @AppStorage(PreferenceKey.showDevBuilds) private var showDevBuilds = true
    @AppStorage(PreferenceKey.confirmPreviewInstalls) private var confirmPreviewInstalls = true
    @AppStorage(PreferenceKey.refreshOnLaunch) private var refreshOnLaunch = false
    @AppStorage(PreferenceKey.cacheDuration) private var cacheDuration = ReleaseCacheDuration.thirtyMinutes.rawValue
    @AppStorage(PreferenceKey.showReleaseSummary) private var showReleaseSummary = true
    @AppStorage(PreferenceKey.completionNotifications) private var completionNotifications = true
    @AppStorage(PreferenceKey.revealAfterInstall) private var revealAfterInstall = true
    @AppStorage(PreferenceKey.launchAfterInstall) private var launchAfterInstall = false
    @AppStorage(PreferenceKey.downloadConnections) private var downloadConnections = 6
    @AppStorage(PreferenceKey.installationLocation) private var installationLocation = InstallationLocation.systemApplications.rawValue
    @AppStorage(PreferenceKey.installationBehavior) private var installationBehavior = InstallationBehavior.install.rawValue
    @AppStorage(PreferenceKey.keepDownloadedArchives) private var keepDownloadedArchives = false
    @AppStorage(PreferenceKey.downloadSource) private var downloadSourceRawValue = DownloadSource.official.rawValue
    @AppStorage(PreferenceKey.customDownloadTemplate) private var customDownloadTemplate = ""
    @AppStorage(PreferenceKey.customSourceSupportsPreviews) private var customSourceSupportsPreviews = false
    @State private var cacheWasCleared = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label(L10n.tr("general"), systemImage: "gearshape") }

            versionSettings
                .tabItem { Label(L10n.tr("versions"), systemImage: "square.stack.3d.up") }

            downloadSettings
                .tabItem { Label(L10n.tr("downloads"), systemImage: "arrow.down.circle") }

            completionSettings
                .tabItem { Label(L10n.tr("completion"), systemImage: "checkmark.circle") }
        }
        .frame(width: 620, height: 500)
        .scenePadding()
    }

    private var generalSettings: some View {
        Form {
            Section(L10n.tr("language")) {
                Picker(L10n.tr("app_language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language.rawValue)
                    }
                }
                Text(L10n.tr("language_change_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("defaults")) {
                Picker(L10n.tr("default_edition"), selection: $selectedEdition) {
                    ForEach(GodotEdition.allCases) { edition in
                        Text(verbatim: edition.title).tag(edition.rawValue)
                    }
                }
                Toggle(L10n.tr("show_release_summary"), isOn: $showReleaseSummary)
            }

            Section(L10n.tr("updates")) {
                Toggle(L10n.tr("refresh_on_launch"), isOn: $refreshOnLaunch)
                Picker(L10n.tr("cache_duration"), selection: $cacheDuration) {
                    ForEach(ReleaseCacheDuration.allCases) { duration in
                        Text(verbatim: duration.title).tag(duration.rawValue)
                    }
                }
                HStack {
                    Button(L10n.tr("clear_release_cache")) {
                        Task {
                            await store.clearReleaseCache()
                            cacheWasCleared = true
                        }
                    }
                    if cacheWasCleared {
                        Label(L10n.tr("cache_cleared"), systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var versionSettings: some View {
        Form {
            Section(L10n.tr("visible_channels")) {
                Toggle(L10n.tr("channel_stable"), isOn: $showStableBuilds)
                Toggle("Release Candidate (RC)", isOn: $showRCBuilds)
                Toggle("Beta", isOn: $showBetaBuilds)
                Toggle(L10n.tr("development_builds"), isOn: $showDevBuilds)
            }

            Section(L10n.tr("safety")) {
                Toggle(L10n.tr("confirm_preview_installs"), isOn: $confirmPreviewInstalls)
                Text(L10n.tr("preview_warning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var downloadSettings: some View {
        Form {
            Section(L10n.tr("download_source")) {
                Picker(L10n.tr("download_source"), selection: $downloadSourceRawValue) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(verbatim: source.title).tag(source.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(downloadSourceConfiguration.source.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if downloadSourceConfiguration.source == .godotHub {
                    Label(L10n.tr("godothub_stable_only"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Link("godothub.com/download", destination: AppConstants.URLs.godotHubDownloadPage)
                        .font(.caption)
                }

                if downloadSourceConfiguration.source == .custom {
                    TextField(
                        L10n.tr("custom_url_template"),
                        text: $customDownloadTemplate,
                        prompt: Text("https://example.com/{tag}/{asset}")
                    )
                    .textFieldStyle(.roundedBorder)

                    Text(L10n.tr("custom_template_help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(L10n.tr("custom_supports_previews"), isOn: $customSourceSupportsPreviews)

                    if let message = downloadSourceConfiguration.customValidationMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section(L10n.tr("parallel_download")) {
                Stepper(value: $downloadConnections, in: 2...8) {
                    LabeledContent(L10n.tr("connections"), value: "\(downloadConnections)")
                }
                Text(L10n.tr("parallel_download_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("installation")) {
                Picker(L10n.tr("default_action"), selection: $installationBehavior) {
                    ForEach(InstallationBehavior.allCases) { behavior in
                        Text(verbatim: behavior.title).tag(behavior.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedInstallationBehavior.help)
                    .font(.caption)
                    .foregroundStyle(selectedInstallationBehavior == .update ? .orange : .secondary)

                Picker(L10n.tr("install_location"), selection: $installationLocation) {
                    ForEach(InstallationLocation.allCases) { location in
                        Text(verbatim: location.title).tag(location.rawValue)
                    }
                }
                Toggle(L10n.tr("keep_downloaded_archives"), isOn: $keepDownloadedArchives)
                Text(keepDownloadedArchives
                     ? L10n.tr("archive_kept_location")
                     : L10n.tr("temporary_files_removed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("integrity")) {
                Label(L10n.tr("sha256_always_enabled"), systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var downloadSourceConfiguration: DownloadSourceConfiguration {
        DownloadSourceConfiguration(
            source: DownloadSource(rawValue: downloadSourceRawValue) ?? .official,
            customTemplate: customDownloadTemplate,
            customSupportsPreviews: customSourceSupportsPreviews
        )
    }

    private var selectedInstallationBehavior: InstallationBehavior {
        InstallationBehavior(rawValue: installationBehavior) ?? .install
    }

    private var completionSettings: some View {
        Form {
            Section(L10n.tr("after_installation")) {
                Toggle(L10n.tr("send_notification"), isOn: $completionNotifications)
                Toggle(L10n.tr("reveal_in_finder"), isOn: $revealAfterInstall)
                Toggle(L10n.tr("launch_godot"), isOn: $launchAfterInstall)
            }
        }
        .formStyle(.grouped)
    }
}
