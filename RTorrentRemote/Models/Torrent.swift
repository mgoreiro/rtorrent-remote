import Foundation

enum TorrentStatus: String, CaseIterable, Identifiable {
    case downloading
    case seeding
    case paused
    case stopped
    case completed
    case hashing
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .downloading: return "Descargando"
        case .seeding: return "Compartiendo"
        case .paused: return "En pausa"
        case .stopped: return "Detenido"
        case .completed: return "Completado"
        case .hashing: return "Verificando"
        case .error: return "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .downloading: return "arrow.down.circle.fill"
        case .seeding: return "arrow.up.circle.fill"
        case .paused: return "pause.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .hashing: return "arrow.triangle.2.circlepath.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

struct Torrent: Identifiable, Hashable {
    let hash: String
    var name: String
    var sizeBytes: Int64
    var completedBytes: Int64
    var downRate: Int64      // bytes/sec
    var upRate: Int64        // bytes/sec
    var ratio: Double
    var isActive: Bool
    var isOpen: Bool
    var isHashing: Bool
    var state: Int           // 0 = stopped, 1 = started (rTorrent's d.state)
    var label: String
    var message: String
    var peersConnected: Int
    var seedersConnected: Int
    var baseDirectory: String

    var id: String { hash }

    var progress: Double {
        guard sizeBytes > 0 else { return 0 }
        return Double(completedBytes) / Double(sizeBytes)
    }

    var isComplete: Bool { completedBytes >= sizeBytes && sizeBytes > 0 }

    var status: TorrentStatus {
        if !message.isEmpty { return .error }
        if isHashing { return .hashing }
        if state == 0 { return .stopped }
        if !isActive { return .paused }
        if isComplete { return upRate > 0 ? .seeding : .completed }
        return .downloading
    }
}

struct TorrentFile: Identifiable, Hashable {
    let index: Int
    var path: String
    var sizeBytes: Int64
    var completedChunks: Int
    var sizeChunks: Int
    var priority: FilePriority

    var id: Int { index }

    var progress: Double {
        guard sizeChunks > 0 else { return 0 }
        return Double(completedChunks) / Double(sizeChunks)
    }
}

enum FilePriority: Int, CaseIterable, Identifiable {
    case off = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "No descargar"
        case .normal: return "Normal"
        case .high: return "Alta"
        }
    }
}

struct TorrentTracker: Identifiable, Hashable {
    let index: Int
    var url: String
    var isEnabled: Bool
    var seeders: Int
    var leechers: Int
    var failures: Int
    var id: Int { index }
}

struct TorrentPeer: Identifiable, Hashable {
    let index: Int
    var address: String
    var port: Int
    var client: String
    var downRate: Int64
    var upRate: Int64
    var percent: Int
    var id: Int { index }
}

enum TorrentSortKey: String, CaseIterable, Identifiable {
    case name, size, progress, ratio, downRate, upRate
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Nombre"
        case .size: return "Tamaño"
        case .progress: return "Progreso"
        case .ratio: return "Ratio"
        case .downRate: return "Velocidad de bajada"
        case .upRate: return "Velocidad de subida"
        }
    }

    /// True when `a` should come before `b` in ascending order.
    func isOrderedBefore(_ a: Torrent, _ b: Torrent) -> Bool {
        switch self {
        case .name: return a.name.localizedCompare(b.name) == .orderedAscending
        case .size: return a.sizeBytes < b.sizeBytes
        case .progress: return a.progress < b.progress
        case .ratio: return a.ratio < b.ratio
        case .downRate: return a.downRate < b.downRate
        case .upRate: return a.upRate < b.upRate
        }
    }
}
