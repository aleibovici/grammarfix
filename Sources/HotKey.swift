import Carbon.HIToolbox

/// Global hotkeys via Carbon. Works system-wide without Accessibility permission.
final class HotKey {
    static let shared = HotKey()

    enum Slot: UInt32, CaseIterable {
        case primary = 1
        case oneShot = 2
    }

    var handlers: [Slot: () -> Void] = [:]
    private var refs: [Slot: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private static let signature = OSType(0x47465831) // "GFX1"

    /// Returns false if the system refused the registration (e.g. the combo is taken).
    @discardableResult
    func register(_ shortcut: Shortcut, as slot: Slot) -> Bool {
        unregister(slot)
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[slot] = ref
            return true
        }
        return false
    }

    func registerAll(primary: Shortcut, oneShot: Shortcut) {
        register(primary, as: .primary)
        register(oneShot, as: .oneShot)
    }

    /// True if the combo is an enabled macOS system shortcut (Spotlight, screenshots,
    /// Mission Control, input source switching, …).
    static func isSystemShortcut(_ shortcut: Shortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int) == Int(shortcut.keyCode)
                && (entry[kHISymbolicHotKeyModifiers as String] as? Int) == Int(shortcut.carbonModifiers)
        }
    }

    func unregister(_ slot: Slot? = nil) {
        if let slot {
            if let ref = refs.removeValue(forKey: slot) {
                UnregisterEventHotKey(ref)
            }
        } else {
            for s in Slot.allCases { unregister(s) }
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ in
            guard let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let slot = Slot(rawValue: hkID.id) {
                DispatchQueue.main.async { HotKey.shared.handlers[slot]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
