#!/bin/sh
# Points the Homebrew cask (ranawaqas-ai/homebrew-tap) at the released zip.
# Run after the GitHub release exists, since the cask's checksum must match it.
# Usage: scripts/bump-cask.sh
set -eu

cd "$(dirname "$0")/.."
REPO=ranawaqas-ai/homebrew-tap
CASK=Casks/lafz-prompter.rb
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" packaging/Info.plist)
SHA=$(curl -fsSL "https://github.com/ranawaqas-ai/lafz-prompter/releases/download/v$VERSION/LafzPrompter.zip" | shasum -a 256 | cut -d' ' -f1)

CURRENT_SHA=$(gh api "repos/$REPO/contents/$CASK" --jq .sha)
gh api "repos/$REPO/contents/$CASK" --jq .content | base64 -d \
    | sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    > build/lafz-prompter.rb

gh api -X PUT "repos/$REPO/contents/$CASK" \
    -f message="Update lafz-prompter to $VERSION" \
    -f content="$(base64 < build/lafz-prompter.rb)" \
    -f sha="$CURRENT_SHA" --silent
echo "Cask now at $VERSION ($SHA)"
