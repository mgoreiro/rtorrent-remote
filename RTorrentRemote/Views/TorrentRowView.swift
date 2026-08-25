import SwiftUI

struct TorrentRowView: View {
    let torrent: Torrent
    @ObservedObject var viewModel: TorrentListViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: torrent.status.symbolName)
                .foregroundStyle(color(for: torrent.status))
                .font(.title3)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(torrent.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                ProgressView(value: torrent.progress)
                    .progressViewStyle(.linear)
                    .tint(color(for: torrent.status))

                HStack(spacing: 10) {
                    Text(Formatters.percent(torrent.progress))
                    Text("↓ \(Formatters.rate(torrent.downRate))")
                    Text("↑ \(Formatters.rate(torrent.upRate))")
                    if !torrent.label.isEmpty {
                        Text(torrent.label)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(Formatters.bytes(torrent.sizeBytes))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            quickActionButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var quickActionButton: some View {
        Button {
            torrent.isActive ? viewModel.pause(torrent) : viewModel.resume(torrent)
        } label: {
            Image(systemName: torrent.isActive ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.borderless)
        .help(torrent.isActive ? "Pausar" : "Reanudar")
    }

    private func color(for status: TorrentStatus) -> Color {
        switch status {
        case .downloading: return .blue
        case .seeding: return .green
        case .paused, .stopped: return .secondary
        case .completed: return .green
        case .hashing: return .orange
        case .error: return .red
        }
    }
}
