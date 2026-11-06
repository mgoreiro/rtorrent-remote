import SwiftUI
import Foundation

struct TorrentDetailView: View {
    let torrent: Torrent
    @ObservedObject var viewModel: TorrentListViewModel

    @State private var tab: Tab = .info
    @State private var files: [TorrentFile] = []
    @State private var isLoadingFiles = false
    @State private var labelDraft: String = ""
    @State private var filesErrorMessage: String?
    @State private var trackers: [TorrentTracker] = []
    @State private var peers: [TorrentPeer] = []
    @State private var moveDestination: String = ""
    @State private var showingMove = false

    enum Tab: String, CaseIterable, Identifiable {
        case info = "Información"
        case files = "Archivos"
        case trackers = "Trackers"
        case peers = "Pares"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            Divider().padding(.top, 8)

            switch tab {
            case .info: infoTab
            case .files: filesTab
            case .trackers: trackersTab
            case .peers: peersTab
            }
        }
        .navigationTitle(torrent.name)
        .task(id: torrent.hash) {
            labelDraft = torrent.label
            await loadFiles()
        }
        .task(id: "\(torrent.hash)-\(tab.rawValue)") {
            // Trackers and peers refresh every few seconds while their tab is visible.
            while !Task.isCancelled && (tab == .trackers || tab == .peers) {
                await loadTrackersOrPeers()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .alert("Mover datos", isPresented: $showingMove) {
            TextField("Carpeta destino en el servidor", text: $moveDestination)
            Button("Mover") { viewModel.move([torrent], to: moveDestination) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ruta absoluta en el servidor. El torrent se detendrá, los archivos se moverán y se reanudará si estaba activo.")
        }
    }

    private var trackersTab: some View {
        List(trackers) { tracker in
            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.url).lineLimit(1)
                Text("\(tracker.isEnabled ? "Activo" : "Desactivado") · \(tracker.seeders) seeders · \(tracker.leechers) leechers\(tracker.failures > 0 ? " · \(tracker.failures) fallos" : "")")
                    .font(.caption)
                    .foregroundStyle(tracker.failures > 0 ? .orange : .secondary)
            }
        }
        .listStyle(.inset)
        .overlay { if trackers.isEmpty { Text("Sin trackers").foregroundStyle(.secondary) } }
    }

    private var peersTab: some View {
        List(peers) { peer in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(peer.address):\(peer.port)")
                    Text(peer.client.isEmpty ? "Cliente desconocido" : peer.client)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(peer.percent)%").foregroundStyle(.secondary)
                Text("↓ \(Formatters.rate(peer.downRate))  ↑ \(Formatters.rate(peer.upRate))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .overlay { if peers.isEmpty { Text("Sin pares conectados").foregroundStyle(.secondary) } }
    }

    private func loadTrackersOrPeers() async {
        guard let client = viewModel.clientForDetail else { return }
        if tab == .trackers {
            trackers = (try? await client.fetchTrackers(hash: torrent.hash)) ?? trackers
        } else {
            peers = (try? await client.fetchPeers(hash: torrent.hash)) ?? peers
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(torrent.name)
                .font(.title3.weight(.semibold))
                .lineLimit(2)

            ProgressView(value: torrent.progress)
            HStack {
                Text("\(Formatters.percent(torrent.progress)) · \(Formatters.bytes(torrent.completedBytes)) de \(Formatters.bytes(torrent.sizeBytes))")
                Spacer()
                Text(torrent.status.label)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
    }

    private var infoTab: some View {
        Form {
            Section("Actividad") {
                LabeledContent("Descarga", value: Formatters.rate(torrent.downRate))
                LabeledContent("Subida", value: Formatters.rate(torrent.upRate))
                LabeledContent("Ratio", value: Formatters.ratio(torrent.ratio))
                LabeledContent("Peers conectados", value: "\(torrent.peersConnected)")
                LabeledContent("Seeders", value: "\(torrent.seedersConnected)")
                LabeledContent("ETA aprox.", value: Formatters.eta(bytesRemaining: torrent.sizeBytes - torrent.completedBytes, ratePerSecond: torrent.downRate))
            }

            Section("Ubicación") {
                LabeledContent("Carpeta", value: torrent.baseDirectory)
                LabeledContent("Hash", value: torrent.hash)
                    .textSelection(.enabled)
            }

            Section("Etiqueta") {
                HStack {
                    TextField("Sin etiqueta", text: $labelDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Guardar") {
                        viewModel.setLabel(torrent, label: labelDraft)
                    }
                    .disabled(labelDraft == torrent.label)
                }
            }

            Section("Acciones") {
                HStack(spacing: 10) {
                    Button(torrent.isActive ? "Pausar" : "Reanudar") {
                        torrent.isActive ? viewModel.pause(torrent) : viewModel.resume(torrent)
                    }
                    Button("Detener") { viewModel.stop(torrent) }
                    Button("Verificar hash") { viewModel.recheck(torrent) }
                    Button("Mover…") { moveDestination = torrent.baseDirectory; showingMove = true }
                    Button("Eliminar", role: .destructive) { viewModel.torrentsPendingRemoval = [torrent] }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var filesTab: some View {
        Group {
            if isLoadingFiles {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let filesErrorMessage {
                VStack(spacing: 8) {
                    Text(filesErrorMessage).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { await loadFiles() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files) { file in
                    FileRow(file: file) { newPriority in
                        setPriority(file: file, priority: newPriority)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func loadFiles() async {
        guard let client = viewModel.clientForDetail else { return }
        isLoadingFiles = true
        do {
            files = try await client.fetchFiles(hash: torrent.hash)
            filesErrorMessage = nil
        } catch {
            filesErrorMessage = error.localizedDescription
        }
        isLoadingFiles = false
    }

    private func setPriority(file: TorrentFile, priority: FilePriority) {
        guard let client = viewModel.clientForDetail else { return }
        Task {
            do {
                try await client.setFilePriority(hash: torrent.hash, index: file.index, priority: priority)
                await loadFiles()
            } catch {
                filesErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct FileRow: View {
    let file: TorrentFile
    let onPriorityChange: (FilePriority) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path).lineLimit(1)
                ProgressView(value: file.progress)
                Text(Formatters.bytes(file.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { file.priority },
                set: { onPriorityChange($0) }
            )) {
                ForEach(FilePriority.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .frame(width: 130)
        }
        .padding(.vertical, 2)
    }
}
