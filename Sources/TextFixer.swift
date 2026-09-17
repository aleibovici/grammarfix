import AppKit
import Carbon.HIToolbox

/// Copies the selection from the frontmost app, fixes it, and pastes it back.
@MainActor
final class TextFixer {
    enum State { case idle, working, failed(String) }

    var onStateChange: ((State) -> Void)?
    private var isRunning = false

    func run() {
        guard !isRunning else { return }
        guard ensureAccessibility() else { return }
        isRunning = true
        onStateChange?(.working)
        Task {
            do {
                try await fixSelection()
                onStateChange?(.idle)
            } catch {
                NSSound.beep()
                onStateChange?(.failed(error.localizedDescription))
            }
            isRunning = false
        }
    }

    private func fixSelection() async throws {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        await waitForModifierRelease()

        let before = pasteboard.changeCount
        postKey(CGKeyCode(kVK_ANSI_C))
        var waited = 0
        while pasteboard.changeCount == before && waited < 20 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        guard pasteboard.changeCount != before,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarAPI.APIError(message: "No text selected.")
        }

        let fixed: String
        do {
            fixed = try await GrammarAPI.fixGrammar(text)
        } catch {
            restore(saved, to: pasteboard)
            throw error
        }

        pasteboard.clearContents()
        pasteboard.setString(fixed, forType: .string)
        postKey(CGKeyCode(kVK_ANSI_V))

        // Give the target app time to read the pasteboard before restoring it.
        try? await Task.sleep(nanoseconds: 700_000_000)
        if Settings.shared.keepOriginalOnClipboard {
            // Lets the user paste the original back if the fix is wrong.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } else {
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - Accessibility

    private func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            onStateChange?(.failed("Grant Accessibility access in System Settings → Privacy & Security, then try again."))
        }
        return trusted
    }

    // MARK: - Keyboard

    /// The hotkey's own modifiers would otherwise combine with the synthetic ⌘C.
    private func waitForModifierRelease() async {
        let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        var waited = 0
        while !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty && waited < 40 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            waited += 1
        }
    }

    private func postKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Pasteboard

    private func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    private func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
