import Foundation
import CryptoKit

/// Computes a torrent's BitTorrent info-hash so the app can reliably tag a
/// freshly-added torrent with a label right after `load.start`/`load.raw_start`,
/// instead of guessing which entry in the torrent list is the new one.
enum TorrentHash {

    /// Extracts the info-hash (lowercase hex, 40 chars) from a magnet URI's `xt=urn:btih:` parameter.
    /// Supports both the 40-char hex form and the 32-char Base32 form.
    static func infoHash(fromMagnetURI uri: String) -> String? {
        guard let components = URLComponents(string: uri), let items = components.queryItems else { return nil }
        for item in items where item.name == "xt" {
            guard let value = item.value, value.hasPrefix("urn:btih:") else { continue }
            let raw = String(value.dropFirst("urn:btih:".count))
            if raw.count == 40, raw.allSatisfy({ $0.isHexDigit }) {
                return raw.lowercased()
            }
            if raw.count == 32, let decoded = base32Decode(raw) {
                return decoded.map { String(format: "%02x", $0) }.joined()
            }
        }
        return nil
    }

    /// Computes the SHA-1 info-hash of a `.torrent` file's `info` dictionary, exactly as
    /// rTorrent/BitTorrent clients identify a torrent.
    static func infoHash(fromTorrentFileData data: Data) -> String? {
        guard let infoBytes = extractBencodedInfoDictionary(data) else { return nil }
        let digest = Insecure.SHA1.hash(data: infoBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Minimal Bencode walker (only extracts the raw byte range of the "info" value)

    private static func extractBencodedInfoDictionary(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var pos = 0
        guard pos < bytes.count, bytes[pos] == UInt8(ascii: "d") else { return nil }
        pos += 1
        while pos < bytes.count, bytes[pos] != UInt8(ascii: "e") {
            guard let key = parseStringBytes(bytes, &pos) else { return nil }
            if key == Array("info".utf8) {
                let start = pos
                guard skipValue(bytes, &pos) else { return nil }
                return Data(bytes[start..<pos])
            } else {
                guard skipValue(bytes, &pos) else { return nil }
            }
        }
        return nil
    }

    /// Parses a bencoded byte-string (`<length>:<bytes>`) and returns its raw content bytes.
    private static func parseStringBytes(_ bytes: [UInt8], _ pos: inout Int) -> [UInt8]? {
        var lengthDigits: [UInt8] = []
        while pos < bytes.count, bytes[pos] != UInt8(ascii: ":") {
            guard bytes[pos] >= UInt8(ascii: "0"), bytes[pos] <= UInt8(ascii: "9") else { return nil }
            lengthDigits.append(bytes[pos])
            pos += 1
        }
        guard pos < bytes.count else { return nil } // missing ':'
        pos += 1 // skip ':'
        guard let length = Int(String(decoding: lengthDigits, as: UTF8.self)) else { return nil }
        guard pos + length <= bytes.count else { return nil }
        let content = Array(bytes[pos..<(pos + length)])
        pos += length
        return content
    }

    /// Advances `pos` past one full bencoded value (int, string, list, or dict) without decoding it.
    private static func skipValue(_ bytes: [UInt8], _ pos: inout Int) -> Bool {
        guard pos < bytes.count else { return false }
        switch bytes[pos] {
        case UInt8(ascii: "i"):
            pos += 1
            while pos < bytes.count, bytes[pos] != UInt8(ascii: "e") { pos += 1 }
            guard pos < bytes.count else { return false }
            pos += 1
            return true
        case UInt8(ascii: "l"):
            pos += 1
            while pos < bytes.count, bytes[pos] != UInt8(ascii: "e") {
                guard skipValue(bytes, &pos) else { return false }
            }
            guard pos < bytes.count else { return false }
            pos += 1
            return true
        case UInt8(ascii: "d"):
            pos += 1
            while pos < bytes.count, bytes[pos] != UInt8(ascii: "e") {
                guard parseStringBytes(bytes, &pos) != nil else { return false }
                guard skipValue(bytes, &pos) else { return false }
            }
            guard pos < bytes.count else { return false }
            pos += 1
            return true
        default:
            return parseStringBytes(bytes, &pos) != nil
        }
    }

    // MARK: - Base32 (RFC 4648, no padding) → bytes, needed for magnet links using the Base32 BTIH form.

    private static func base32Decode(_ string: String) -> [UInt8]? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var lookup: [Character: UInt8] = [:]
        for (i, c) in alphabet.enumerated() { lookup[c] = UInt8(i) }

        var bits = 0
        var value: UInt32 = 0
        var output: [UInt8] = []
        for char in string.uppercased() {
            guard let v = lookup[char] else { return nil }
            value = (value << 5) | UInt32(v)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> UInt32(bits)) & 0xFF))
            }
        }
        return output
    }
}
