import Foundation

/// Error raised when the torrent was removed but its data could not be deleted/moved.
struct DataOperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// How `removeWithData` disposes of the downloaded files on the server.
enum DataDisposal: Equatable {
    case delete
    case moveToTrash(String)
}

extension RTorrentClient {

    /// A data path is only safe to delete/move when absolute, at least two levels deep and free
    /// of `..` segments. This protects against `rm -rf /` or `rm -rf /home` style accidents.
    static func isSafeDataPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/").filter { !$0.isEmpty }
        return path.hasPrefix("/") && parts.count >= 2 && !parts.contains("..") && !path.contains("\0")
    }

    /// Removes the torrent from rTorrent and then deletes (or moves to a trash folder) its data on
    /// the server's disk. The data path is read *before* erasing because it is unavailable afterwards.
    /// Commands run via `execute.throw`, so a failing `rm`/`mv` surfaces as an error.
    func removeWithData(hash: String, disposal: DataDisposal = .delete) async throws {
        let path = try await rpc.call("d.base_path", [.string(hash)]).stringValue
        guard Self.isSafeDataPath(path) else {
            throw DataOperationError(message: "Ruta de datos no segura, no se ha eliminado nada: \(path)")
        }
        if case .moveToTrash(let trash) = disposal, !Self.isSafeDataPath(trash) {
            throw DataOperationError(message: "Ruta de papelera no válida: \(trash)")
        }
        try await remove(hash: hash)
        do {
            switch disposal {
            case .delete:
                try await shell("rm -rf -- \"$1\"", path)
            case .moveToTrash(let trash):
                try await shell("mkdir -p -- \"$1\" && mv -- \"$2\" \"$1\"/", trash, path)
            }
        } catch {
            throw DataOperationError(message: "El torrent se eliminó, pero no se pudieron borrar los archivos (\(path)): \(error.localizedDescription)")
        }
    }

    /// Moves a torrent's data to `destination` on the server and points rTorrent at it.
    func moveData(hash: String, to destination: String) async throws {
        guard Self.isSafeDataPath(destination) else {
            throw DataOperationError(message: "Ruta de destino no válida: \(destination)")
        }
        let path = try await rpc.call("d.base_path", [.string(hash)]).stringValue
        let name = try await rpc.call("d.name", [.string(hash)]).stringValue
        let isMulti = try await rpc.call("d.is_multi_file", [.string(hash)]).intValue == 1
        guard Self.isSafeDataPath(path) else {
            throw DataOperationError(message: "Ruta de datos no segura: \(path)")
        }
        let dest = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
        let wasActive = try await rpc.call("d.is_active", [.string(hash)]).intValue == 1
        try await stop(hash: hash)
        try await close(hash: hash)
        try await shell("mkdir -p -- \"$1\" && mv -- \"$2\" \"$1\"/", dest, path)
        // Multi-file torrents keep their own folder (named after the torrent) inside the destination.
        let newDirectory = isMulti ? "\(dest)/\(name)" : dest
        _ = try await rpc.call("d.directory.set", [.string(hash), .string(newDirectory)])
        if wasActive { try await start(hash: hash) }
    }

    /// Runs `script` with `args` as `$1…` through `sh -c` on the server; throws on a non-zero exit.
    private func shell(_ script: String, _ args: String...) async throws {
        var params: [XMLRPCValue] = [.string(""), .string("sh"), .string("-c"), .string(script), .string("sh")]
        params.append(contentsOf: args.map { .string($0) })
        _ = try await rpc.call("execute.throw", params)
    }

    // MARK: - Sharing statistics

    /// Reads each value separately so a method missing on an older rTorrent only blanks that field
    /// instead of failing the whole panel.
    func fetchStats(hash: String) async -> TorrentStats {
        func int(_ method: String, _ extra: [XMLRPCValue] = []) async -> Int64? {
            try? await rpc.call(method, [.string(hash)] + extra).int64Value
        }
        func date(_ seconds: Int64?) -> Date? {
            guard let seconds, seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        var stats = TorrentStats()
        // `addtime` is written by this app (and ruTorrent) when a torrent is loaded.
        let addTime = (try? await rpc.call("d.custom", [.string(hash), .string("addtime")]).stringValue).flatMap { Int64($0) }
        if let added = date(addTime) {
            stats.addedDate = added
        } else if let started = date(await int("d.timestamp.started")) {
            stats.addedDate = started
            stats.addedIsApproximate = true
        }
        stats.finishedDate = date(await int("d.timestamp.finished"))
        stats.creationDate = date(await int("d.creation_date"))
        stats.uploadedBytes = await int("d.up.total") ?? 0
        stats.downloadedBytes = await int("d.down.total") ?? 0
        return stats
    }

    // MARK: - Trackers & peers

    func fetchTrackers(hash: String) async throws -> [TorrentTracker] {
        let fields = ["t.url=", "t.is_enabled=", "t.scrape_complete=", "t.scrape_incomplete=", "t.failed_counter="]
        let params: [XMLRPCValue] = [.string(hash), .string("")] + fields.map { .string($0) }
        let result = try await rpc.call("t.multicall", params)
        return result.arrayValue.enumerated().compactMap { index, row in
            let v = row.arrayValue
            guard v.count >= fields.count else { return nil }
            return TorrentTracker(index: index, url: v[0].stringValue, isEnabled: v[1].intValue == 1,
                                  seeders: v[2].intValue, leechers: v[3].intValue, failures: v[4].intValue)
        }
    }

    func fetchPeers(hash: String) async throws -> [TorrentPeer] {
        let fields = ["p.address=", "p.port=", "p.client_version=", "p.down_rate=", "p.up_rate=", "p.completed_percent="]
        let params: [XMLRPCValue] = [.string(hash), .string("")] + fields.map { .string($0) }
        let result = try await rpc.call("p.multicall", params)
        return result.arrayValue.enumerated().compactMap { index, row in
            let v = row.arrayValue
            guard v.count >= fields.count else { return nil }
            return TorrentPeer(index: index, address: v[0].stringValue, port: v[1].intValue, client: v[2].stringValue,
                               downRate: v[3].int64Value, upRate: v[4].int64Value, percent: v[5].intValue)
        }
    }
}
