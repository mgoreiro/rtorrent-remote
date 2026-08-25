import Foundation

/// Represents any value that can appear in an XML-RPC request or response.
indirect enum XMLRPCValue {
    case int(Int)
    case i8(Int64)
    case string(String)
    case double(Double)
    case bool(Bool)
    case base64(Data)
    case array([XMLRPCValue])
    case dictionary([String: XMLRPCValue])
    case nilValue

    // MARK: - Convenience accessors

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .i8(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "1" : "0"
        default: return ""
        }
    }

    var intValue: Int {
        switch self {
        case .int(let i): return i
        case .i8(let i): return Int(i)
        case .string(let s): return Int(s) ?? 0
        case .double(let d): return Int(d)
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    var int64Value: Int64 {
        switch self {
        case .int(let i): return Int64(i)
        case .i8(let i): return i
        case .string(let s): return Int64(s) ?? 0
        case .double(let d): return Int64(d)
        default: return 0
        }
    }

    var doubleValue: Double {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .i8(let i): return Double(i)
        case .string(let s): return Double(s) ?? 0
        default: return 0
        }
    }

    var arrayValue: [XMLRPCValue] {
        if case .array(let a) = self { return a }
        return []
    }

    // MARK: - XML encoding

    func toXMLString() -> String {
        switch self {
        case .int(let i):
            return "<value><i4>\(i)</i4></value>"
        case .i8(let i):
            return "<value><i8>\(i)</i8></value>"
        case .string(let s):
            return "<value><string>\(XMLRPCValue.escape(s))</string></value>"
        case .double(let d):
            return "<value><double>\(d)</double></value>"
        case .bool(let b):
            return "<value><boolean>\(b ? 1 : 0)</boolean></value>"
        case .base64(let data):
            return "<value><base64>\(data.base64EncodedString())</base64></value>"
        case .array(let arr):
            let items = arr.map { $0.toXMLString() }.joined()
            return "<value><array><data>\(items)</data></array></value>"
        case .dictionary(let dict):
            let members = dict.map { key, value in
                "<member><name>\(XMLRPCValue.escape(key))</name>\(value.toXMLString())</member>"
            }.joined()
            return "<value><struct>\(members)</struct></value>"
        case .nilValue:
            return "<value><nil/></value>"
        }
    }

    private static func escape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }
}
