import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let legacyProfileKey = "connectionProfile"
    private static let profilesKey = "connectionProfiles"
    private static let activeProfileKey = "activeProfileID"
    private static let legacyKeychainAccount = "default"

    /// The profile currently being used/edited (Settings binds directly to it).
    @Published var profile: ConnectionProfile
    @Published private(set) var profiles: [ConnectionProfile]
    @Published var password: String
    @Published private(set) var client: RTorrentClient?
    @Published var isConnected: Bool = false
    @Published var lastError: String?

    init() {
        let defaults = UserDefaults.standard
        var loaded: [ConnectionProfile] = []
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            loaded = decoded
        } else if let data = defaults.data(forKey: Self.legacyProfileKey),
                  let legacy = try? JSONDecoder().decode(ConnectionProfile.self, from: data) {
            // Migrate the single-profile layout (and its Keychain entry) to the multi-profile one.
            loaded = [legacy]
            if let pw = KeychainHelper.loadPassword(account: Self.legacyKeychainAccount) {
                KeychainHelper.savePassword(pw, account: legacy.id.uuidString)
            }
        }
        if loaded.isEmpty { loaded = [.empty] }
        let activeID = defaults.string(forKey: Self.activeProfileKey).flatMap(UUID.init(uuidString:))
        let active = loaded.first { $0.id == activeID } ?? loaded[0]
        self.profiles = loaded
        self.profile = active
        self.password = KeychainHelper.loadPassword(account: active.id.uuidString) ?? ""
        rebuildClient()
    }

    func saveProfile() {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        KeychainHelper.savePassword(password, account: profile.id.uuidString)
        rebuildClient()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.profilesKey) }
        defaults.set(profile.id.uuidString, forKey: Self.activeProfileKey)
    }

    func selectProfile(_ id: UUID) {
        guard id != profile.id, let target = profiles.first(where: { $0.id == id }) else { return }
        saveProfile()
        profile = target
        password = KeychainHelper.loadPassword(account: target.id.uuidString) ?? ""
        persist()
        rebuildClient()
    }

    func addProfile() {
        saveProfile()
        var fresh = ConnectionProfile.empty
        fresh.id = UUID()
        fresh.name = "Servidor \(profiles.count + 1)"
        profiles.append(fresh)
        profile = fresh
        password = ""
        persist()
        rebuildClient()
    }

    func deleteCurrentProfile() {
        guard profiles.count > 1 else { return }
        KeychainHelper.deletePassword(account: profile.id.uuidString)
        profiles.removeAll { $0.id == profile.id }
        profile = profiles[0]
        password = KeychainHelper.loadPassword(account: profile.id.uuidString) ?? ""
        persist()
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
