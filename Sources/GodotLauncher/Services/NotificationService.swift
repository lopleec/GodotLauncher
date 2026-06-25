import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func sendInstallationCompleted(
        version: String,
        applicationName: String,
        behavior: InstallationBehavior
    ) async {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr(behavior == .update
            ? "notification_update_complete"
            : "notification_install_complete")
        content.body = L10n.tr(behavior == .update
            ? "notification_updated_as"
            : "notification_installed_as", version, applicationName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
