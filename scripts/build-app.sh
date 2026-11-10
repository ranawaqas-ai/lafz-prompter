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
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist build/assets-info.plist >/dev/null

# Ad-hoc signature: runs locally, but downloaded copies need
# right-click > Open the first time (no Apple Developer ID).
codesign --force --deep --sign - "$APP"

(cd build && rm -f LafzPrompter.zip && ditto -c -k --keepParent "Lafz Prompter.app" LafzPrompter.zip)
echo "Built $APP and build/LafzPrompter.zip"
