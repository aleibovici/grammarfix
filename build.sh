#!/bin/bash
# Builds GrammarFix.app into ./build. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/GrammarFix.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"  # regenerate with: swift make-icon.swift

# Weak-link FoundationModels (macOS 26+) so the app still launches on older systems.
# Older SDKs don't have it; the on-device provider is compiled out there.
LINK_FLAGS=()
if [[ -d "$(xcrun --show-sdk-path)/System/Library/Frameworks/FoundationModels.framework" ]]; then
    LINK_FLAGS=(-Xlinker -weak_framework -Xlinker FoundationModels)
fi

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    ${LINK_FLAGS[@]+"${LINK_FLAGS[@]}"} \
    -o "$APP/Contents/MacOS/GrammarFix" Sources/*.swift

# A stable signing identity keeps the Accessibility grant and Keychain access
# across rebuilds; ad-hoc signing ("-") works but macOS re-asks after each build.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x GrammarFix 2>/dev/null || true
    rm -rf /Applications/GrammarFix.app
    cp -R "$APP" /Applications/
    open /Applications/GrammarFix.app
    echo "Installed to /Applications and launched."
fi
