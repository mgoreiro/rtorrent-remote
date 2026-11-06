import SwiftUI

enum SidebarSection: Hashable {
    case filter(TorrentFilter)
    case label(String)
    case rss
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var bot: TelegramBot
    @ObservedObject var listVM: TorrentListViewModel
    @StateObject private var rssVM = RSSViewModel()

    @State private var selection: SidebarSection? = .filter(.all)
    @State private var torrentSelection: Set<String> = []
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
                        selection: $torrentSelection,
                        showingAddTorrent: $showingAddTorrent
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            if torrentSelection.count == 1, let hash = torrentSelection.first,
               let torrent = listVM.torrents.first(where: { $0.hash == hash }) {
                TorrentDetailView(torrent: torrent, viewModel: listVM)
            } else if torrentSelection.count > 1 {
                MultiSelectionSummary(torrents: listVM.torrents.filter { torrentSelection.contains($0.hash) })
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
                if appState.profiles.count > 1 {
                    Menu {
                        ForEach(appState.profiles) { p in
                            Button {
                                appState.selectProfile(p.id)
                            } label: {
                                Label(p.name, systemImage: p.id == appState.profile.id ? "checkmark" : "server.rack")
                            }
                        }
                    } label: {
                        Label(appState.profile.name, systemImage: "server.rack")
                    }
                }
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
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { !listVM.torrentsPendingRemoval.isEmpty },
                set: { if !$0 { listVM.torrentsPendingRemoval = [] } }
            ),
            titleVisibility: .visible,
            presenting: listVM.torrentsPendingRemoval
        ) { torrents in
            Button("Eliminar solo el torrent") { listVM.remove(torrents) }
            Button(Preferences.trashPath.isEmpty ? "Eliminar torrent y archivos" : "Eliminar torrent y mover archivos a la papelera",
                   role: .destructive) { listVM.removeWithData(torrents) }
            Button("Cancelar", role: .cancel) {}
        } message: { torrents in
            Text(removalMessage(for: torrents))
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { listVM.addFromExternal(url: $0) }
            return !urls.isEmpty
        }
        .dropDestination(for: String.self) { strings, _ in
            let magnets = strings.filter { $0.hasPrefix("magnet:") || $0.hasPrefix("http") }
            magnets.forEach { listVM.addTorrent(uri: $0, startImmediately: true, label: "") }
            return !magnets.isEmpty
        }
        .onOpenURL { listVM.addFromExternal(url: $0) }
        .onChange(of: appState.profile.id) { _, _ in
            torrentSelection = []
            listVM.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addTorrentRequested)) { _ in
            showingAddTorrent = true
        }
        .sheet(isPresented: $showingAddTorrent) {
            AddTorrentView(viewModel: listVM, availableLabels: listVM.availableLabels)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(bot)
                .frame(width: 460, height: 640)
        }
        .onAppear {
            listVM.attach(to: appState)
            rssVM.attach(to: appState)
            listVM.startPolling()
            Notifier.requestAuthorization()
            bot.attach(appState: appState, listVM: listVM)
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

extension ContentView {
    fileprivate var removalTitle: String {
        let list = listVM.torrentsPendingRemoval
        if list.count == 1 { return "¿Eliminar \"\(list[0].name)\"?" }
        return "¿Eliminar \(list.count) torrents?"
    }

    fileprivate func removalMessage(for torrents: [Torrent]) -> String {
        let total = Formatters.bytes(torrents.reduce(0) { $0 + $1.sizeBytes })
        let dirs = Set(torrents.map(\.baseDirectory)).sorted().prefix(3).joined(separator: "\n")
        let trash = Preferences.trashPath
        let fate = trash.isEmpty
            ? "Eliminar los archivos borra los datos del servidor y no se puede deshacer."
            : "Los archivos se moverán a \(trash) en el servidor."
        return "\(total) en:\n\(dirs)\n\n\(fate)"
    }
}

extension Notification.Name {
    static let addTorrentRequested = Notification.Name("addTorrentRequested")
}

private struct MultiSelectionSummary: View {
    let torrents: [Torrent]
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("\(torrents.count) torrents seleccionados").font(.title3)
            Text(Formatters.bytes(torrents.reduce(0) { $0 + $1.sizeBytes }))
                .foregroundStyle(.secondary)
            Text("Usa el menú contextual (clic derecho) para actuar sobre todos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
