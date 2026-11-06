import Foundation

// MARK: - Command parsing (pure, unit-testable)

enum TelegramCommand: Equatable {
    case help
    case list(filter: String?)
    case status
    case pause(String)
    case resume(String)
    case add(String)
    case remove(String)
    case removeData(String)
    case speed(down: Int?, up: Int?)
    case confirm
    case cancel
    case unknown(String)

    static func parse(_ text: String) -> TelegramCommand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("magnet:") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .add(trimmed)
        }
        guard trimmed.hasPrefix("/") else { return .unknown(trimmed) }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        // "/list@MyBot" → "list"
        let name = parts[0].dropFirst().split(separator: "@").first.map(String.init)?.lowercased() ?? ""
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch name {
        case "start", "help", "ayuda": return .help
        case "list", "lista", "ls": return .list(filter: arg.isEmpty ? nil : arg.lowercased())
        case "status", "estado": return .status
        case "pause", "pausar": return arg.isEmpty ? .unknown(trimmed) : .pause(arg)
        case "resume", "reanudar": return arg.isEmpty ? .unknown(trimmed) : .resume(arg)
        case "add", "anadir", "añadir": return arg.isEmpty ? .unknown(trimmed) : .add(arg)
        case "remove", "eliminar": return arg.isEmpty ? .unknown(trimmed) : .remove(arg)
        case "removedata", "eliminararchivos": return arg.isEmpty ? .unknown(trimmed) : .removeData(arg)
        case "speed", "velocidad":
            let nums = arg.split(separator: " ").compactMap { Int($0) }
            return .speed(down: nums.first, up: nums.count > 1 ? nums[1] : nil)
        case "confirm", "confirmar": return .confirm
        case "cancel", "cancelar": return .cancel
        default: return .unknown(trimmed)
        }
    }
}

/// Parses the comma/space separated list of authorised chat IDs typed in Settings.
func parseTelegramChatIDs(_ text: String) -> Set<Int64> {
    Set(text.split(whereSeparator: { ", ;\n".contains($0) }).compactMap { Int64($0) })
}

// MARK: - Telegram Bot API

private struct TGResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
}
private struct TGUpdate: Decodable {
    let update_id: Int
    let message: TGMessage?
}
private struct TGMessage: Decodable {
    let chat: TGChat
    let text: String?
}
private struct TGChat: Decodable { let id: Int64 }

private struct TelegramAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct TelegramAPI {
    let token: String
    let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        return URLSession(configuration: config)
    }()

    func call<T: Decodable>(_ method: String, _ body: [String: Any]) async throws -> T {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw TelegramAPIError(message: "Token no válido")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(TGResponse<T>.self, from: data)
        guard decoded.ok, let result = decoded.result else {
            throw TelegramAPIError(message: decoded.description ?? "Error de Telegram")
        }
        return result
    }

    fileprivate func updates(offset: Int, timeout: Int) async throws -> [TGUpdate] {
        try await call("getUpdates", ["offset": offset, "timeout": timeout, "allowed_updates": ["message"]])
    }

    func send(chat: Int64, text: String) async {
        struct Ignored: Decodable {}
        // Telegram caps messages at 4096 characters.
        let body = ["chat_id": chat, "text": String(text.prefix(4000))] as [String: Any]
        let _: Ignored? = try? await call("sendMessage", body)
    }
}

// MARK: - Bot

/// Lets an authorised Telegram chat control rTorrent. Security model: the bot token lives in the Keychain and
/// ONLY chats whose numeric ID is on the allow-list in Settings are obeyed; everyone else just gets their chat ID back.
/// Destructive actions (/remove, /removedata) need an explicit /confirm within 60 seconds.
@MainActor
final class TelegramBot: ObservableObject {
    static let keychainAccount = "telegram-bot-token"

    enum State: Equatable {
        case stopped
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .stopped

