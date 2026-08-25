# Releasing Scriber

Turning a verified working tree into a notarized download. [Building](BUILDING.md) covers ordinary local builds; this covers only what a public release adds.

Every tag on `main` ships a build, so do not tag until you intend to finish this whole document. The [versioning policy](VERSIONING.md) explains why.

## Prerequisites

- The **Developer ID Application** certificate for team `24U8BM54A3` in the login Keychain, with its private key. Nothing here works without it, and Apple cannot reissue the key.

  It expires **1 Feb 2027**, capped by the legacy Apple intermediate that issued it; a certificate created through the developer portal on the G2 Sub-CA instead runs to 2031. Deliberately not taken: Gaf wants the renewal as a live exercise. Releases already notarized keep validating after expiry because they are timestamped, so what expiry actually stops is signing anything new. When it lapses, create a replacement, then pin `CODE_SIGN_IDENTITY` to its SHA-1 fingerprint in `Signing.xcconfig` — two certificates sharing one common name make selection by name ambiguous. Users keep their permissions across the change: the designated requirement matches on the team identifier, which does not change.

- `create-dmg`, which arranges the disk image window. `brew install create-dmg`. Build-time only — nothing from it ships inside the app.

- A notary credential profile in the Keychain. Create it once:

```bash
xcrun notarytool store-credentials "scriber-notary" --key <path to AuthKey_XXXX.p8> --key-id <key id> --issuer <issuer uuid>
```

The `.p8` is needed only for that one command. Delete the local copy afterwards with `rm -P`, which overwrites before unlinking; the profile lives in the Keychain from then on. Omit `--issuer` if App Store Connect issued an Individual key rather than a Team key.

## 1. Version

Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in **both** configurations of the Scriber target, and compose the `Unreleased` entries in [`CHANGELOG.md`](../CHANGELOG.md) into the new version's section: merge the bullets that describe one change, drop any a later session superseded, and sort what remains under Added, Changed, Fixed, and Removed. Sessions append to `Unreleased` as they go, so this is the first time the section is read as a whole and the only place it is written as one.

## 2. Build and verify the signature

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Scriber.xcodeproj -scheme Scriber -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode-release \
  clean build
```

Run the Release bundle inspection in [Automated checks](AUTOMATED_CHECKS.md) before going further. A build that is not correctly signed and hardened will be rejected by the notary service several minutes later, with a worse error message than `codesign` gives immediately.

## 3. Notarize the app, then staple it

Staple the app *before* the disk image is built from it. A ticket stapled to the app is what lets a copy dragged out of the DMG validate with no network.

```bash
APP=.build/xcode-release/Build/Products/Release/Scriber.app
ditto -c -k --keepParent "$APP" .build/Scriber-notarize.zip
xcrun notarytool submit .build/Scriber-notarize.zip --keychain-profile "scriber-notary" --wait
xcrun stapler staple "$APP"
```

The first submission from a newly enrolled team takes far longer than later ones — allow twenty minutes or more for it, and roughly five afterwards. `--wait` holds the connection; if it is interrupted, the submission is unaffected and `xcrun notarytool history --keychain-profile "scriber-notary"` finds it again.

On rejection, ask for the reason rather than guessing:

```bash
xcrun notarytool log <submission id> --keychain-profile "scriber-notary"
```

## 4. Build, sign, notarize and staple the disk image

```bash
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=.build/dmg-stage
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Scriber.app"

create-dmg \
  --volname "Scriber $VERSION" \
  --background Branding/dmg-background.tiff \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "Scriber.app" 180 170 \
  --app-drop-link 480 170 \
  --no-internet-enable \
  ".build/Scriber-$VERSION.dmg" "$STAGE"

