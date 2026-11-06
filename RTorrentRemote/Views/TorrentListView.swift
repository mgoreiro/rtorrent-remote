import SwiftUI

struct TorrentListView: View {
    @ObservedObject var viewModel: TorrentListViewModel
    @Binding var selection: Set<String>
    @Binding var showingAddTorrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error, countdown: viewModel.retryCountdown, onRetry: { viewModel.retryNow() })
            }

            List(viewModel.filteredTorrents, selection: $selection) { torrent in
                TorrentRowView(torrent: torrent, viewModel: viewModel)
                    .tag(torrent.hash)
            }
            .contextMenu(forSelectionType: String.self) { hashes in
                contextMenu(for: torrents(for: hashes))
            }
            .onDeleteCommand { viewModel.torrentsPendingRemoval = selectedTorrents }
            .onKeyPress(.space) {
                guard !selectedTorrents.isEmpty else { return .ignored }
                viewModel.togglePause(selectedTorrents)
                return .handled
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
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Ordenar por", selection: $viewModel.sortKey) {
                        ForEach(TorrentSortKey.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Toggle("Orden ascendente", isOn: $viewModel.sortAscending)
                } label: {
                    Label("Ordenar", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var selectedTorrents: [Torrent] { torrents(for: selection) }

    private func torrents(for hashes: Set<String>) -> [Torrent] {
        viewModel.torrents.filter { hashes.contains($0.hash) }
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
    private func contextMenu(for torrents: [Torrent]) -> some View {
        if !torrents.isEmpty {
            Button(torrents.allSatisfy(\.isActive) ? "Pausar" : "Reanudar") { viewModel.togglePause(torrents) }
            Button("Iniciar") { viewModel.start(torrents) }
            Button("Detener") { viewModel.stop(torrents) }
            Divider()
            Menu("Etiqueta") {
                Button("Sin etiqueta") { viewModel.setLabel(torrents, label: "") }
                ForEach(viewModel.availableLabels, id: \.self) { label in
                    Button(label) { viewModel.setLabel(torrents, label: label) }
                }
            }
            Button("Verificar hash") { viewModel.recheck(torrents) }
            Divider()
            Button("Eliminar…", role: .destructive) { viewModel.torrentsPendingRemoval = torrents }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    var countdown: Int?
    var onRetry: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if let countdown {
                Text("Reintentando en \(countdown) s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reintentar ahora", action: onRetry)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }
}
