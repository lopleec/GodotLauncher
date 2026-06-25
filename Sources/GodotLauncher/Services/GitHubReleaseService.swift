import Foundation

struct ReleaseFetchResult: Sendable {
    let releases: [GodotRelease]
    let usedCachedData: Bool
}

enum ReleaseServiceError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.tr("release_invalid_response")
        case let .httpStatus(code, message):
            if code == 403 {
                L10n.tr("github_rate_limited")
            } else if let message, !message.isEmpty {
                L10n.tr("release_http_error_message", code, message)
            } else {
                L10n.tr("release_http_error", code)
            }
        case .emptyResponse:
            L10n.tr("no_releases_found")
        }
    }
}

actor GitHubReleaseService {
    private struct CachedPayload: Codable {
        let fetchedAt: Date
        let releases: [GodotRelease]
    }

    private struct GitHubErrorPayload: Decodable {
        let message: String?
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AppConstants.Network.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.Network.releaseFetchTimeout
        configuration.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": AppConstants.userAgent
        ]
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.fileManager = fileManager
    }

    func fetchReleases(
        forceRefresh: Bool,
        cacheLifetime: TimeInterval,
        pageChanged: @MainActor @Sendable (Int) -> Void
    ) async throws -> ReleaseFetchResult {
        if !forceRefresh,
           let cached = try? readCache(),
           Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return ReleaseFetchResult(releases: cached.releases, usedCachedData: true)
        }

        do {
            var allReleases: [GodotRelease] = []
            for page in 1...AppConstants.Network.maxGitHubReleasePages {
                await pageChanged(page)
                let pageReleases = try await fetchPage(page)
                allReleases.append(contentsOf: pageReleases)
                if pageReleases.count < AppConstants.Network.githubPerPage { break }
            }

            let releases = allReleases
                .filter { !$0.draft }
                .sorted { $0.publishedAt > $1.publishedAt }
            guard !releases.isEmpty else { throw ReleaseServiceError.emptyResponse }

            try? writeCache(CachedPayload(fetchedAt: Date(), releases: releases))
            return ReleaseFetchResult(releases: releases, usedCachedData: false)
        } catch {
            if let cached = try? readCache(), !cached.releases.isEmpty {
                return ReleaseFetchResult(releases: cached.releases, usedCachedData: true)
            }
            throw error
        }
    }

    private func fetchPage(_ page: Int) async throws -> [GodotRelease] {
        var components = URLComponents(url: AppConstants.URLs.githubReleasesAPI, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(AppConstants.Network.githubPerPage)),
            URLQueryItem(name: "page", value: String(page))
        ]

        guard let url = components.url else {
            throw ReleaseServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReleaseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try? decoder.decode(GitHubErrorPayload.self, from: data).message
            throw ReleaseServiceError.httpStatus(httpResponse.statusCode, message ?? nil)
        }
        return try decoder.decode([GodotRelease].self, from: data)
    }

    private func cacheURL() throws -> URL {
        try AppDirectories.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(AppConstants.Cache.currentReleaseCacheFileName)
    }

    private func readCache() throws -> CachedPayload {
        let data = try Data(contentsOf: cacheURL())
        return try decoder.decode(CachedPayload.self, from: data)
    }

    private func writeCache(_ payload: CachedPayload) throws {
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL(), options: .atomic)
    }

    func clearCache() throws {
        let currentURL = try cacheURL()
        let legacyURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent(AppConstants.Cache.legacyReleaseCacheFileName)
        for url in [currentURL, legacyURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
