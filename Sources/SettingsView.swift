import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var models: [String] = []
    @State private var modelsError: String?
    @State private var loadingModels = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = AXIsProcessTrusted()
    // macOS doesn't notify on permission changes, so poll while Settings is open.
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(Provider.allCases) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: settings.provider) { _ in
                        models = []
                        loadModels()
                    }
                    SecureField("API key", text: $settings.apiKey, prompt: Text(settings.provider.keyPlaceholder))
                    TextField("Model", text: $settings.model, prompt: Text(settings.provider.defaultModel))
                    modelSuggestions
                }

                Section {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(shortcut: $settings.shortcut)
                    }
                    Toggle("Keep original text on clipboard", isOn: $settings.keepOriginalOnClipboard)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Additional instructions")
                        TextEditor(text: $settings.extraInstructions)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .scrollIndicators(.never)
                            .frame(height: 50)
                            .padding(4)
                            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                            .overlay(alignment: .topLeading) {
                                if settings.extraInstructions.isEmpty {
                                    Text("Optional, e.g. \"Use New Zealand English\" or \"Keep it friendly and polite\".")
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 9)
                                        .padding(.top, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.top, -8)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear { if models.isEmpty { loadModels() } }
        .onReceive(permissionTimer) { _ in accessibilityGranted = AXIsProcessTrusted() }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("GrammarFix").font(.headline)
                Text("Select text, then press \(settings.shortcut.display)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if accessibilityGranted {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
                    .help("Accessibility access is enabled.")
            } else {
                Button { requestAccessibility() } label: {
                    Label("Grant Access…", systemImage: "exclamationmark.triangle.fill")
                }
                .controlSize(.regular)
                .tint(.orange)
                .buttonStyle(.borderedProminent)
                .help("GrammarFix needs Accessibility access to copy your selection and paste the fix.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .zIndex(1)
    }

    /// Type in the Model field to filter; click a match to select it.
    @ViewBuilder private var modelSuggestions: some View {
        if let modelsError {
            HStack {
                Text(modelsError).font(.caption).foregroundStyle(.red)
                Spacer()
                Button("Retry") { loadModels() }
            }
        } else if loadingModels {
            Text("Loading models…").font(.caption).foregroundStyle(.secondary)
        } else if !matches.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { id in
                        ModelRow(id: id) { settings.model = id }
                    }
                }
            }
            .frame(height: 92)
        } else if !models.isEmpty && !models.contains(settings.model) {
            Text("No models match \"\(settings.model)\". It will be used as typed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Models matching what's typed in the Model field; empty once an exact model is chosen.
    private var matches: [String] {
        let query = settings.model.trimmingCharacters(in: .whitespaces).lowercased()
        if models.contains(settings.model) { return [] }
        if query.isEmpty { return models }
        let terms = query.split(separator: " ")
        return models.filter { id in terms.allSatisfy { id.lowercased().contains($0) } }
    }

    private func requestAccessibility() {
        // The system prompt only appears once, so also open the settings pane.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadModels() {
        loadingModels = true
        modelsError = nil
        Task {
            let provider = settings.provider
            do {
                let fetched = try await GrammarAPI.fetchModels(provider, key: settings.apiKey)
                if provider == settings.provider { models = fetched }
            } catch {
                if provider == settings.provider { modelsError = error.localizedDescription }
            }
            loadingModels = false
        }
    }
}

private struct ModelRow: View {
    let id: String
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            Text(id)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(hovering ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Click, then press a key combination to record it.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(recording ? "Press shortcut… (Esc to cancel)" : shortcut.display) {
                recording ? stop() : start()
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .orange)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        message = nil
        HotKey.shared.unregister() // so the current combo can be re-recorded
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Require a real modifier so plain typing can't become a global hotkey.
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            var carbon = 0
            var display = ""
            if flags.contains(.control) { carbon |= controlKey; display += "⌃" }
            if flags.contains(.option) { carbon |= optionKey; display += "⌥" }
            if flags.contains(.shift) { carbon |= shiftKey; display += "⇧" }
            if flags.contains(.command) { carbon |= cmdKey; display += "⌘" }
            display += keyName(for: event)
            let candidate = Shortcut(keyCode: UInt32(event.keyCode),
                                     carbonModifiers: UInt32(carbon),
                                     display: display)
            apply(candidate, flags: flags)
            return nil
        }
    }

    /// Rejects combos macOS already uses or refuses; warns about ones apps commonly use.
    private func apply(_ candidate: Shortcut, flags: NSEvent.ModifierFlags) {
        if HotKey.isSystemShortcut(candidate) {
            NSSound.beep()
            message = "\(candidate.display) is already used by macOS. Try another."
            isError = true
            return // keep recording
        }
        guard HotKey.shared.register(candidate) else {
            NSSound.beep()
            message = "\(candidate.display) is already in use. Try another."
            isError = true
            return
        }
        isError = false
        // App menus use ⌘ and ⌘⇧ combos, and a global hotkey overrides them in every app.
        message = flags.isSubset(of: [.command, .shift])
            ? "\(candidate.display) may clash with app menu shortcuts. Adding ⌃ or ⌥ is safer."
            : nil
        shortcut = candidate
        stop()
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKey.shared.register(shortcut)
    }

    private func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
