import Foundation

enum InstallationPhase: String, Codable, Sendable {
    case preparing
    case downloading
    case verifying
    case extracting
    case installing
    case completed
    case failed
    case cancelled

    func title(for behavior: InstallationBehavior) -> String {
        switch self {
        case .preparing: L10n.tr("phase_preparing")
        case .downloading: L10n.tr("phase_downloading")
        case .verifying: L10n.tr("phase_verifying")
        case .extracting: L10n.tr("phase_extracting")
        case .installing: L10n.tr(behavior == .update ? "phase_updating" : "phase_installing")
        case .completed: L10n.tr(behavior == .update ? "phase_update_completed" : "phase_completed")
        case .failed: L10n.tr(behavior == .update ? "phase_update_failed" : "phase_failed")
        case .cancelled: L10n.tr("phase_cancelled")
        }
    }

    var canCancel: Bool {
        self == .preparing || self == .downloading || self == .verifying
    }

    var isActive: Bool {
        switch self {
        case .preparing, .downloading, .verifying, .extracting, .installing: true
        case .completed, .failed, .cancelled: false
        }
    }
}

struct InstallationJob: Identifiable, Sendable {
    let id: UUID
    let releaseID: Int64
    let version: String
    let edition: GodotEdition
    let behavior: InstallationBehavior
    var phase: InstallationPhase
    var completedBytes: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double
    var errorMessage: String?
    var installedURL: URL?

    var progress: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

struct InstallationReceipt: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let releaseID: Int64
    let version: String
    let edition: GodotEdition
    let installedAt: Date
    let applicationURL: URL
}

struct InstallationCompletion: Identifiable, Sendable {
    let id = UUID()
    let version: String
    let applicationURL: URL
    let behavior: InstallationBehavior
}

struct PendingInstallation: Identifiable, Sendable {
    let id = UUID()
    let release: GodotRelease
    let edition: GodotEdition
}
