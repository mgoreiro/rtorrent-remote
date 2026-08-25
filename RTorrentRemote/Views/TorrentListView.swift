import SwiftUI

struct TorrentListView: View {
    @ObservedObject var viewModel: TorrentListViewModel
    @Binding var selectedTorrent: Torrent?
    @Binding var showingAddTorrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            List(viewModel.filteredTorrents, selection: Binding(
                get: { selectedTorrent?.hash },
                set: { hash in selectedTorrent = viewModel.torrents.first { $0.hash == hash } }
            )) { torrent in
                TorrentRowView(torrent: torrent, viewModel: viewModel)
                    .tag(torrent.hash)
                    .contextMenu { contextMenu(for: torrent) }
            }
            .listStyle(.inset)
            .overlay {
                if viewModel.filteredTorrents.isEmpty && !viewModel.isLoading {
                    emptyState
                }
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Buscar torrents")
        .navigationTitle("Torrents")
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No hay torrents que mostrar")
                .foregroundStyle(.secondary)
            Button("Añadir torrent") { showingAddTorrent = true }
        }
    }

    @ViewBuilder
    private func contextMenu(for torrent: Torrent) -> some View {
        if torrent.isActive {
            Button("Pausar") { viewModel.pause(torrent) }
        } else {
            Button("Reanudar") { viewModel.resume(torrent) }
        }
        Button("Iniciar") { viewModel.start(torrent) }
        Button("Detener") { viewModel.stop(torrent) }
        Divider()
        Button("Verificar hash") { viewModel.recheck(torrent) }
        Divider()
        Button("Eliminar…", role: .destructive) { viewModel.remove(torrent) }
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }
}
