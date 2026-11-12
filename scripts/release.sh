#!/bin/sh
# Adds the zip from scripts/build-app.sh to the update feed (Sparkle appcast).
# Run after a notarized build, then rebuild the website and push it with the
# GitHub release, so the feed never points at a zip that does not exist yet.
# Usage: scripts/release.sh
set -eu

cd "$(dirname "$0")/.."
ZIP=build/LafzPrompter.zip
APPCAST=website/public/appcast.xml
PLIST=packaging/Info.plist

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST")

if grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"; then
    echo "Build $BUILD is already in $APPCAST" >&2
    exit 1
fi

# Prints: sparkle:edSignature="..." length="..."
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account lafz-prompter "$ZIP")

python3 - "$APPCAST" "$VERSION" "$BUILD" "$MIN_OS" "$SIGNATURE" <<'EOF'
import sys
from email.utils import formatdate
path, version, build, min_os, signature = sys.argv[1:]
url = f"https://github.com/ranawaqas-ai/lafz-prompter/releases/download/v{version}/LafzPrompter.zip"
item = f"""    <item>
      <title>Version {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/ranawaqas-ai/lafz-prompter/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
"""
text = open(path).read()
# Newest first: the item goes right after the channel's own elements.
anchor = "    <language>en</language>\n"
open(path, "w").write(text.replace(anchor, anchor + item, 1))
EOF

echo "Added $VERSION ($BUILD) to $APPCAST"
