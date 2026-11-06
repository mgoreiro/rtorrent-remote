import Foundation

/// High level API used by the app to talk to a remote rTorrent instance via
/// XML-RPC over HTTP. All calls are `async` and throw `XMLRPCError` on failure.
final class RTorrentClient {
    let rpc: XMLRPCClient

    init(profile: ConnectionProfile, password: String?) {
        guard let url = profile.endpointURL else {
            // Fallback to a harmless placeholder; callers validate `profile.isValid`
            // before constructing the client, this just avoids a force-unwrap.
            self.rpc = XMLRPCClient(endpoint: URL(string: "http://localhost")!)
            return
        }
        self.rpc = XMLRPCClient(endpoint: url, username: profile.username, password: password, allowInsecureTLS: profile.allowInsecureTLS, pinnedCertSHA256: profile.pinnedCertSHA256)
    }

    /// Simple connectivity + version check, used by "Probar conexión" in Settings.
    func testConnection() async throws -> String {
        let result = try await rpc.call("system.client_version")
        return result.stringValue
    }
}
