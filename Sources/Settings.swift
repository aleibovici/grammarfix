import AppKit
import Carbon.HIToolbox
import Security

struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    /// Same key and modifiers, ignoring the display string.
    func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    // ⌃⌥G
    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_G),
        carbonModifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥G"
    )

    // ⌃⌥H — same modifiers as the primary, adjacent key.
    static let oneShotDefault = Shortcut(
        keyCode: UInt32(kVK_ANSI_H),
        carbonModifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥H"
    )
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// `apiKey` and `model` always reflect the selected provider; each provider keeps its own.
    @Published var provider: Provider {
        didSet {
            defaults.set(provider.rawValue, forKey: "provider")
            apiKey = Keychain.get(account: provider.keychainAccount) ?? ""
            model = defaults.string(forKey: provider.modelDefaultsKey) ?? provider.defaultModel
        }
    }
    @Published var apiKey: String {
        didSet { Keychain.set(apiKey, account: provider.keychainAccount) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: provider.modelDefaultsKey) }
    }
    @Published var extraInstructions: String {
        didSet { defaults.set(extraInstructions, forKey: "extraInstructions") }
    }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "shortcutKeyCode")
            defaults.set(Int(shortcut.carbonModifiers), forKey: "shortcutModifiers")
            defaults.set(shortcut.display, forKey: "shortcutDisplay")
            onShortcutChange?()
        }
    }
    @Published var oneShotShortcut: Shortcut {
        didSet {
            defaults.set(Int(oneShotShortcut.keyCode), forKey: "oneShotShortcutKeyCode")
            defaults.set(Int(oneShotShortcut.carbonModifiers), forKey: "oneShotShortcutModifiers")
            defaults.set(oneShotShortcut.display, forKey: "oneShotShortcutDisplay")
            onShortcutChange?()
        }
    }

    var onShortcutChange: (() -> Void)?

    /// Apple on-device on first launch; OpenRouter if it's unavailable or a key was already saved.
    private static var initialProvider: Provider {
        let hasOpenRouterKey = !(Keychain.get(account: Provider.openRouter.keychainAccount) ?? "").isEmpty
        return !hasOpenRouterKey && GrammarAPI.appleLocalUnavailableReason() == nil ? .appleLocal : .openRouter
    }

    private init() {
        let provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? Settings.initialProvider
        self.provider = provider
        apiKey = Keychain.get(account: provider.keychainAccount) ?? ""
        model = defaults.string(forKey: provider.modelDefaultsKey) ?? provider.defaultModel
        extraInstructions = defaults.string(forKey: "extraInstructions") ?? ""
        if let display = defaults.string(forKey: "shortcutDisplay") {
            shortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: "shortcutKeyCode")),
                carbonModifiers: UInt32(defaults.integer(forKey: "shortcutModifiers")),
                display: display
            )
        } else {
            shortcut = .default
        }
        if let display = defaults.string(forKey: "oneShotShortcutDisplay") {
            oneShotShortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: "oneShotShortcutKeyCode")),
                carbonModifiers: UInt32(defaults.integer(forKey: "oneShotShortcutModifiers")),
                display: display
            )
        } else {
            oneShotShortcut = .oneShotDefault
        }
    }
}

enum Keychain {
    private static let service = "nz.grammarfix.app"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
