import Foundation
import CryptoKit
import Security

/// Speaks XML-RPC over HTTP(S) to an endpoint such as `http://host/RPC2`,
/// which is typically nginx or socat sitting in front of rTorrent's SCGI socket.
final class XMLRPCClient: NSObject {

    var endpoint: URL
    var username: String?
    var password: String?
    var timeout: TimeInterval = 20
    private let allowInsecureTLS: Bool
    private let pinnedCertSHA256: String
    private let fingerprintLock = NSLock()
    private var _lastServerFingerprint: String?

    /// SHA-256 (hex) of the leaf certificate seen in the most recent TLS handshake; used to offer "pin this certificate".
    var lastServerFingerprint: String? {
        fingerprintLock.lock(); defer { fingerprintLock.unlock() }
        return _lastServerFingerprint
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["Content-Type": "text/xml"]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(endpoint: URL, username: String? = nil, password: String? = nil, allowInsecureTLS: Bool = false, pinnedCertSHA256: String = "") {
        self.endpoint = endpoint
        self.username = username
        self.password = password
        self.allowInsecureTLS = allowInsecureTLS
        self.pinnedCertSHA256 = pinnedCertSHA256.replacingOccurrences(of: ":", with: "").lowercased()
        super.init()
    }

    /// Performs a single XML-RPC call and returns its first `<param>` value.
    @discardableResult
    func call(_ method: String, _ params: [XMLRPCValue] = []) async throws -> XMLRPCValue {
        let results = try await callMultiple(method, params)
        return results.first ?? .nilValue
    }

    /// Performs a single XML-RPC call and returns all `<param>` values.
    func callMultiple(_ method: String, _ params: [XMLRPCValue] = []) async throws -> [XMLRPCValue] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(XMLRPCClient.buildRequestXML(method: method, params: params).utf8)

        if let username, let password, !username.isEmpty {
            let raw = "\(username):\(password)"
            let encoded = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw XMLRPCError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw XMLRPCError.httpError(http.statusCode)
        }
        guard !data.isEmpty else { throw XMLRPCError.emptyResponse }

        return try XMLRPCParser.parse(data: data)
    }

    /// Builds a `<methodCall>` XML document for the given method and parameters.
    static func buildRequestXML(method: String, params: [XMLRPCValue]) -> String {
        let paramsXML = params.map { "<param>\($0.toXMLString())</param>" }.joined()
        return """
        <?xml version="1.0"?>
        <methodCall>
        <methodName>\(method)</methodName>
        <params>\(paramsXML)</params>
        </methodCall>
        """
    }
}

extension XMLRPCClient: URLSessionDelegate {
    /// TLS trust decisions. Priority: (1) a pinned certificate must match exactly; (2) otherwise
    /// self-signed certificates are accepted only if the user opted in; (3) otherwise default system validation.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let fingerprint = Self.leafFingerprint(of: serverTrust)
        fingerprintLock.lock(); _lastServerFingerprint = fingerprint; fingerprintLock.unlock()

        if !pinnedCertSHA256.isEmpty {
            if fingerprint == pinnedCertSHA256 {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else if allowInsecureTLS {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    static func leafFingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return nil }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
