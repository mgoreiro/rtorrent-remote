import Foundation

/// Non-secret user preferences stored in UserDefaults. Secrets (passwords, bot token) live in the Keychain.
enum Preferences {
    static let trashPathKey = "serverTrashPath"
    static let notificationsKey = "notificationsEnabled"
    static let telegramEnabledKey = "telegramEnabled"
    static let telegramChatIDsKey = "telegramAllowedChatIDs"

    /// Where deleted data is moved on the server; empty means "delete permanently".
    static var trashPath: String {
        UserDefaults.standard.string(forKey: trashPathKey)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var dataDisposal: DataDisposal {
        trashPath.isEmpty ? .delete : .moveToTrash(trashPath)
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? true
    }
}
