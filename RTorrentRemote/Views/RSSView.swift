import SwiftUI
import Foundation

struct RSSView: View {
    @ObservedObject var viewModel: RSSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("URL del feed RSS", text: $viewModel.newFeedURL)
                    .textFieldStyle(.roundedBorder)
                Button("Añadir") { viewModel.addFeed() }
                    .disabled(viewModel.newFeedURL.isEmpty)
            }
            .padding()

            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label("RSS no disponible", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            List(viewModel.feeds) { feed in
                VStack(alignment: .leading) {
                    Text(feed.url).lineLimit(1)
                    Text("\(feed.itemCount) elementos · actualizado \(feed.lastUpdate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Eliminar", role: .destructive) { viewModel.removeFeed(feed) }
                }
            }
            .listStyle(.inset)
            .overlay {
                if viewModel.feeds.isEmpty && viewModel.errorMessage == nil && !viewModel.isLoading {
                    Text("Sin feeds RSS configurados")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("RSS")
        .task { await viewModel.refresh() }
    }
}
