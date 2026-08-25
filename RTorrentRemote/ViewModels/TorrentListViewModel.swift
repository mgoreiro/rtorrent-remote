import Foundation
import SwiftUI

enum TorrentFilter: String, CaseIterable, Identifiable {
    case all, downloading, seeding, paused, completed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .downloading: return "Descargando"
        case .seeding: return "Compartiendo"
        case .paused: return "En pausa"
        case .completed: return "Completados"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle"
        }
    }

    func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return torrent.status == .downloading
        case .seeding: return torrent.status == .seeding
        case .paused: return torrent.status == .paused || torrent.status == .stopped
        case .completed: return torrent.isComplete
        }
    }
}

@MainActor
final class TorrentListViewModel: ObservableObject {
    @Published var torrents: [Torrent] = []
    @Published var searchText: String = ""
    @Published var filter: TorrentFilter = .all
    @Published var selectedLabel: String? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var globalDownRate: Int64 = 0
    @Published var globalUpRate: Int64 = 0

    private var pollingTask: Task<Void, Never>?
    private weak var appState: AppState?

    var availableLabels: [String] {
        Set(torrents.map(\.label).filter { !$0.isEmpty }).sorted()
    }

    var filteredTorrents: [Torrent] {
        torrents
            .filter { filter.matches($0) }
            .filter { selectedLabel == nil || $0.label == selectedLabel }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func attach(to appState: AppState) {
        self.appState = appState
    }

    /// Exposes the active client for detail views (file listing, per-file priorities)
    /// that need direct calls beyond the actions already wrapped above.
    var clientForDetail: RTorrentClient? { appState?.client }

    func startPolling(interval: TimeInterval = 3) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard let client = appState?.client else { return }
        isLoading = true
        do {
            async let torrentsTask = client.fetchTorrents()
            async let statsTask = client.fetchSessionStats()
            let (fetched, stats) = try await (torrentsTask, statsTask)
            torrents = fetched
            globalDownRate = stats.downRate
            globalUpRate = stats.upRate
            errorMessage = nil
            appState?.isConnected = true
        } catch {
            errorMessage = error.localizedDescription
            appState?.isConnected = false
        }
        isLoading = false
    }

    // MARK: - Actions

    func perform(_ action: @escaping (RTorrentClient, String) async throws -> Void, on hash: String) {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await action(client, hash)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func start(_ torrent: Torrent) { perform({ try await $0.start(hash: $1) }, on: torrent.hash) }
    func stop(_ torrent: Torrent) { perform({ try await $0.stop(hash: $1) }, on: torrent.hash) }
    func pause(_ torrent: Torrent) { perform({ try await $0.pause(hash: $1) }, on: torrent.hash) }
    func resume(_ torrent: Torrent) { perform({ try await $0.resume(hash: $1) }, on: torrent.hash) }
    func remove(_ torrent: Torrent) { perform({ try await $0.remove(hash: $1) }, on: torrent.hash) }
    func recheck(_ torrent: Torrent) { perform({ try await $0.recheck(hash: $1) }, on: torrent.hash) }

    func setLabel(_ torrent: Torrent, label: String) {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.setLabel(hash: torrent.hash, label: label)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTorrent(uri: String, startImmediately: Bool, label: String) {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.addFromURI(uri, startImmediately: startImmediately, label: label.isEmpty ? nil : label)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTorrent(fileData: Data, startImmediately: Bool, label: String) {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.addFromFileData(fileData, startImmediately: startImmediately, label: label.isEmpty ? nil : label)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
