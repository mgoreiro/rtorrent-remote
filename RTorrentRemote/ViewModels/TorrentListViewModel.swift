import Foundation
import SwiftUI
import AppKit

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
    @Published var sortKey: TorrentSortKey = .name
    @Published var sortAscending = true
    /// Torrents awaiting delete confirmation (shown as a dialog by ContentView).
    @Published var torrentsPendingRemoval: [Torrent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var globalDownRate: Int64 = 0
    @Published var globalUpRate: Int64 = 0
    /// Seconds until the next automatic reconnection attempt (nil while connected).
    @Published var retryCountdown: Int?

    /// Callbacks fired when a torrent finishes downloading (used by notifications and the Telegram bot).
    var onTorrentCompleted: [(Torrent) -> Void] = []

    private var pollingTask: Task<Void, Never>?
    private weak var appState: AppState?
    private var consecutiveFailures = 0
    private var knownCompletion: [String: Bool]?

    var availableLabels: [String] {
        Set(torrents.map(\.label).filter { !$0.isEmpty }).sorted()
    }

    var filteredTorrents: [Torrent] {
        let base = torrents
            .filter { filter.matches($0) }
            .filter { selectedLabel == nil || $0.label == selectedLabel }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
        return base.sorted { a, b in
            let before = sortKey.isOrderedBefore(a, b)
            let after = sortKey.isOrderedBefore(b, a)
            if !before && !after { return a.name.localizedCompare(b.name) == .orderedAscending }
            return sortAscending ? before : after
        }
    }

    func attach(to appState: AppState) {
        self.appState = appState
    }

    var isAttached: Bool { appState != nil }

    /// Exposes the active client for detail views (files, trackers, peers) that need direct calls.
    var clientForDetail: RTorrentClient? { appState?.client }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                await self.waitForNextPoll()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        retryCountdown = nil
    }

    /// Clears state when switching to another server profile.
    func reset() {
        torrents = []
        knownCompletion = nil
        consecutiveFailures = 0
        errorMessage = nil
        startPolling()
    }

    /// Reconnect right now instead of waiting for the backoff timer.
    func retryNow() { startPolling() }

    /// 3 s while the app is frontmost, 10 s in the background, exponential backoff (max 60 s) on failures.
    private func waitForNextPoll() async {
        if consecutiveFailures > 0 {
            let delay = min(60, 3 * (1 << min(consecutiveFailures - 1, 5)))
            for remaining in stride(from: delay, to: 0, by: -1) {
                if Task.isCancelled { return }
                retryCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            retryCountdown = nil
        } else {
            let interval: UInt64 = NSApplication.shared.isActive ? 3 : 10
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
        }
    }

    func refresh() async {
        guard let client = appState?.client else { return }
        isLoading = true
        do {
            async let torrentsTask = client.fetchTorrents()
            async let statsTask = client.fetchSessionStats()
            let (fetched, stats) = try await (torrentsTask, statsTask)
            detectCompletions(in: fetched)
            torrents = fetched
            globalDownRate = stats.downRate
            globalUpRate = stats.upRate
            errorMessage = nil
            consecutiveFailures = 0
            retryCountdown = nil
            appState?.isConnected = true
        } catch {
            consecutiveFailures += 1
            errorMessage = error.localizedDescription
            appState?.isConnected = false
        }
        isLoading = false
    }

    private func detectCompletions(in fetched: [Torrent]) {
        let previous = knownCompletion
        knownCompletion = Dictionary(uniqueKeysWithValues: fetched.map { ($0.hash, $0.isComplete) })
        guard let previous else { return }   // first load: nothing to compare against
        for torrent in fetched where torrent.isComplete && previous[torrent.hash] == false {
            Notifier.notify(title: "Descarga completada", body: torrent.name)
            onTorrentCompleted.forEach { $0(torrent) }
        }
    }

    // MARK: - Actions (all accept several torrents)

    func perform(_ action: @escaping (RTorrentClient, String) async throws -> Void, on torrents: [Torrent]) {
        guard let client = appState?.client, !torrents.isEmpty else { return }
        Task {
            var failures: [String] = []
            for torrent in torrents {
                do { try await action(client, torrent.hash) }
                catch { failures.append(error.localizedDescription) }
            }
            if let first = failures.first {
                errorMessage = failures.count > 1 ? "\(first) (+\(failures.count - 1) más)" : first
            }
            await refresh()
        }
    }

    func start(_ torrents: [Torrent]) { perform({ try await $0.start(hash: $1) }, on: torrents) }
    func stop(_ torrents: [Torrent]) { perform({ try await $0.stop(hash: $1) }, on: torrents) }
    func pause(_ torrents: [Torrent]) { perform({ try await $0.pause(hash: $1) }, on: torrents) }
    func resume(_ torrents: [Torrent]) { perform({ try await $0.resume(hash: $1) }, on: torrents) }
    func recheck(_ torrents: [Torrent]) { perform({ try await $0.recheck(hash: $1) }, on: torrents) }
    func remove(_ torrents: [Torrent]) { perform({ try await $0.remove(hash: $1) }, on: torrents) }

    func removeWithData(_ torrents: [Torrent]) {
        let disposal = Preferences.dataDisposal
        perform({ try await $0.removeWithData(hash: $1, disposal: disposal) }, on: torrents)
    }

    func togglePause(_ torrents: [Torrent]) {
        pause(torrents.filter(\.isActive))
        resume(torrents.filter { !$0.isActive })
    }

    func start(_ torrent: Torrent) { start([torrent]) }
    func stop(_ torrent: Torrent) { stop([torrent]) }
    func pause(_ torrent: Torrent) { pause([torrent]) }
    func resume(_ torrent: Torrent) { resume([torrent]) }
    func recheck(_ torrent: Torrent) { recheck([torrent]) }

    func setLabel(_ torrents: [Torrent], label: String) {
        perform({ try await $0.setLabel(hash: $1, label: label) }, on: torrents)
    }

    func setLabel(_ torrent: Torrent, label: String) { setLabel([torrent], label: label) }

    func move(_ torrents: [Torrent], to directory: String) {
        perform({ try await $0.moveData(hash: $1, to: directory) }, on: torrents)
    }

    func addTorrent(uri: String, startImmediately: Bool, label: String, directory: String = "") {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.addFromURI(uri.trimmingCharacters(in: .whitespacesAndNewlines), startImmediately: startImmediately,
                                            label: label.isEmpty ? nil : label, directory: directory)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTorrent(fileData: Data, startImmediately: Bool, label: String, directory: String = "") {
        guard let client = appState?.client else { return }
        Task {
            do {
                try await client.addFromFileData(fileData, startImmediately: startImmediately,
                                                 label: label.isEmpty ? nil : label, directory: directory)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Handles a magnet link, a `.torrent` URL or a local `.torrent` file (drag & drop / open-with).
    func addFromExternal(url: URL) {
        if url.isFileURL {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "torrent", let data = try? Data(contentsOf: url) else {
                errorMessage = "No se pudo leer el archivo \(url.lastPathComponent)."
                return
            }
            addTorrent(fileData: data, startImmediately: true, label: "")
        } else {
            addTorrent(uri: url.absoluteString, startImmediately: true, label: "")
        }
    }
}
