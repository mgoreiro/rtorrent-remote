import Foundation

/// Errors that can occur while talking to the rTorrent XML-RPC endpoint.
enum XMLRPCError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case emptyResponse
    case parseError(String)
    case fault(code: Int, message: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL del servidor no válida."
        case .httpError(let code):
            return "El servidor respondió con el código HTTP \(code)."
        case .emptyResponse:
            return "El servidor devolvió una respuesta vacía."
        case .parseError(let detail):
            return "No se pudo interpretar la respuesta XML-RPC: \(detail)"
        case .fault(let code, let message):
            return "rTorrent devolvió un error (\(code)): \(message)"
        case .transport(let error):
            return "Error de red: \(error.localizedDescription)"
        }
    }
}

/// Parses an XML-RPC `methodResponse` document into an array of `XMLRPCValue`
/// (top level XML-RPC calls can return more than one `<param>`, though rTorrent
/// almost always returns exactly one).
final class XMLRPCParser: NSObject, XMLParserDelegate {

    private enum Node {
        case value(XMLRPCValue)
        case array([XMLRPCValue])
        case dictionary([(String, XMLRPCValue)])
        case member(String, XMLRPCValue?)
        case container // struct/array wrapper waiting for children
    }

    private var stack: [Node] = []
    private var textBuffer: String = ""
    private var currentTag: String = ""
    private var results: [XMLRPCValue] = []
    private var faultValue: XMLRPCValue?
    private var isFault = false
    private var currentMemberName: String?

    static func parse(data: Data) throws -> [XMLRPCValue] {
        let parser = XMLRPCParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            let message = xmlParser.parserError?.localizedDescription ?? "desconocido"
            throw XMLRPCError.parseError(message)
        }
        if parser.isFault {
            let dict: [String: XMLRPCValue]
            if case .dictionary(let d) = parser.faultValue {
                dict = d
            } else {
                dict = [:]
            }
            let code = dict["faultCode"]?.intValue ?? -1
            let message = dict["faultString"]?.stringValue ?? "Fallo desconocido"
            throw XMLRPCError.fault(code: code, message: message)
        }
        return parser.results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentTag = elementName
        textBuffer = ""
        switch elementName {
        case "array":
            stack.append(.array([]))
        case "struct":
            stack.append(.dictionary([]))
        case "member":
            currentMemberName = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "i4", "int":
            push(.int(Int(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
        case "i8":
            push(.i8(Int64(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
        case "double":
            push(.double(Double(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
        case "boolean":
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            push(.bool(trimmed == "1" || trimmed.lowercased() == "true"))
        case "string":
            push(.string(textBuffer))
        case "base64":
            let cleaned = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            push(.base64(Data(base64Encoded: cleaned) ?? Data()))
        case "nil":
            push(.nilValue)
        case "name":
            currentMemberName = textBuffer
        case "value":
            // If no typed child was emitted (e.g. bare <value>text</value>), treat as string.
            if case .some(.value) = stack.last {
                // already pushed by a typed child above; nothing to do.
            } else if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                push(.string(textBuffer))
            }
        case "member":
            if case .value(let v)? = popIfValue() {
                if case .dictionary(var members)? = stack.popLast() {
                    members.append((currentMemberName ?? "", v))
                    stack.append(.dictionary(members))
                }
            }
            currentMemberName = nil
        case "data":
            break
        case "array":
            if case .array(let items)? = stack.popLast() {
                push(.array(items))
            }
        case "struct":
            if case .dictionary(let members)? = stack.popLast() {
                var dict: [String: XMLRPCValue] = [:]
                for (k, v) in members { dict[k] = v }
                push(.dictionary(dict))
            }
        case "fault":
            if case .value(let v)? = popIfValue() {
                faultValue = v
                isFault = true
            }
        case "param":
            if case .value(let v)? = popIfValue() {
                results.append(v)
            }
        default:
            break
        }
        textBuffer = ""
    }

    /// Pops the top of the stack if it is a `.value`, otherwise leaves the stack untouched
    /// and wraps it appropriately (used right after closing `</value>`, `</fault>`, `</param>`).
    private func popIfValue() -> Node? {
        guard let top = stack.last else { return nil }
        if case .value = top {
            return stack.popLast()
        }
        return nil
    }

    /// Pushes a freshly-produced scalar/array/struct value onto the stack, attaching it to an
    /// enclosing array if present.
    private func push(_ value: XMLRPCValue) {
        if case .array(var items)? = stack.last {
            stack.removeLast()
            items.append(value)
            stack.append(.array(items))
        } else {
            stack.append(.value(value))
        }
    }
}
