#!/bin/bash
# Checks the published Homebrew cask, after a release is live. Nothing else
# checks the tap's Casks/scriber.rb: it lives in another repository, is not
# compiled, is not tested, and does not run until someone types the install
# command — so a wrong sha256, a version that builds a URL to nothing, a mis-set
# depends_on, or an artifact name that does not match what is inside the disk
# image all fail silently until a stranger meets them.
#
# --appdir is what makes this runnable here. Installing the ordinary way would
# put the release over the development build in /Applications and hand Homebrew
# that app to manage; sent to a throwaway directory, the whole real path still
# runs — fetch, checksum, architecture and OS gates, mount, artifact placement —
# against the copy nobody is using.
#
# This checks the recipe, not the app. The cask fetches the same release asset
# already tested by hand and verifies it against the checksum published with it.
#
# The uninstall quits the running Scriber, wherever it was installed from: the
# cask carries `uninstall quit: "com.gafiegarcia.scriber"`, which acts on the
# bundle identifier and not on the copy being removed. Expect it, and reopen
# afterwards. On a beta macOS, Homebrew warns that it does not support the OS —
# that is Homebrew talking about the OS, not about this cask.
set -euo pipefail

EXPECTED_VERSION="${1:-}"
if [ -z "$EXPECTED_VERSION" ]; then
  echo "usage: $0 <version just published, e.g. 0.9.4>" >&2
  exit 1
fi

fail() { echo "FAILED: $1" >&2; exit 1; }

APPDIR="$(mktemp -d)"
cleanup() {
  brew uninstall --cask scriber >/dev/null 2>&1 || true
  rm -rf "$APPDIR"
}
trap cleanup EXIT

echo "==> Installing the published cask into $APPDIR"
brew install --cask --appdir="$APPDIR" gafiegarcia/scriber/scriber
APP="$APPDIR/Scriber.app"
[ -d "$APP" ] || fail "the cask placed no Scriber.app in $APPDIR"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "    version $version (build $build)"
[ "$version" = "$EXPECTED_VERSION" ] \
  || fail "the cask installed $version, not the $EXPECTED_VERSION just published"

codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$APP" >/dev/null || fail "the stapled ticket does not validate"
spctl -a -vvv --type open --context context:primary-signature "$APP" 2>&1 | tee /dev/stderr \
  | grep -q "source=Notarized Developer ID" \
  || fail "Gatekeeper does not report a notarized Developer ID"

echo
echo "Cask installs $version, signature verifies, ticket validates, Gatekeeper accepts."
echo "Uninstalling — this quits any running Scriber."
