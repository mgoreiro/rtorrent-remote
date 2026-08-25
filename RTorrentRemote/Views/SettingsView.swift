import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    @State private var downLimit: String = "0"
    @State private var upLimit: String = "0"
    @State private var isSavingLimits = false
    @State private var limitsMessage: String?

    var body: some View {
        Form {
            Section("Servidor rTorrent") {
                TextField("Host o IP", text: $appState.profile.host)
                TextField("Puerto", value: $appState.profile.port, format: .number.grouping(.never))
                TextField("Ruta", text: $appState.profile.path)
                Toggle("Usar HTTPS", isOn: $appState.profile.useHTTPS)
                Toggle("Aceptar certificados no verificados (autofirmados)", isOn: $appState.profile.allowInsecureTLS)
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
        .task { await loadCurrentLimits() }
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