codesign --sign "Developer ID Application" --timestamp ".build/Scriber-$VERSION.dmg"
xcrun notarytool submit ".build/Scriber-$VERSION.dmg" --keychain-profile "scriber-notary" --wait
xcrun stapler staple ".build/Scriber-$VERSION.dmg"
```

`create-dmg` places the icons by driving Finder over AppleScript, so the first run on a machine raises an automation prompt. Answer it — unanswered, the AppleEvent times out after about two minutes and the run fails with `-1712` and no image. Do not add the `Applications` symlink to the staging folder; `--app-drop-link` makes its own, and a second one appears as a stray icon.

It emits UDZO, the same format the three commands below expect, so signing and notarization are unchanged by the styling.

The window is light in both appearances, deliberately and unavoidably: Finder draws a volume window's labels black whenever a background picture is set, whatever that picture holds, so a dark design renders black text on a dark backdrop. Verified on macOS 27. Regenerate the background with `swift Branding/DMGBackground.swift Branding` after editing it.

`hdiutil` still works but is deprecated across the board on macOS 27 in favour of `diskutil image`. Nothing here calls it directly any more; `create-dmg` does, and its warnings are expected.

The disk image is notarized separately from the app inside it, and both need it. Sign the image before submitting: an unsigned one still passes the checks below, but reports `no usable signature` to any tool that assesses it as an installer.

## 5. Verify what a stranger receives

Local files carry no quarantine flag, which is why a broken signature cannot be caught by opening the build yourself. Attach the flag by hand and assess the app the way Gatekeeper does when someone opens a download:

```bash
cp ".build/Scriber-$VERSION.dmg" /tmp/Scriber-quarantined.dmg
xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;$(uuidgen)" /tmp/Scriber-quarantined.dmg
MNT=$(mktemp -d)
hdiutil attach /tmp/Scriber-quarantined.dmg -nobrowse -readonly -mountpoint "$MNT"
spctl -a -vvv --type open --context context:primary-signature "$MNT/Scriber.app"
xcrun stapler validate "$MNT/Scriber.app"
hdiutil detach "$MNT" && rm -f /tmp/Scriber-quarantined.dmg
```

Both must pass: `accepted` with `source=Notarized Developer ID`, and a valid ticket. `spctl --type exec` is the wrong assessment for an application bundle and reports that the code is valid but does not seem to be an app; do not use it here.

## 6. Verify the candidate on real hardware, before tagging

Run the distribution checks in [Manual checks](MANUAL_CHECKS.md) against the disk image built above, while it is still only a file in `.build/`. Send it to a second macOS account and to a Mac on the oldest supported macOS by any route that marks it as downloaded; that flag, not a release URL, is what makes Gatekeeper assess it.

Doing this after tagging instead is what turns one release into several. A tag on `main` ships, so a fault found afterwards costs a new version for a build nobody could install — while the same fault found here costs a rebuild and nothing else.

Only the three things step 7 produces can still be wrong after tagging, and none of them needs a new version: a bad asset is replaced with `gh release upload --clobber`, wrong notes with `gh release edit`, and a wrong cask checksum in the tap repository alone.

## 7. Publish

Merge to `main` fast-forward only and tag there, never on the branch. Then:

Take the release notes from the version's [changelog](../CHANGELOG.md) section, whose opening line names the build and the requirements. Keep that line: someone who follows a link straight to the release page never sees the README, and the disk image gives them no warning until macOS refuses to open the app.

Open them with what taking the update requires, above the changelog. The in-app offer lands here, and the reader arriving from it is about to meet the one step nothing on screen has told them: **Scriber is running, and a running app cannot be replaced.** Say to quit it from the menu bar first, then drag. Write for that reader alone — a Homebrew install is answered inside Scriber, which offers it `brew upgrade --cask scriber` rather than sending it here, so notes addressing both audiences would be half wrong for each.

```bash
shasum -a 256 ".build/Scriber-$VERSION.dmg"
gh release create "v$VERSION" ".build/Scriber-$VERSION.dmg" --title "v$VERSION" --notes-file <(…requirements, then changelog section…)
```

Finally update `Casks/scriber.rb` in the [tap repository](https://github.com/gafiegarcia/homebrew-scriber) with the new `version` and that `sha256`. The cask points at the release asset by version, so it breaks until this lands — do it in the same sitting.