    private weak var appState: AppState?
    private weak var listVM: TorrentListViewModel?
    private var task: Task<Void, Never>?
    private var api: TelegramAPI?
    private var allowed: Set<Int64> = []
    private var lastListing: [Int64: [String]] = [:]
    private var pending: [Int64: (summary: String, hashes: [String], withData: Bool, expires: Date)] = [:]
    private var didRegisterCompletionHook = false

    func attach(appState: AppState, listVM: TorrentListViewModel) {
        self.appState = appState
        self.listVM = listVM
        reload()
        guard !didRegisterCompletionHook else { return }
        didRegisterCompletionHook = true
        listVM.onTorrentCompleted.append { [weak self] torrent in
            self?.broadcast("✅ Descarga completada: \(torrent.name)")
        }
    }

    /// Re-reads the saved settings and (re)starts or stops polling accordingly.
    func reload() {
        task?.cancel()
        task = nil
        let defaults = UserDefaults.standard
        let token = KeychainHelper.loadPassword(account: Self.keychainAccount) ?? ""
        allowed = parseTelegramChatIDs(defaults.string(forKey: Preferences.telegramChatIDsKey) ?? "")
        guard defaults.bool(forKey: Preferences.telegramEnabledKey), !token.isEmpty else {
            state = .stopped
            api = nil
            return
        }
        let api = TelegramAPI(token: token)
        self.api = api
        state = .running
        task = Task { [weak self] in await self?.run(api) }
    }

    private func broadcast(_ text: String) {
        guard let api, state == .running else { return }
        for chat in allowed { Task { await api.send(chat: chat, text: text) } }
    }

