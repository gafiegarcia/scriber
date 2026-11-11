#!/bin/bash
# Inspects the exact Release bundle that will be installed or shipped. Run it
# after a Release build and before replacing /Applications or notarizing.
#
# Each thing below must hold, and each defends a real mistake. This script asserts
# them rather than printing them for someone to read past.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_PATH="${1:-$REPO_ROOT/.build/xcode-release/Build/Products/Release/Scriber.app}"
TEAM="24U8BM54A3"

if [ ! -d "$APP_PATH" ]; then
  echo "REFUSING: no app at $APP_PATH — build Release first" >&2
  exit 1
fi

fail() { echo "FAILED: $1" >&2; exit 1; }

echo "==> $APP_PATH"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist"

codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'

# Anything not anchored to Apple's Developer ID chain for this team is a
# different app to macOS, and its permission grants will not carry over.
requirement="$(codesign -d -r- "$APP_PATH" 2>/dev/null)"
echo "$requirement" | grep -q "anchor apple generic" \
  || fail "the designated requirement does not anchor to Apple"
echo "$requirement" | grep -q "$TEAM" \
  || fail "the designated requirement does not name team $TEAM"

# Without the hardened runtime, notarization refuses the build.
# Read into a variable first: grep -q closes the pipe early, and under
# `set -o pipefail` that makes the whole pipeline report failure.
details="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
echo "$details" | grep -q "flags=.*runtime" \
  || fail "CodeDirectory flags do not include runtime"

# An entitlement Scriber does not use is a notarization rejection waiting to
# happen; a missing one takes the microphone away at runtime, not at build time.
entitlements="$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null)"
echo "$entitlements" | grep -q "com.apple.security.device.audio-input" \
  || fail "the audio-input entitlement is missing"
unexpected="$(echo "$entitlements" | grep -c "com.apple.security" || true)"
[ "$unexpected" -eq 1 ] \
  || fail "more entitlements than audio-input alone: $entitlements"

# Scriber uses no entitlement that requires one, so a profile appearing means
# something turned on automatic signing.
[ -e "$APP_PATH/Contents/embedded.provisionprofile" ] \
  && fail "a provisioning profile is embedded"

# Sparkle ships its helpers ad-hoc signed. The Sign Sparkle build phase signs
# them with this team's identity and removes the XPC services; a helper that
# escaped it is rejected by the notary service, and an XPC service left behind
# is unsigned code nothing uses.
SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
[ -d "$SPARKLE" ] || fail "Sparkle.framework is not embedded"
[ -e "$SPARKLE/Versions/B/XPCServices" ] && fail "Sparkle's XPC services are still embedded"
for nested in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
  nested_details="$(codesign -d --verbose=4 "$nested" 2>&1)"
  echo "$nested_details" | grep -q "TeamIdentifier=$TEAM" \
    || fail "${nested#"$APP_PATH"/} is not signed by team $TEAM"
  echo "$nested_details" | grep -q "flags=.*runtime" \
    || fail "${nested#"$APP_PATH"/} is not signed with the hardened runtime"
done
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
  || fail "nested code does not verify"

# The test-appcast option is compiled into Debug alone. Its string in the
# Release binary means the gate became a runtime check, and the shipped app can
# be pointed at another feed. Every file in MacOS, because a Debug build keeps
# its code in a dylib beside the executable.
for binary in "$APP_PATH"/Contents/MacOS/*; do
  strings -a "$binary" | grep -q -- "--debug-appcast" \
    && fail "${binary#"$APP_PATH"/} contains --debug-appcast"
done

# Installed copies update from this feed, signed with this key, and nothing
# else. A key that changes strands every install that holds the old one.
plist="$APP_PATH/Contents/Info.plist"
feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" 2>/dev/null || true)"
[ "$feed" = "https://github.com/gafiegarcia/scriber/releases/latest/download/appcast.xml" ] \
  || fail "SUFeedURL is '$feed', not the published appcast"
key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
[ "$key" = "qtc3YwvRV9VeGSjKronQmpKQAvRuSgYYCO1avljjlyc=" ] \
  || fail "SUPublicEDKey is '$key', not Scriber's signing key"

# Sparkle's license requires its notice in every copy of the app.
[ -s "$APP_PATH/Contents/Resources/ThirdPartyNotices.txt" ] \
  || fail "ThirdPartyNotices.txt is missing from the bundle"

echo
echo "Developer ID anchor for $TEAM, hardened runtime, audio-input only, no profile."
echo "Sparkle signed by $TEAM without XPC services, no test-appcast option, published feed and key, notices shipped."
