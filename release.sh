#!/bin/bash
# Builds a signed, notarised GrammarFix zip for distribution.
# Usage: ./release.sh
#
# One-time setup:
#   1. Create a "Developer ID Application" certificate (Xcode > Settings >
#      Accounts > Manage Certificates, or developer.apple.com).
#   2. Store notarisation credentials in the keychain:
#        xcrun notarytool store-credentials grammarfix-notary \
#            --apple-id you@example.com --team-id TEAMID
#      It asks for an app-specific password from account.apple.com.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-grammarfix-notary}"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
    echo "No Developer ID Application certificate found. See the setup notes at the top of this script." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
APP="build/GrammarFix.app"
ZIP="build/GrammarFix-$VERSION.zip"

CODESIGN_IDENTITY="$IDENTITY" ./build.sh

# Notarisation requires the hardened runtime and a secure timestamp.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Staple the ticket so the app opens offline, then re-zip the stapled app.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP"
echo "Release ready: $ZIP"
