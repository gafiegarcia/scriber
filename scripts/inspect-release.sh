#!/bin/bash
# Inspects the exact Release bundle that will be installed or shipped. Run it
# after a Release build and before replacing /Applications or notarizing.
#
# Four things must hold, and each has caught a real mistake. This script asserts
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

echo
echo "Developer ID anchor for $TEAM, hardened runtime, audio-input only, no profile."
