import Foundation

struct ReleaseListRow: Identifiable, Hashable {
    let release: GodotRelease
    let edition: GodotEdition

    var id: GodotRelease.ID {
        release.id
    }

    var displayVersion: String {
        release.displayVersion
    }

    var channelTitle: String {
        release.channelTitle
    }

    var publishedAt: Date {
        release.publishedAt
    }

    var macAsset: ReleaseAsset? {
        release.macAsset(for: edition)
    }

    var packageSize: Int64 {
        macAsset?.size ?? -1
    }
}
