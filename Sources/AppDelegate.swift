import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var fixMenuItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private let fixer = TextFixer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        fixer.onStateChange = { [weak self] state in self?.show(state) }
        HotKey.shared.handler = { [weak self] in self?.fixer.run() }
        Settings.shared.onShortcutChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()

        if Settings.shared.apiKey.isEmpty { openSettings() }
    }

    private func registerHotKey() {
        HotKey.shared.register(Settings.shared.shortcut)
        fixMenuItem.title = "Fix Selected Text  (\(Settings.shared.shortcut.display))"
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("text.badge.checkmark")

        let menu = NSMenu()
        fixMenuItem = menu.addItem(withTitle: "Fix Selected Text", action: #selector(fixNow), keyEquivalent: "")
        statusMenuItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statusMenuItem.isHidden = true
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GrammarFix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GrammarFix")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func show(_ state: TextFixer.State) {
        switch state {
        case .idle:
            setIcon("text.badge.checkmark")
            statusMenuItem.isHidden = true
        case .working:
            setIcon("ellipsis.circle")
            statusMenuItem.isHidden = true
        case .failed(let message):
            setIcon("exclamationmark.triangle")
            statusMenuItem.title = "Error: " + message
            statusMenuItem.isHidden = false
        }
    }

    @objc private func fixNow() {
        // The menu steals focus briefly; let the previous app become active again first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.fixer.run() }
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "GrammarFix Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.makeFirstResponder(nil)
    }

    // MARK: - Main menu

    /// An accessory app has no visible menu bar, but without an Edit menu
    /// ⌘V/⌘C/⌘A don't work in the Settings text fields.
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
