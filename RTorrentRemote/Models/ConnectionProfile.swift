import Foundation

/// Everything needed to reach the rTorrent XML-RPC endpoint over HTTP(S).
/// This app assumes rTorrent's SCGI socket is fronted by a reverse proxy
/// (nginx `scgi_pass` or `socat`) that exposes plain XML-RPC over HTTP,
/// typically at a path such as `/RPC2`.
struct ConnectionProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = "Servidor"
    var host: String = ""
    var port: Int = 443
    var path: String = "/RPC2"
    var useHTTPS: Bool = true
    var username: String = ""
    /// Trust self-signed / untrusted certificates (useful for home servers).
    var allowInsecureTLS: Bool = false
    /// SHA-256 (hex) of the only server certificate accepted. When set it overrides system trust,
    /// which is safer than blindly accepting any self-signed certificate.
    var pinnedCertSHA256: String = ""

    init() {}

    // Custom decoding keeps profiles saved by older versions (no id/name/pin) loading correctly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Servidor"
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 443
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/RPC2"
        useHTTPS = try c.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? true
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        allowInsecureTLS = try c.decodeIfPresent(Bool.self, forKey: .allowInsecureTLS) ?? false
        pinnedCertSHA256 = try c.decodeIfPresent(String.self, forKey: .pinnedCertSHA256) ?? ""
    }

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
