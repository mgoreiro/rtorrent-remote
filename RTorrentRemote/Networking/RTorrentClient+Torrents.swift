import Foundation

extension RTorrentClient {

    /// Field list used for `d.multicall2`. Keep `parseTorrent(from:)` in sync
    /// with the order of this array.
    private static let torrentFields: [String] = [
        "d.hash=",
        "d.name=",
        "d.size_bytes=",
        "d.completed_bytes=",
        "d.down.rate=",
        "d.up.rate=",
        "d.ratio=",
        "d.is_active=",
        "d.is_open=",
        "d.is_hash_checking=",
        "d.state=",
        "d.custom1=",
        "d.message=",
        "d.peers_connected=",
        "d.peers_complete=",
        "d.directory=",
    ]

    /// Fetches every torrent currently known to rTorrent (the "main" view, i.e. all torrents).
    func fetchTorrents() async throws -> [Torrent] {
        var params: [XMLRPCValue] = [.string(""), .string("main")]
        params.append(contentsOf: Self.torrentFields.map { .string($0) })
        let result = try await rpc.call("d.multicall2", params)
        return result.arrayValue.compactMap(Self.parseTorrent(from:))
    }

    private static func parseTorrent(from row: XMLRPCValue) -> Torrent? {
        let values = row.arrayValue
        guard values.count >= torrentFields.count else { return nil }
        return Torrent(
            hash: values[0].stringValue,
            name: values[1].stringValue,
            sizeBytes: values[2].int64Value,
            completedBytes: values[3].int64Value,
            downRate: values[4].int64Value,
            upRate: values[5].int64Value,
            ratio: Double(values[6].intValue) / 1000.0,
            isActive: values[7].intValue == 1,
            isOpen: values[8].intValue == 1,
            isHashing: values[9].intValue != 0,
            state: values[10].intValue,
            label: values[11].stringValue,
            message: values[12].stringValue,
            peersConnected: values[13].intValue,
            seedersConnected: values[14].intValue,
            baseDirectory: values[15].stringValue
        )
    }

    // MARK: - Lifecycle actions

    func start(hash: String) async throws {
        _ = try await rpc.call("d.start", [.string(hash)])
    }

    func stop(hash: String) async throws {
        _ = try await rpc.call("d.stop", [.string(hash)])
    }

    /// Pauses without closing the torrent (keeps trackers/peers state), mirrors rTorrent's `d.pause`.
    func pause(hash: String) async throws {
        _ = try await rpc.call("d.pause", [.string(hash)])
    }

    func resume(hash: String) async throws {
        _ = try await rpc.call("d.resume", [.string(hash)])
    }

    /// Fully stops and closes a torrent (releases file handles); use before `remove`.
    func close(hash: String) async throws {
        _ = try await rpc.call("d.close", [.string(hash)])
    }

    /// Removes a torrent from rTorrent. Does NOT delete data on disk.
    func remove(hash: String) async throws {
        try await stop(hash: hash)
        try await close(hash: hash)
        _ = try await rpc.call("d.erase", [.string(hash)])
    }

    func recheck(hash: String) async throws {
        _ = try await rpc.call("d.check_hash", [.string(hash)])
    }

    func setLabel(hash: String, label: String) async throws {
        _ = try await rpc.call("d.custom1.set", [.string(hash), .string(label)])
    }

    // MARK: - Adding torrents

    /// Adds a torrent from a magnet link or a direct .torrent URL, then tags it with `label`
    /// (when provided) using the info-hash computed client-side, so tagging is exact rather
    /// than a guess.
    func addFromURI(_ uri: String, startImmediately: Bool, label: String? = nil, directory: String? = nil) async throws {
        let method = startImmediately ? "load.start" : "load.normal"
        _ = try await rpc.call(method, [.string(""), .string(uri)] + Self.loadCommands(directory: directory))
        guard let label, !label.isEmpty else { return }
        if let hash = TorrentHash.infoHash(fromMagnetURI: uri) {
            // rTorrent needs a brief moment to register the newly loaded torrent.
            try await Task.sleep(nanoseconds: 500_000_000)
            try? await setLabel(hash: hash, label: label)
        }
    }

    /// Adds a torrent from the raw bytes of a `.torrent` file, then tags it with `label`
    /// (when provided) using the SHA-1 info-hash computed from the file itself.
    func addFromFileData(_ data: Data, startImmediately: Bool, label: String? = nil, directory: String? = nil) async throws {
        let method = startImmediately ? "load.raw_start" : "load.raw"
        _ = try await rpc.call(method, [.string(""), .base64(data)] + Self.loadCommands(directory: directory))
        guard let label, !label.isEmpty else { return }
        if let hash = TorrentHash.infoHash(fromTorrentFileData: data) {
            try await Task.sleep(nanoseconds: 500_000_000)
            try? await setLabel(hash: hash, label: label)
        }
    }

    /// Extra `load.*` argument that makes the new torrent download into `directory`.
    private static func loadCommands(directory: String?) -> [XMLRPCValue] {
        // Records when the torrent was added (same `addtime` key ruTorrent uses).
        var commands: [XMLRPCValue] = [.string("d.custom.set=addtime,\(Int(Date().timeIntervalSince1970))")]
        if let directory = directory?.trimmingCharacters(in: .whitespaces), !directory.isEmpty {
            let escaped = directory.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            commands.append(.string("d.directory.set=\"\(escaped)\""))
        }
        return commands
    }
}
