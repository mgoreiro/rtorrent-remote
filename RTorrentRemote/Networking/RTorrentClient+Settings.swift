import Foundation

extension RTorrentClient {

    struct GlobalSpeedLimits {
        var downKBps: Int  // 0 = unlimited
        var upKBps: Int
    }

    func fetchGlobalSpeedLimits() async throws -> GlobalSpeedLimits {
        async let down = rpc.call("throttle.global_down.max_rate")
        async let up = rpc.call("throttle.global_up.max_rate")
        let (d, u) = try await (down, up)
        return GlobalSpeedLimits(downKBps: d.intValue / 1024, upKBps: u.intValue / 1024)
    }

    func setGlobalSpeedLimits(downKBps: Int, upKBps: Int) async throws {
        _ = try await rpc.call("throttle.global_down.max_rate.set", [.string(""), .int(downKBps * 1024)])
        _ = try await rpc.call("throttle.global_up.max_rate.set", [.string(""), .int(upKBps * 1024)])
    }

    /// Current download/upload rates across all torrents, and free disk space on the
    /// default download directory, useful for a status bar.
    func fetchSessionStats() async throws -> (downRate: Int64, upRate: Int64) {
        async let down = rpc.call("throttle.global_down.rate")
        async let up = rpc.call("throttle.global_up.rate")
        let (d, u) = try await (down, up)
        return (d.int64Value, u.int64Value)
    }

    /// All distinct labels (rTorrent's `d.custom1`) currently in use, derived client-side
    /// since rTorrent has no dedicated "list of labels" RPC method.
    func fetchDistinctLabels() async throws -> [String] {
        let torrents = try await fetchTorrents()
        let labels = Set(torrents.map(\.label).filter { !$0.isEmpty })
        return labels.sorted()
    }
}
