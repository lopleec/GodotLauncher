import CryptoKit
import Foundation

enum IntegrityError: LocalizedError {
    case unsupportedDigest
    case mismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedDigest: L10n.tr("unsupported_digest")
        case .mismatch: L10n.tr("digest_mismatch")
        }
    }
}

actor ArchiveIntegrityVerifier {
    func verify(fileURL: URL, expectedDigest: String) throws {
        let parts = expectedDigest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "sha256" else {
            throw IntegrityError.unsupportedDigest
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(parts[1]) == .orderedSame else {
            throw IntegrityError.mismatch
        }
    }
}
