import Foundation

enum GodotEdition: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case dotnet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: L10n.tr("standard_edition")
        case .dotnet: L10n.tr("dotnet_edition")
        }
    }

    var shortTitle: String {
        switch self {
        case .standard: L10n.tr("standard_short")
        case .dotnet: ".NET"
        }
    }
}

enum ReleaseChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case releaseCandidate
    case beta
    case development
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: L10n.tr("channel_stable")
        case .releaseCandidate: "RC"
        case .beta: "Beta"
        case .development: L10n.tr("channel_development")
        case .preview: L10n.tr("channel_preview")
        }
    }

    var systemImage: String {
        switch self {
        case .stable: "checkmark.seal.fill"
        case .releaseCandidate: "checkmark.diamond.fill"
        case .beta: "testtube.2"
        case .development: "hammer.fill"
        case .preview: "sparkles"
        }
    }
}

struct ReleaseAsset: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let size: Int64
    let downloadURL: URL
    let downloadCount: Int
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case downloadURL = "browser_download_url"
        case downloadCount = "download_count"
        case digest
    }

    func using(downloadURL: URL) -> ReleaseAsset {
        ReleaseAsset(
            id: id,
            name: name,
            size: size,
            downloadURL: downloadURL,
            downloadCount: downloadCount,
            digest: digest
        )
    }
}

struct GodotRelease: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let tagName: String
    let name: String?
    let notes: String?
    let publishedAt: Date
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id, name, prerelease, draft, assets
        case tagName = "tag_name"
        case notes = "body"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    var displayVersion: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var archivePageURL: URL? {
        Self.archivePageURL(for: tagName)
    }

    static func archivePageURL(for tag: String) -> URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return AppConstants.URLs.godotArchivePageURL(encodedTag: encodedTag)
    }

    var isStable: Bool {
        !prerelease && displayVersion.localizedCaseInsensitiveContains("stable")
    }

    var channelTitle: String {
        channel.title
    }

    var channel: ReleaseChannel {
        let value = displayVersion.lowercased()
        if isStable { return .stable }
        if value.range(of: #"(?:^|[-.])rc\d*"#, options: .regularExpression) != nil {
            return .releaseCandidate
        }
        if value.contains("beta") { return .beta }
        if value.contains("alpha") || value.contains("dev") { return .development }
        return .preview
    }

    func plainSummary(maxLength: Int = 360) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        let paragraphs = notes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        let source = paragraphs.first { paragraph in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 40 && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("-")
        } ?? notes
        let plain: String
        if let attributed = try? AttributedString(markdown: source) {
            plain = String(attributed.characters)
        } else {
            plain = source
        }
        let collapsed = plain
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    func macAsset(for edition: GodotEdition) -> ReleaseAsset? {
        assets
            .filter { asset in
                let value = asset.name.lowercased()
                let isMac = value.contains("macos") || value.contains("osx")
                let isArchive = value.hasSuffix(".zip")
                let isDotNet = value.contains("mono") || value.contains("dotnet")
                let isEditor = !value.contains("template") && !value.contains("export")
                return isMac && isArchive && isEditor && (edition == .dotnet ? isDotNet : !isDotNet)
            }
            .max { assetScore($0.name) < assetScore($1.name) }
    }

    private func assetScore(_ name: String) -> Int {
        let value = name.lowercased()
        var score = 0
        if value.contains("macos.universal") { score += 100 }
        if value.contains("osx.universal") { score += 80 }
        if value.contains("arm64") { score += 50 }
        if value.contains("64") { score += 30 }
        if value.hasSuffix(".zip") { score += 10 }
        return score
    }
}
