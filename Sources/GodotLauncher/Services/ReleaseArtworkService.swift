import Foundation

actor ReleaseArtworkService {
    static let shared = ReleaseArtworkService()

    private let session: URLSession
    private var cachedURLs: [String: URL] = [:]
    private var unavailableTags: Set<String> = []

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.Network.artworkRequestTimeout
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpAdditionalHeaders = ["User-Agent": AppConstants.userAgent]
        session = URLSession(configuration: configuration)
    }

    func artworkURL(for tag: String) async -> URL? {
        if let cached = cachedURLs[tag] { return cached }
        guard !unavailableTags.contains(tag),
              let archiveURL = GodotRelease.archivePageURL(for: tag) else { return nil }

        do {
            let (data, response) = try await session.data(from: archiveURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let html = String(data: data, encoding: .utf8),
                  let path = Self.extractArtworkPath(from: html),
                  let resolvedURL = URL(string: path, relativeTo: archiveURL)?.absoluteURL,
                  resolvedURL.scheme == "https",
                  resolvedURL.host == AppConstants.URLs.godotWebsiteHost else {
                unavailableTags.insert(tag)
                return nil
            }
            cachedURLs[tag] = resolvedURL
            return resolvedURL
        } catch {
            return nil
        }
    }

    static func extractArtworkPath(from html: String) -> String? {
        let pattern = #"notes-thumbnail[^>]*background-image:\s*url\(([^)]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }
}
