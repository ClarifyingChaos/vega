#!/usr/bin/env bash
# Licensed under GPL-3.0. See LICENSE.
#
# Vega release: one command from a clean `main` to an update every installed copy picks up.
#
#   scripts/release.sh 1.6.1            build, sign, DMG, GitHub Release, update feed
#   scripts/release.sh 1.6.1 --dry-run  everything up to the DMG and appcast, publishes nothing
#
# Signing picks the best that is set up on this Mac:
#   - "Developer ID Application" certificate + notarytool profile "vega-notary"
#       → signed, notarized, stapled: opens with no warning.
#     Plus scripts/signing/Vega_Developer_ID.provisionprofile (push + password autofill)
#       → those two features switch on.
#   - otherwise ad-hoc: works, but the first open needs System Settings › Open Anyway.
# Updates are signed with the Sparkle EdDSA key in the login Keychain (see docs/RELEASING.md).

set -euo pipefail

VERSION="${1:?usage: scripts/release.sh X.Y.Z [--dry-run]}"
DRY_RUN=false; [[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || { echo "version must look like 1.6.1 or 1.6.1-beta.1"; exit 1; }

REPO="ClarifyingChaos/vega"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
OUT="$ROOT/build/release-out"
PBX="Nook.xcodeproj/project.pbxproj"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
DMG_NAME="Vega-$VERSION.dmg"
TAG="v$VERSION"

# --- Preconditions ---------------------------------------------------------------------------
if ! $DRY_RUN; then
  [[ "$(git branch --show-current)" == "main" ]] || { echo "release from main"; exit 1; }
  [[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean"; exit 1; }
  git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG already exists"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh is not signed in"; exit 1; }
fi

# --- Version: marketing from the argument, build number +1 (Sparkle orders by it) --------------
OLD_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | grep -oE '[0-9]+')
NEW_BUILD=$((OLD_BUILD + 1))
if ! $DRY_RUN; then
  # Only the macOS target's values (the iOS target has its own build number).
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/" "$PBX"
  sed -i '' -E "s/MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+[^;]*;/MARKETING_VERSION = $VERSION;/" "$PBX"
fi
echo "▸ Vega $VERSION (build $($DRY_RUN && echo $OLD_BUILD || echo $NEW_BUILD))"

# --- Build ------------------------------------------------------------------------------------
xcodebuild -scheme Nook -configuration Release -arch arm64 -derivedDataPath build/release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  -skipPackagePluginValidation -skipMacroValidation -quiet
[[ -x "$SPARKLE_BIN/sign_update" ]] || SPARKLE_BIN="$(find build -path '*sparkle/Sparkle/bin' -type d | head -1)"

rm -rf "$OUT"; mkdir -p "$OUT/stage"
APP="$OUT/stage/Vega.app"
ditto build/release/Build/Products/Release/Nook.app "$APP"

# --- Sign -------------------------------------------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | grep -oE '"[^"]+"' | tr -d '"' || true)
PROFILE="$ROOT/scripts/signing/Vega_Developer_ID.provisionprofile"
NOTARIZE=false
if [[ -n "$IDENTITY" ]]; then
  ENTITLEMENTS="Nook/Nook-CI.entitlements"
  if [[ -f "$PROFILE" ]]; then
    # Push and autofill need the profile; Developer ID push is the production APNs environment.
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    ENTITLEMENTS="$OUT/Vega.entitlements"
    cp Nook/Nook.entitlements "$ENTITLEMENTS"
    plutil -replace com.apple.developer.aps-environment -string production "$ENTITLEMENTS"
    echo "▸ push notifications and password autofill: on"
  fi
  echo "▸ signing with $IDENTITY"
  # Inside out: Sparkle's helpers, the framework, then the app.
  find "$APP/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) -print0 |
    xargs -0 -I{} codesign --force --options runtime --timestamp --sign "$IDENTITY" "{}"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  xcrun notarytool history --keychain-profile vega-notary >/dev/null 2>&1 && NOTARIZE=true
else
  echo "▸ no Developer ID certificate: ad-hoc signature (first open needs Open Anyway)"
  codesign --force --deep --sign - --entitlements Nook/Nook-CI.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"

# --- DMG --------------------------------------------------------------------------------------
cp "scripts/dmg/Read Me First.txt" "$OUT/stage/"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -volname "Vega" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$OUT/$DMG_NAME" -quiet
if $NOTARIZE; then
  codesign --sign "$IDENTITY" --timestamp "$OUT/$DMG_NAME"
  echo "▸ notarizing (a few minutes)"
  xcrun notarytool submit "$OUT/$DMG_NAME" --keychain-profile vega-notary --wait
  xcrun stapler staple "$OUT/$DMG_NAME"
fi
hdiutil verify "$OUT/$DMG_NAME" -quiet

# --- Sparkle appcast --------------------------------------------------------------------------
SIG_LINE=$("$SPARKLE_BIN/sign_update" "$OUT/$DMG_NAME")   # sparkle:edSignature="..." length="..."
URL="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"
BUILD_FOR_FEED=$($DRY_RUN && echo $OLD_BUILD || echo $NEW_BUILD)
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Vega</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Vega $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_FOR_FEED</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.5</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIG_LINE />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT/appcast.xml"
echo "▸ built $OUT/$DMG_NAME"

$DRY_RUN && { echo "▸ dry run: nothing published"; exit 0; }

# --- Publish ----------------------------------------------------------------------------------
git commit -qam "Release $TAG"
git tag -a "$TAG" -m "Vega $VERSION"
git push -q origin main "$TAG"

PRERELEASE=""; [[ "$VERSION" == *-beta.* ]] && PRERELEASE="--prerelease"
gh release create "$TAG" "$OUT/$DMG_NAME" --repo "$REPO" --title "Vega $VERSION" \
  --notes-file "${RELEASE_NOTES:-/dev/null}" --generate-notes $PRERELEASE

# The feed lives on the gh-pages branch, served at https://clarifyingchaos.github.io/vega/appcast.xml
PAGES="$OUT/gh-pages"
if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git clone -q --depth 1 --branch gh-pages "$(git remote get-url origin)" "$PAGES"
else
  mkdir -p "$PAGES" && git -C "$PAGES" init -q -b gh-pages && git -C "$PAGES" remote add origin "$(git remote get-url origin)"
  touch "$PAGES/.nojekyll"
fi
cp "$OUT/appcast.xml" "$PAGES/appcast.xml"
git -C "$PAGES" add -A && git -C "$PAGES" commit -qm "Appcast: Vega $VERSION" && git -C "$PAGES" push -q origin gh-pages
gh api -X POST "repos/$REPO/pages" -f "source[branch]=gh-pages" -f "source[path]=/" >/dev/null 2>&1 || true

echo "▸ released: https://github.com/$REPO/releases/tag/$TAG"
