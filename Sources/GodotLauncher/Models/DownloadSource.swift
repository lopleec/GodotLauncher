import Foundation

enum DownloadSource: String, CaseIterable, Identifiable, Sendable {
    case official
    case godotHub
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official: L10n.tr("source_official")
        case .godotHub: "GodotHub.com"
        case .custom: L10n.tr("source_custom")
        }
    }

    var description: String {
        switch self {
        case .official: L10n.tr("source_official_help")
        case .godotHub: L10n.tr("source_godothub_help")
        case .custom: L10n.tr("source_custom_help")
        }
    }
}

struct DownloadSourceConfiguration: Sendable {
    let source: DownloadSource
    let customTemplate: String
    let customSupportsPreviews: Bool

    static func current(defaults: UserDefaults = .standard) -> DownloadSourceConfiguration {
        let rawValue = defaults.string(forKey: PreferenceKey.downloadSource) ?? ""
        return DownloadSourceConfiguration(
            source: DownloadSource(rawValue: rawValue) ?? .official,
            customTemplate: defaults.string(forKey: PreferenceKey.customDownloadTemplate) ?? "",
            customSupportsPreviews: defaults.bool(forKey: PreferenceKey.customSourceSupportsPreviews)
        )
    }

    func downloadURL(for release: GodotRelease, asset: ReleaseAsset) -> URL? {
        switch source {
        case .official:
            return asset.downloadURL
        case .godotHub:
            guard release.isStable,
                  let tag = Self.encodedPathSegment(release.tagName),
                  let assetName = Self.encodedPathSegment(asset.name) else { return nil }
            return AppConstants.URLs.godotHubDownloadURL(encodedTag: tag, encodedAssetName: assetName)
        case .custom:
            guard !release.prerelease || customSupportsPreviews,
                  customTemplate.contains("{asset}"),
                  let tag = Self.encodedPathSegment(release.tagName),
                  let assetName = Self.encodedPathSegment(asset.name) else { return nil }
            let value = customTemplate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "{tag}", with: tag)
                .replacingOccurrences(of: "{asset}", with: assetName)
            guard let url = URL(string: value),
                  url.scheme?.lowercased() == "https",
                  url.host?.isEmpty == false else { return nil }
            return url
        }
    }

    func unavailableReason(for release: GodotRelease, asset: ReleaseAsset?) -> String? {
        guard let asset else { return L10n.tr("missing_macos_asset", "") }
        if source == .godotHub, !release.isStable {
            return L10n.tr("godothub_stable_only")
        }
        if source == .custom, release.prerelease, !customSupportsPreviews {
            return L10n.tr("custom_preview_disabled")
        }
        if source == .custom, customValidationMessage != nil {
            return customValidationMessage
        }
        return downloadURL(for: release, asset: asset) == nil
            ? L10n.tr("download_source_unavailable", source.title)
            : nil
    }

    var customValidationMessage: String? {
        guard source == .custom else { return nil }
        let value = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return L10n.tr("custom_template_required") }
        guard value.contains("{asset}") else { return L10n.tr("custom_template_asset_required") }
        let example = value
            .replacingOccurrences(of: "{tag}", with: "4.7-stable")
            .replacingOccurrences(of: "{asset}", with: "Godot.zip")
        guard let url = URL(string: example),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return L10n.tr("custom_template_invalid")
        }
        return nil
    }

    private static func encodedPathSegment(_ value: String) -> String? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
