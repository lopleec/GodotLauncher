import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.appLanguage: AppLanguage.system.rawValue,
            PreferenceKey.selectedEdition: GodotEdition.standard.rawValue,
            PreferenceKey.showStableBuilds: true,
            PreferenceKey.showRCBuilds: true,
            PreferenceKey.showBetaBuilds: true,
            PreferenceKey.showDevBuilds: true,
            PreferenceKey.confirmPreviewInstalls: true,
            PreferenceKey.refreshOnLaunch: false,
            PreferenceKey.cacheDuration: ReleaseCacheDuration.defaultValue.rawValue,
            PreferenceKey.showReleaseSummary: true,
            PreferenceKey.completionNotifications: true,
            PreferenceKey.revealAfterInstall: true,
            PreferenceKey.launchAfterInstall: false,
            PreferenceKey.downloadConnections: AppConstants.Downloads.defaultConnections,
            PreferenceKey.installationLocation: InstallationLocation.systemApplications.rawValue,
            PreferenceKey.installationBehavior: InstallationBehavior.install.rawValue,
            PreferenceKey.keepDownloadedArchives: false,
            PreferenceKey.downloadSource: DownloadSource.official.rawValue,
            PreferenceKey.customDownloadTemplate: "",
            PreferenceKey.customSourceSupportsPreviews: false
        ])
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GodotLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(PreferenceKey.appLanguage) private var appLanguageRawValue = AppLanguage.system.rawValue
    @State private var store = LauncherStore()

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup(AppConstants.displayName, id: AppConstants.mainWindowID) {
            ContentView(store: store)
                .id("main-\(appLanguageRawValue)")
                .frame(minWidth: 1_020, minHeight: 640)
                .environment(\.locale, appLanguage.locale)
                .background {
                    LanguageRuntimeBridge(language: appLanguage, role: .main)
                        .frame(width: 0, height: 0)
                }
        }
        .defaultSize(width: 1_120, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu(L10n.tr("versions")) {
                Button(L10n.tr("refresh_versions")) {
                    Task { await store.loadReleases(forceRefresh: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isLoading)

                Divider()

                Button(L10n.tr("cancel_current_install")) {
                    store.cancelInstallation()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.canCancelInstallation)
            }
        }

        Settings {
            SettingsView(store: store)
                .id("settings-\(appLanguageRawValue)")
                .environment(\.locale, appLanguage.locale)
                .background {
                    LanguageRuntimeBridge(language: appLanguage, role: .settings)
                        .frame(width: 0, height: 0)
                }
        }
    }
}
