import Foundation

/// Thrown when the server doesn't expose the `rss.*` XML-RPC methods.
/// Standard rTorrent builds (including the one in most package managers) do NOT
/// include RSS support out of the box — it requires compiling with libcurl's RSS
/// module enabled, or scripting `rtorrent.rc` with an external watcher. This app
/// still offers the UI, but calls will surface this error so the user understands
/// why nothing happens.
struct RSSUnsupportedError: LocalizedError {
    var errorDescription: String? {
        "Este servidor de rTorrent no expone métodos rss.* por XML-RPC. El soporte de RSS depende de cómo se compiló/configuró rTorrent en el servidor; consulta su rtorrent.rc."
    }
}

extension RTorrentClient {

    func fetchRSSFeeds() async throws -> [RSSFeed] {
        do {
            let result = try await rpc.call("rss.list")
            return result.arrayValue.map { row in
                let values = row.arrayValue
                return RSSFeed(
                    url: values.first?.stringValue ?? "",
                    lastUpdate: values.count > 1 ? values[1].stringValue : "",
                    itemCount: values.count > 2 ? values[2].intValue : 0
                )
            }
        } catch XMLRPCError.fault {
            throw RSSUnsupportedError()
        }
    }

    func addRSSFeed(url: String) async throws {
        do {
            _ = try await rpc.call("rss.import", [.string(url)])
        } catch XMLRPCError.fault {
            throw RSSUnsupportedError()
        }
    }

    func removeRSSFeed(url: String) async throws {
        do {
            _ = try await rpc.call("rss.remove", [.string(url)])
        } catch XMLRPCError.fault {
            throw RSSUnsupportedError()
        }
    }
}
