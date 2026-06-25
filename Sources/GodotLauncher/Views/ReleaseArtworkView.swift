import SwiftUI

struct ReleaseArtworkView: View {
    let release: GodotRelease
    @State private var artworkURL: URL?
    @State private var didFinishLookup = false

    var body: some View {
        GroupBox(L10n.tr("version_artwork")) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        artwork
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let archiveURL = release.archivePageURL {
                    Link(destination: archiveURL) {
                        Label(L10n.tr("open_archive_page"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: release.id) {
            artworkURL = nil
            didFinishLookup = false
            artworkURL = await ReleaseArtworkService.shared.artworkURL(for: release.tagName)
            didFinishLookup = true
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL {
            AsyncImage(url: artworkURL, transaction: Transaction(animation: .easeInOut)) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    unavailableArtwork
                case .empty:
                    loadingArtwork
                @unknown default:
                    unavailableArtwork
                }
            }
        } else if didFinishLookup {
            unavailableArtwork
        } else {
            loadingArtwork
        }
    }

    private var loadingArtwork: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.35))
            ProgressView(L10n.tr("loading_artwork"))
                .controlSize(.small)
        }
    }

    private var unavailableArtwork: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.35))
            Label(L10n.tr("artwork_unavailable"), systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
