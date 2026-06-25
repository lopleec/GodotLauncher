import SwiftUI

struct ActivityBar: View {
    let store: LauncherStore
    let job: InstallationJob

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                phaseIcon

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(verbatim: L10n.tr("job_title", job.version, job.phase.title(for: job.behavior)))
                            .font(.subheadline.weight(.medium))
                        if job.phase == .downloading {
                            Text(verbatim: L10n.tr(
                                "download_progress_bytes",
                                AppFormatting.bytes(job.completedBytes),
                                AppFormatting.bytes(job.totalBytes)
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if job.phase == .downloading {
                        ProgressView(value: job.progress ?? 0)
                            .progressViewStyle(.linear)
                        HStack(spacing: 8) {
                            Text(AppFormatting.speed(job.bytesPerSecond))
                            if let remaining = AppFormatting.remaining(
                                bytes: max(0, job.totalBytes - job.completedBytes),
                                speed: job.bytesPerSecond
                            ) {
                                Text(verbatim: "· \(remaining)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else if job.phase == .verifying || job.phase == .extracting || job.phase == .installing || job.phase == .preparing {
                        ProgressView()
                            .progressViewStyle(.linear)
                    } else if let error = job.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if job.phase.canCancel {
                    Button(L10n.tr("cancel")) { store.cancelInstallation() }
                } else if job.phase.isActive {
                    EmptyView()
                } else if let url = job.installedURL {
                    Button(L10n.tr("open")) { store.launchInstalledApplication(url) }
                    Button(L10n.tr("show_in_finder")) { store.revealInstalledApplication(url) }
                    Button {
                        store.dismissActivity()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("close"))
                } else {
                    Button(L10n.tr("close")) { store.dismissActivity() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch job.phase {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        default:
            Image(systemName: job.behavior == .update ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        }
    }
}
