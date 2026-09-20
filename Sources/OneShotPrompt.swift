import AppKit

/// Borderless panels refuse key status unless canBecomeKey is overridden.
private final class FloatingKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Tiny floating text field near the cursor for one-shot extra instructions.
@MainActor
final class OneShotPrompt: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private var field: NSTextField?
    private var onSubmit: ((String) -> Void)?
    private var previousApp: NSRunningApplication?

    func show(onSubmit: @escaping (String) -> Void) {
        dismiss(reactivatePrevious: false)
        self.onSubmit = onSubmit
        previousApp = NSWorkspace.shared.frontmostApplication

        let width: CGFloat = 320
        let height: CGFloat = 40
        let inset: CGFloat = 8

        let field = NSTextField(frame: NSRect(x: inset, y: inset,
                                              width: width - inset * 2,
                                              height: height - inset * 2))
        field.placeholderString = "Extra instructions for this fix…"
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.delegate = self
        field.stringValue = ""
        self.field = field

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(field)

        let panel = FloatingKeyPanel(
            contentRect: container.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        self.panel = panel

        position(panel, size: container.bounds.size)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// - Parameter reactivatePrevious: Return focus to the app that had the selection.
    func dismiss(reactivatePrevious: Bool) {
        let app = previousApp
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        field = nil
        onSubmit = nil
        previousApp = nil
        if reactivatePrevious {
            app?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Placement

    private func position(_ panel: NSPanel, size: NSSize) {
        var origin = NSEvent.mouseLocation
        origin.x -= size.width / 2
        origin.y -= size.height + 12
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Submit / cancel

    private func submit() {
        let text = (field?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onSubmit
        dismiss(reactivatePrevious: true)
        // Empty submit dismisses without running a fix.
        guard !text.isEmpty else { return }
        // Let the previous app become active again before the copy/paste pipeline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            callback?(text)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss(reactivatePrevious: true)
            return true
        }
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        // User clicked elsewhere; don't steal focus back.
        dismiss(reactivatePrevious: false)
    }
}