    private func run(_ api: TelegramAPI) async {
        var offset = 0
        // Skip anything queued while the app was closed, so old commands (e.g. a stale /removedata) never replay.
        if let backlog = try? await api.updates(offset: -1, timeout: 0), let last = backlog.last {
            offset = last.update_id + 1
        }
        while !Task.isCancelled {
            do {
                let updates = try await api.updates(offset: offset, timeout: 25)
                if state != .running { state = .running }
                for update in updates {
                    offset = update.update_id + 1
                    guard let message = update.message, let text = message.text else { continue }
                    await handle(text: text, chat: message.chat.id, api: api)
                }
            } catch {
                if Task.isCancelled { return }
                state = .failed(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    // MARK: Command handling

    private func handle(text: String, chat: Int64, api: TelegramAPI) async {
        guard allowed.contains(chat) else {
            await api.send(chat: chat, text: "No autorizado. Tu chat ID es \(chat); añádelo en Ajustes de rTorrent Remote para usar este bot.")
            return
        }
        guard let client = appState?.client, let listVM else {
            await api.send(chat: chat, text: "La app no está conectada a ningún servidor rTorrent.")
            return
        }
        await listVM.refresh()
        let reply = await execute(TelegramCommand.parse(text), chat: chat, client: client, listVM: listVM)
        await api.send(chat: chat, text: reply)
    }

    private func execute(_ command: TelegramCommand, chat: Int64, client: RTorrentClient, listVM: TorrentListViewModel) async -> String {
        do {
            switch command {
            case .help, .unknown:
                return """
                Comandos:
                /list [descargando|compartiendo|pausados|completados]
                /status — velocidades globales
                /pause <n|nombre|all> · /resume <n|nombre|all>
                /add <magnet o URL> (o envía el enlace directamente)
                /remove <n> — quitar torrent (conserva archivos)
                /removedata <n> — quitar torrent y archivos
                /confirm · /cancel — confirmar o anular un borrado
                /speed [bajada subida] — límites en KB/s (0 = sin límite)
                <n> es el número mostrado por /list.
                """
            case .status:
                return "↓ \(Formatters.rate(listVM.globalDownRate))  ↑ \(Formatters.rate(listVM.globalUpRate))\n\(listVM.torrents.count) torrents, \(listVM.torrents.filter { $0.status == .downloading }.count) descargando"
            case .list(let filterText):
                let list = listVM.torrents.filter { Self.matches($0, filter: filterText) }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                lastListing[chat] = list.map(\.hash)
                if list.isEmpty { return "No hay torrents." }
                let lines = list.prefix(40).enumerated().map { i, t in
                    "\(i + 1). \(t.name)\n   \(Formatters.percent(t.progress)) · ↓\(Formatters.rate(t.downRate)) ↑\(Formatters.rate(t.upRate)) · \(t.status.label)"
                }
                return lines.joined(separator: "\n") + (list.count > 40 ? "\n… y \(list.count - 40) más" : "")
            case .pause(let target), .resume(let target):
                let isPause: Bool
                if case .pause = command { isPause = true } else { isPause = false }
                let torrents = try resolve(target, chat: chat, listVM: listVM, allowAll: true)
                for t in torrents { isPause ? try await client.pause(hash: t.hash) : try await client.resume(hash: t.hash) }
                await listVM.refresh()
                return "\(isPause ? "Pausado" : "Reanudado"): \(torrents.count) torrent(s)."
            case .add(let uri):
                try await client.addFromURI(uri, startImmediately: true)
                await listVM.refresh()
                return "Torrent añadido."
            case .remove(let target), .removeData(let target):
                let withData: Bool
                if case .removeData = command { withData = true } else { withData = false }
                let torrents = try resolve(target, chat: chat, listVM: listVM, allowAll: false)
                let names = torrents.map(\.name).joined(separator: ", ")
                pending[chat] = (names, torrents.map(\.hash), withData, Date().addingTimeInterval(60))
                return "⚠️ ¿\(withData ? "Eliminar torrent Y ARCHIVOS" : "Eliminar torrent") de: \(names)?\nResponde /confirm en menos de 60 s o /cancel."
            case .confirm:
                guard let p = pending.removeValue(forKey: chat), p.expires > Date() else {
                    return "No hay nada pendiente de confirmar."
                }
                let disposal = Preferences.dataDisposal
                for hash in p.hashes {
                    if p.withData { try await client.removeWithData(hash: hash, disposal: disposal) }
                    else { try await client.remove(hash: hash) }
                }
                await listVM.refresh()
                return "Eliminado: \(p.summary)"
            case .cancel:
                pending[chat] = nil
                return "Cancelado."
            case .speed(let down, let up):
                if let down {
                    try await client.setGlobalSpeedLimits(downKBps: down, upKBps: up ?? 0)
                }
                let limits = try await client.fetchGlobalSpeedLimits()
                return "Límites: bajada \(limits.downKBps == 0 ? "sin límite" : "\(limits.downKBps) KB/s"), subida \(limits.upKBps == 0 ? "sin límite" : "\(limits.upKBps) KB/s")"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func matches(_ t: Torrent, filter: String?) -> Bool {
        switch filter {
        case nil: return true
        case "descargando", "downloading": return t.status == .downloading
        case "compartiendo", "seeding": return t.status == .seeding
        case "pausados", "paused": return t.status == .paused || t.status == .stopped
        case "completados", "completed": return t.isComplete
        default: return t.name.localizedCaseInsensitiveContains(filter ?? "")
        }
    }

    /// Resolves "3", "all" or a unique name fragment to torrents.
    private func resolve(_ target: String, chat: Int64, listVM: TorrentListViewModel, allowAll: Bool) throws -> [Torrent] {
        if allowAll && target.lowercased() == "all" { return listVM.torrents }
        if let n = Int(target) {
            guard let hashes = lastListing[chat], n >= 1, n <= hashes.count,
                  let torrent = listVM.torrents.first(where: { $0.hash == hashes[n - 1] }) else {
                throw TelegramAPIError(message: "Número no válido. Usa /list primero.")
            }
            return [torrent]
        }
        let matches = listVM.torrents.filter { $0.name.localizedCaseInsensitiveContains(target) }
        guard matches.count == 1 else {
            throw TelegramAPIError(message: matches.isEmpty ? "No hay ningún torrent llamado «\(target)»." : "«\(target)» coincide con \(matches.count) torrents; usa el número de /list.")
        }
        return matches
    }
}
