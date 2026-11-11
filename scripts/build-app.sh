#!/bin/sh
# Builds "Lafz Prompter.app" and a zip of it into build/.
# Usage: scripts/build-app.sh   (needs Xcode or the Xcode command line tools)
set -eu

cd "$(dirname "$0")/.."
APP="build/Lafz Prompter.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LafzPrompter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LafzPrompter"
cp packaging/Info.plist "$APP/Contents/Info.plist"
xcrun actool notch-prompter/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist build/assets-info.plist >/dev/null

# With SIGN_IDENTITY set (a "Developer ID Application" certificate), the app is
# signed with the hardened runtime. With NOTARY_PROFILE also set (a profile saved
# by `xcrun notarytool store-credentials`), it is notarized and stapled, so that
# downloaded copies open without a Gatekeeper warning. Otherwise it is signed
# ad hoc, which runs locally but needs right-click > Open after a download.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements packaging/LafzPrompter.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

zip_app() {
    (cd build && rm -f LafzPrompter.zip && ditto -c -k --keepParent "Lafz Prompter.app" LafzPrompter.zip)
}
zip_app

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit build/LafzPrompter.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    zip_app
fi

echo "Built $APP and build/LafzPrompter.zip"
