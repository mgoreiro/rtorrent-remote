import SwiftUI

enum SidebarSection: Hashable {
    case filter(TorrentFilter)
    case label(String)
    case rss
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var listVM = TorrentListViewModel()
    @StateObject private var rssVM = RSSViewModel()

    @State private var selection: SidebarSection? = .filter(.all)
    @State private var selectedTorrent: Torrent?
    @State private var showingAddTorrent = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, labels: listVM.availableLabels)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            Group {
                switch selection {
                case .rss:
                    RSSView(viewModel: rssVM)
                default:
                    TorrentListView(
                        viewModel: listVM,
                        selectedTorrent: $selectedTorrent,
                        showingAddTorrent: $showingAddTorrent
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            if let selectedTorrent, let refreshed = listVM.torrents.first(where: { $0.hash == selectedTorrent.hash }) {
                TorrentDetailView(torrent: refreshed, viewModel: listVM)
            } else {
                ContentUnavailableFallback()
            }
        }
        .onChange(of: selection) { _, newValue in
            switch newValue {
            case .filter(let f): listVM.filter = f; listVM.selectedLabel = nil
            case .label(let l): listVM.selectedLabel = l; listVM.filter = .all
            case .rss, .none: break
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddTorrent = true
                } label: {
                    Label("Añadir torrent", systemImage: "plus")
                }
                .disabled(appState.client == nil)

                Button {
                    Task { await listVM.refresh() }
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .disabled(appState.client == nil)

                Button {
                    showingSettings = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            SpeedStatusBar(viewModel: listVM)
        }
        .sheet(isPresented: $showingAddTorrent) {
            AddTorrentView(viewModel: listVM, availableLabels: listVM.availableLabels)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 460, height: 480)
        }
        .onAppear {
            listVM.attach(to: appState)
            rssVM.attach(to: appState)
            listVM.startPolling()
            if appState.client != nil {
                showingSettings = false
            } else {
                showingSettings = true
            }
        }
        .onDisappear {
            listVM.stopPolling()
        }
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Selecciona un torrent")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
