import Foundation

/// rTorrent only exposes RSS control over XML-RPC when it was compiled with
/// libcurl + the RSS module (methods like `rss.import`, `rss.list`). Not every
/// build/distro package includes this, so all RSS features in the app degrade
/// gracefully with an explanatory message when the methods are unavailable.
struct RSSFeed: Identifiable, Hashable {
    let url: String
    var lastUpdate: String
    var itemCount: Int

    var id: String { url }
}

struct RSSFilter: Identifiable, Hashable {
    let name: String
    var pattern: String
    var isEnabled: Bool

    var id: String { name }
}
