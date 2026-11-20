import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var bot: TelegramBot
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Preferences.trashPathKey) private var trashPath = ""
    @AppStorage(Preferences.deleteTorrentFileKey) private var deleteTorrentFile = true
    @AppStorage(Preferences.notificationsKey) private var notificationsEnabled = true
    @AppStorage(Preferences.telegramEnabledKey) private var telegramEnabled = false
    @AppStorage(Preferences.telegramChatIDsKey) private var telegramChatIDs = ""
    @State private var telegramToken = ""

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    @State private var downLimit: String = "0"
    @State private var upLimit: String = "0"
    @State private var isSavingLimits = false
    @State private var limitsMessage: String?

    var body: some View {
        Form {
            Section("Perfil") {
                Picker("Servidor", selection: Binding(
                    get: { appState.profile.id },
                    set: { appState.selectProfile($0) }
                )) {
                    ForEach(appState.profiles) { Text($0.name).tag($0.id) }
                }
                TextField("Nombre del perfil", text: $appState.profile.name)
                HStack {
                    Button("Nuevo perfil") { appState.addProfile() }
                    Button("Eliminar perfil", role: .destructive) { appState.deleteCurrentProfile() }
                        .disabled(appState.profiles.count < 2)
                }
            }

            Section("Servidor rTorrent") {
                TextField("Host o IP", text: $appState.profile.host)
                TextField("Puerto", value: $appState.profile.port, format: .number.grouping(.never))
                TextField("Ruta", text: $appState.profile.path)
                Toggle("Usar HTTPS", isOn: $appState.profile.useHTTPS)
                Toggle("Aceptar certificados no verificados (autofirmados)", isOn: $appState.profile.allowInsecureTLS)
                    .disabled(!appState.profile.pinnedCertSHA256.isEmpty)
                if appState.profile.pinnedCertSHA256.isEmpty {
                    Button("Fijar certificado actual del servidor") {
                        if let fp = appState.client?.rpc.lastServerFingerprint {
                            appState.profile.pinnedCertSHA256 = fp
                            appState.profile.allowInsecureTLS = false
                            appState.saveProfile()
                        }
                    }
                    .disabled(appState.client?.rpc.lastServerFingerprint == nil)
                    Text("Pulsa «Probar conexión» primero. Al fijar el certificado solo se aceptará ese, más seguro que aceptar cualquiera.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Certificado fijado", value: String(appState.profile.pinnedCertSHA256.prefix(16)) + "…")
                        .textSelection(.enabled)
                    Button("Quitar certificado fijado") {
                        appState.profile.pinnedCertSHA256 = ""
                        appState.saveProfile()
                    }
                }
            }

            Section("Autenticación (opcional)") {
                TextField("Usuario", text: $appState.profile.username)
                SecureField("Contraseña", text: $appState.password)
            }

            Section {
                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Probar conexión")
                        }
                    }
                    .disabled(!appState.profile.isValid || isTesting)

                    if let testResult {
                        Label(testResult, systemImage: testSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testSucceeded ? .green : .red)
                            .font(.callout)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Diagnóstico")
            } footer: {
                Text("La app habla XML-RPC por HTTP(S). En el servidor necesitas un proxy (nginx con scgi_pass o socat) delante del socket SCGI de rTorrent, expuesto en la ruta indicada arriba.")
                    .font(.caption)
            }

            Section {
                Toggle("Notificar cuando termine una descarga", isOn: $notificationsEnabled)
                Toggle("Mover a la papelera los archivos .torrent tras añadirlos", isOn: $deleteTorrentFile)
                TextField("Papelera en el servidor (vacío = borrar definitivamente)", text: $trashPath)
            } header: {
                Text("Notificaciones y borrado")
            } footer: {
                Text("Si indicas una carpeta (ruta absoluta), «Eliminar torrent y archivos» moverá los datos allí en lugar de borrarlos.")
                    .font(.caption)
            }

            Section {
                Toggle("Activar bot de Telegram", isOn: $telegramEnabled)
                SecureField("Token del bot (de @BotFather)", text: $telegramToken)
                TextField("Chat IDs autorizados (separados por comas)", text: $telegramChatIDs)
                HStack {
                    Button("Aplicar") {
                        KeychainHelper.savePassword(telegramToken, account: TelegramBot.keychainAccount)
                        bot.reload()
                    }
                    switch bot.state {
                    case .stopped: Text("Detenido").foregroundStyle(.secondary)
                    case .running: Label("Activo", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
                    }
                }
                .font(.callout)
            } header: {
                Text("Bot de Telegram")
            } footer: {
                Text("El bot solo obedece a los chats autorizados. Escríbele /start desde Telegram: si no está autorizado te responderá con tu chat ID para añadirlo aquí. La app debe estar abierta para que el bot funcione.")
                    .font(.caption)
            }

            Section("Límites globales de velocidad (KB/s, 0 = sin límite)") {
                HStack {
                    TextField("Bajada", text: $downLimit)
                    TextField("Subida", text: $upLimit)
                    Button("Aplicar") { Task { await applyLimits() } }
                        .disabled(appState.client == nil || isSavingLimits)
                }
                if let limitsMessage {
                    Text(limitsMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    appState.saveProfile()
                    dismiss()
                }
                .disabled(!appState.profile.isValid)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
            }
        }
        .task {
            telegramToken = KeychainHelper.loadPassword(account: TelegramBot.keychainAccount) ?? ""
            await loadCurrentLimits()
        }
    }

    private func testConnection() async {
        isTesting = true
        appState.saveProfile()
        do {
            let version = try await appState.client?.testConnection() ?? ""
            testResult = version.isEmpty ? "Conectado" : "Conectado (rTorrent \(version))"
            testSucceeded = true
        } catch {
            testResult = error.localizedDescription
            testSucceeded = false
        }
        isTesting = false
    }

    private func loadCurrentLimits() async {
        guard let client = appState.client else { return }
        if let limits = try? await client.fetchGlobalSpeedLimits() {
            downLimit = String(limits.downKBps)
            upLimit = String(limits.upKBps)
        }
    }

    private func applyLimits() async {
        guard let client = appState.client else { return }
        isSavingLimits = true
        do {
            try await client.setGlobalSpeedLimits(downKBps: Int(downLimit) ?? 0, upKBps: Int(upLimit) ?? 0)
            limitsMessage = "Límites actualizados."
        } catch {
            limitsMessage = error.localizedDescription
        }
        isSavingLimits = false
    }
}
