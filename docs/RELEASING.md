# Releasing Vega

One command ships an update. Every installed copy finds it within an hour (or at once through Vega › Check for Updates…) and installs it on the next relaunch.

```bash
scripts/release.sh 1.6.1             # stable
scripts/release.sh 1.7.0-beta.1      # marked as a pre-release on GitHub
scripts/release.sh 1.6.1 --dry-run   # build, sign, DMG and feed only; publishes nothing
```

Run it from a clean `main`. It:

1. sets the version, bumps the build number (Sparkle orders updates by it), builds Release for Apple Silicon;
2. signs: Developer ID + notarization when set up (below), ad-hoc otherwise;
3. makes `Vega-X.Y.Z.dmg` with an Applications shortcut and `scripts/dmg/Read Me First.txt`;
4. signs the DMG for Sparkle with the EdDSA key in the login Keychain and writes the feed;
5. commits "Release vega-vX.Y.Z", tags `vega-vX.Y.Z` (upstream Nook owns the plain `vX.Y.Z` tags), pushes, creates the GitHub Release with the DMG, and publishes the feed to the `gh-pages` branch, served at <https://clarifyingchaos.github.io/vega-browser/appcast.xml>.

Release notes: add a `## Vega X.Y.Z` section to `VEGA_CHANGELOG.md` before releasing and the script uses it; `RELEASE_NOTES=notes.md` overrides it, and with neither GitHub writes notes from the commits.

## Keys and accounts

| What | Where | Notes |
|---|---|---|
| Sparkle EdDSA private key | login Keychain on the release Mac | Public half is `SUPublicEDKey` in `Nook/Info.plist`. Back it up: `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-key.txt`, store the file somewhere safe, delete it. Losing it means installed copies can't update. |
| GitHub | `gh auth login` as ClarifyingChaos | |
| Developer ID certificate | login Keychain | Optional, needs the paid Apple Developer Program. |
| Notary profile `vega-notary` | Keychain | Optional, with the certificate. |

## Turning on notarization, push notifications and password autofill

These need the paid [Apple Developer Program](https://developer.apple.com/programs/) ($99/year). It's needed even outside the App Store: Developer ID signing, notarization and the push and AutoFill entitlements all come with it.

1. **Certificate:** Xcode › Settings › Accounts › your team › Manage Certificates › + › **Developer ID Application**.
2. **App ID:** in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), register `com.vega.browser` with **Push Notifications** and **AutoFill Credential Provider**.
3. **Profile:** create a **Developer ID** provisioning profile for that App ID, download it to `scripts/signing/Vega_Developer_ID.provisionprofile` (ignored by git).
4. **Notary profile:** `xcrun notarytool store-credentials vega-notary --apple-id <your Apple ID> --team-id <TEAMID>` with an app-specific password.

The next `scripts/release.sh` picks all of this up: the app is notarized (no Open Anyway), and push notifications and password autofill work. Nothing else changes.

## Upstream

`develop` mirrors [nook-browser/Nook](https://github.com/nook-browser/Nook). The *Sync upstream* workflow fast-forwards it daily and opens a pull request into `main`. Review it, fix conflicts like any merge (keep `com.vega.browser`, keep `// FORK:` code), merge, then release.
