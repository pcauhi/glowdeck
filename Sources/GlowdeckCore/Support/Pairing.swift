import Foundation
import Security

/// A hub or light that was found but needs the user to do something before we can control it
/// (press the Hue bridge button, hold the Nanoleaf power button, paste a Home Assistant token…).
public final class Pairing: Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let instructions: String
    /// When non-nil, the UI shows a text field with this placeholder (e.g. a token).
    public let inputPrompt: String?
    private let attemptHandler: (String?, @escaping (Result<Void, PairingError>) -> Void) -> Void

    public init(id: String, title: String, instructions: String, inputPrompt: String? = nil,
                attempt: @escaping (String?, @escaping (Result<Void, PairingError>) -> Void) -> Void) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.inputPrompt = inputPrompt
        self.attemptHandler = attempt
    }

    public func attempt(input: String? = nil, completion: @escaping (Result<Void, PairingError>) -> Void) {
        attemptHandler(input, completion)
    }
}

public struct PairingError: Error, CustomStringConvertible {
    public var description: String
    public init(_ d: String) { description = d }
}

/// Callbacks a provider uses to report back to the manager.
public struct ProviderContext {
    public var found: (LightDevice) -> Void
    public var needsPairing: (Pairing) -> Void
    public var paired: (String) -> Void
    public init(found: @escaping (LightDevice) -> Void, needsPairing: @escaping (Pairing) -> Void,
                paired: @escaping (String) -> Void) {
        self.found = found; self.needsPairing = needsPairing; self.paired = paired
    }
}

/// Secrets (Hue usernames, Nanoleaf/Home Assistant tokens) live in the login Keychain.
public enum Credentials {
    private static let service = "app.glowdeck.credentials"

    public static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public static func set(_ key: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Keys of every stored credential with a prefix, e.g. "ha:" → saved Home Assistant URLs.
    public static func keys(prefix: String) -> [String] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }
}
