import Foundation

extension RTorrentClient {

    private static let fileFields: [String] = [
        "f.path=",
        "f.size_bytes=",
        "f.completed_chunks=",
        "f.size_chunks=",
        "f.priority=",
    ]

    func fetchFiles(hash: String) async throws -> [TorrentFile] {
        var params: [XMLRPCValue] = [.string(hash), .string("")]
        params.append(contentsOf: Self.fileFields.map { .string($0) })
        let result = try await rpc.call("f.multicall", params)
        return result.arrayValue.enumerated().compactMap { index, row in
            Self.parseFile(index: index, from: row)
        }
    }

    private static func parseFile(index: Int, from row: XMLRPCValue) -> TorrentFile? {
        let values = row.arrayValue
        guard values.count >= fileFields.count else { return nil }
        let priority = FilePriority(rawValue: values[4].intValue) ?? .normal
        return TorrentFile(
            index: index,
            path: values[0].stringValue,
            sizeBytes: values[1].int64Value,
            completedChunks: values[2].intValue,
            sizeChunks: values[3].intValue,
            priority: priority
        )
    }

    /// Sets a file's download priority. `index` is the file's position as returned by `fetchFiles`.
    func setFilePriority(hash: String, index: Int, priority: FilePriority) async throws {
        _ = try await rpc.call("f.priority.set", [.string("\(hash):f\(index)"), .int(priority.rawValue)])
        // Ask rTorrent to recompute which pieces to fetch next given the new priorities.
        _ = try await rpc.call("d.update_priorities", [.string(hash)])
    }
}
