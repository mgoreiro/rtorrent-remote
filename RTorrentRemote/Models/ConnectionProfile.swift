import Foundation

/// Everything needed to reach the rTorrent XML-RPC endpoint over HTTP(S).
/// This app assumes rTorrent's SCGI socket is fronted by a reverse proxy
/// (nginx `scgi_pass` or `socat`) that exposes plain XML-RPC over HTTP,
/// typically at a path such as `/RPC2`.
struct ConnectionProfile: Codable, Equatable {
    var host: String = ""
    var port: Int = 443
    var path: String = "/RPC2"
    var useHTTPS: Bool = true
    var username: String = ""
    /// Trust self-signed / untrusted certificates (useful for home servers).
    var allowInsecureTLS: Bool = false

    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0 && port < 65536
    }

    var endpointURL: URL? {
        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = host
        components.port = port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url
    }

    static let empty = ConnectionProfile()
}
