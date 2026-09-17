# Contributing

Thanks for helping out. GrammarFix is deliberately small, so the bar for changes is "keeps it simple".

## Building

```bash
./build.sh            # builds build/GrammarFix.app
./build.sh --install  # builds, installs to /Applications and launches
```

There is no Xcode project and no package manager. The app is compiled with `swiftc` from the files in `Sources/`. You can still open the folder in Xcode or any editor to edit the code.

## Guidelines

- No third-party dependencies.
- Keep it one focused job: fixing the grammar of selected text.
- Match the style of the surrounding code. Comments explain why, not what.
- Test a real fix in at least a native app (Notes, Mail) and a browser text field before opening a pull request.
- Never commit API keys. Keys belong in the Keychain, not in code, defaults or logs.

## Adding a provider

Providers live in `Sources/GrammarAPI.swift`. Add a case to `Provider`, fill in its name, default model and key placeholder, then handle it in `fixGrammar` and `fetchModels`. Providers that speak the OpenAI chat completions format can reuse `chatCompletions`.

The Apple on-device provider uses the FoundationModels framework, which needs the macOS 26 SDK. Keep that code behind `#if canImport(FoundationModels)` and `#available(macOS 26.0, *)` so the app still builds with older SDKs and runs on macOS 13. `build.sh` weak-links the framework when the SDK has it.

## Reporting bugs

Please include your macOS version, the provider and model you used, the app you were typing in, and the error shown in the GrammarFix menu, if any. Don't include your API key.
