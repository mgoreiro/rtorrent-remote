import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let profileKey = "connectionProfile"
    private static let keychainAccount = "default"

    @Published var profile: ConnectionProfile
    @Published var password: String
    @Published private(set) var client: RTorrentClient?
    @Published var isConnected: Bool = false
    @Published var lastError: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profileKey),
           let decoded = try? JSONDecoder().decode(ConnectionProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = .empty
        }
        self.password = KeychainHelper.loadPassword(account: Self.keychainAccount) ?? ""
        rebuildClient()
    }

    func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
        KeychainHelper.savePassword(password, account: Self.keychainAccount)
        rebuildClient()
    }

    func rebuildClient() {
        guard profile.isValid else {
            client = nil
            isConnected = false
            return
        }
        client = RTorrentClient(profile: profile, password: password)
    }

    func testConnection() async {
        guard let client else {
            lastError = "Configura primero el servidor en Ajustes."
            isConnected = false
            return
        }
        do {
            _ = try await client.testConnection()
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error.localizedDescription
        }
    }
}
