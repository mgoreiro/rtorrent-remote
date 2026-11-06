import SwiftUI

@main
struct RTorrentRemoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var listVM = TorrentListViewModel()
    @StateObject private var bot = TelegramBot()

    var body: some Scene {
        WindowGroup {
            ContentView(listVM: listVM)
                .environmentObject(appState)
                .environmentObject(bot)
                .frame(minWidth: 900, minHeight: 560)
                // Reuse the existing window when a magnet link / .torrent file is opened.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Añadir torrent…") {
                    NotificationCenter.default.post(name: .addTorrentRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(listVM: listVM)
        } label: {
            Label(Formatters.rate(listVM.globalDownRate), systemImage: appState.isConnected ? "arrow.down.circle" : "wifi.slash")
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(bot)
                .frame(width: 460)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var listVM: TorrentListViewModel

    var body: some View {
        Text("↓ \(Formatters.rate(listVM.globalDownRate))   ↑ \(Formatters.rate(listVM.globalUpRate))")
        Text("\(listVM.torrents.count) torrents · \(listVM.torrents.filter { $0.status == .downloading }.count) descargando")
        Divider()
        Button("Abrir rTorrent Remote") { NSApp.activate(ignoringOtherApps: true) }
        Button("Salir") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
