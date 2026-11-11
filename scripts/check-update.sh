#!/bin/bash
# The update check. Run it after any change to SoftwareUpdater.swift, to the
# Sparkle version, or to how a release is signed or packaged.
#
# Builds an old and a new Debug build, puts the new one in a disk image, writes
# an appcast for it with Sparkle's own generate_appcast — signed with the real
# key from the login Keychain — and serves that on 127.0.0.1. Nothing public is
# involved. Then:
#
#   A. The old build checks, downloads and stages the update, and is killed
#      with it staged, the way a crash or a force quit ends it.
#   B. A fresh old build is launched with that staged update still on record.
#      It must install it by itself and be relaunched by Sparkle as the new
#      build, with no window or button involved.
#   C. The relaunched build must record that it follows an update, and must no
#      longer hold one staged.
#
# Both builds carry the bundle identifier com.gafiegarcia.scriber.sparkle-test,
# so Sparkle's preferences, cache and installer job never touch the installed
# app's. Both carry their launch options in Info.plist, under
# ScriberTestLaunchArguments, because Sparkle relaunches an updated app with no
# arguments: without them the relaunched build would come up as an ordinary
# Debug build reading the real history, preferences and key. With them it comes
# up under --ui-testing like the build it replaced.
#
# What it cannot show: an install at a screen lock, which would lock the user's
# Mac, and what the status line looks like. MANUAL_CHECKS.md holds those.
#
# The first run raises a Keychain prompt for generate_appcast to use the
# signing key. Allow it; Always Allow saves the next release the same prompt.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORK="$REPO_ROOT/.build/update-test"
DERIVED="$WORK/derived"
FEED="$WORK/feed"
INSTALL_DIR="$WORK/installed"
APP="$INSTALL_DIR/Scriber.app"
EXECUTABLE="$APP/Contents/MacOS/Scriber"
TEST_ID="com.gafiegarcia.scriber.sparkle-test"
SUITE="com.gafiegarcia.scriber.update-test"
PORT=8977
APPCAST="http://127.0.0.1:$PORT/appcast.xml"
OLD_VERSION="0.99.0"; OLD_BUILD="99000"
NEW_VERSION="0.99.1"; NEW_BUILD="99001"

fail() { echo "FAILED: $1" >&2; exit 1; }
build_of() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist"; }
# By the executable's full path, so neither the installed Scriber nor any other
# test build is ever counted.
test_build_pid() { pgrep -n -f "^$EXECUTABLE" || true; }

server_pid=""
cleanup() {
  pkill -f "^$EXECUTABLE" 2>/dev/null || true
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

# Do not: reuse a previous run's folders. A stale copy of the new build left in
# place makes phase A pass without anything having installed.
[ -d "$WORK" ] && trash "$WORK"
mkdir -p "$DERIVED" "$FEED" "$INSTALL_DIR"

IDENTITY="$(xcodebuild -project "$REPO_ROOT/Scriber.xcodeproj" -scheme Scriber -configuration Debug -showBuildSettings 2>/dev/null \
  | awk '$1 == "CODE_SIGN_IDENTITY" {print $3; exit}')"
[ -n "$IDENTITY" ] || fail "no Debug signing identity; Sparkle refuses an update it cannot match by signature"

# Builds one version, gives it the test identity and launch options, and
# re-signs it. Info.plist names the bundle identifier literally, so it is
# patched after the build rather than overridden as a build setting.
build_variant() {
  local version="$1" build="$2" out="$3"
  echo "==> Building $version ($build)"
  xcodebuild -project "$REPO_ROOT/Scriber.xcodeproj" -scheme Scriber -configuration Debug \
    -derivedDataPath "$DERIVED" MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    build >"$WORK/build-$build.log" 2>&1 || fail "the $version build failed; see $WORK/build-$build.log"
  mkdir -p "$out"
  ditto "$DERIVED/Build/Products/Debug/Scriber.app" "$out/Scriber.app"
  local plist="$out/Scriber.app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $TEST_ID" "$plist"
  /usr/libexec/PlistBuddy -c "Add :ScriberTestLaunchArguments array" "$plist"
  local index=0
  for argument in --ui-testing --ui-testing-no-activate --debug-appcast "$APPCAST"; do
    /usr/libexec/PlistBuddy -c "Add :ScriberTestLaunchArguments:$index string $argument" "$plist"
    index=$((index + 1))
  done
  codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements,flags "$out/Scriber.app" 2>/dev/null
  codesign --verify --strict "$out/Scriber.app" || fail "the $version build does not verify after re-signing"
}

build_variant "$OLD_VERSION" "$OLD_BUILD" "$WORK/old"
build_variant "$NEW_VERSION" "$NEW_BUILD" "$WORK/new"

echo "==> Writing the appcast"
# A disk image, as a release ships, so Sparkle's own disk image path is the one
# exercised.
hdiutil create -quiet -volname "Scriber $NEW_VERSION" -srcfolder "$WORK/new" -format UDZO \
  "$FEED/Scriber-$NEW_VERSION.dmg"
"$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" --account scriber \
  --download-url-prefix "http://127.0.0.1:$PORT/" "$FEED" >"$WORK/appcast.log" 2>&1 \
  || fail "generate_appcast failed; see $WORK/appcast.log"
grep -q "sparkle:edSignature" "$FEED/appcast.xml" || fail "the appcast carries no EdDSA signature"

# Sparkle refuses a feed or a download that is not http or https, so a file URL
# will not do.
# Do not: use `python3 -m http.server`. Its server looks the host name up as it
# binds, which asks macOS for local network access — a prompt that blocks the
# server until answered and grants Python the whole network if allowed. Bound
# to loopback with no lookup, nothing asks.
python3 -I - "$FEED" "$PORT" >"$WORK/server.log" 2>&1 <<'PY' &
import functools, http.server, socketserver, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
socketserver.TCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("127.0.0.1", int(sys.argv[2])), handler) as server:
    server.serve_forever()
PY
server_pid=$!
sleep 1
curl -sf -m 5 "$APPCAST" >/dev/null || fail "the appcast is not being served"

# Fresh preferences for both domains. Sparkle is told it has launched before
# and last checked long ago, so its first scheduled check runs at launch.
defaults delete "$TEST_ID" >/dev/null 2>&1 || true
defaults delete "$SUITE" >/dev/null 2>&1 || true
defaults write "$TEST_ID" SUHasLaunchedBefore -bool YES
defaults write "$TEST_ID" SULastCheckTime -date "2020-01-01 00:00:00 +0000"

# Prints the pid of the old build it launched.
launch_old() {
  # Do not: ditto onto a bundle already there. It merges, and leaves a new
  # build's files inside what claims to be the old one.
  rm -rf "${APP:?}"
  ditto "$WORK/old/Scriber.app" "$APP"
  [ "$(build_of "$APP")" = "$OLD_BUILD" ] || fail "could not put the old build in place"
  [ -z "$(test_build_pid)" ] || fail "a test build is already running"
  open -g -n -a "$APP"
  # Measured: polled, not slept. With an update staged, the old build installed
  # and Sparkle had relaunched the new one 1.3 s after launch, so a fixed wait
  # finds the new build and takes it for the old.
  local pid=""
  for _ in $(seq 100); do
    pid="$(test_build_pid)"
    [ -n "$pid" ] && break
    sleep 0.1
  done
  [ -n "$pid" ] || fail "the old build never launched"
  ps -p "$pid" -o command= | grep -q -- "--debug-appcast" \
    && fail "the old build's options arrived on the command line, so Info.plist's went untested"
  echo "$pid"
}

wait_for_build() {
  local want="$1" seconds="$2"
  for _ in $(seq "$seconds"); do
    [ "$(build_of "$APP" 2>/dev/null || true)" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

echo
echo "==> A. Stage the update, then kill the old build"
old_pid="$(launch_old)"
for _ in $(seq 90); do
  defaults read "$SUITE" stagedUpdate >/dev/null 2>&1 && break
  sleep 1
done
defaults read "$SUITE" stagedUpdate >/dev/null 2>&1 || fail "the old build never staged the update"
echo "    staged; killing pid $old_pid"
kill -9 "$old_pid"
if wait_for_build "$NEW_BUILD" 30; then
  echo "    Sparkle's installer installed it when the app died"
else
  echo "    nothing installed on termination; phase B covers the next launch"
fi
sleep 2
pkill -f "^$EXECUTABLE" 2>/dev/null || true

echo
echo "==> B. Launch an old build with the update still staged"
old_pid="$(launch_old)"
echo "    old build is pid $old_pid"
for _ in $(seq 120); do
  kill -0 "$old_pid" 2>/dev/null || break
  sleep 1
done
kill -0 "$old_pid" 2>/dev/null && fail "the old build was still running after two minutes; it never installed"
wait_for_build "$NEW_BUILD" 30 || fail "the old build quit but the new build never arrived"
echo "    installed by itself at launch: build $(build_of "$APP")"
codesign --verify --strict "$APP" || fail "the installed build does not verify"
new_pid=""
for _ in $(seq 30); do
  new_pid="$(test_build_pid)"
  [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && break
  new_pid=""
  sleep 1
done
[ -n "$new_pid" ] || fail "Sparkle never relaunched the new build"
echo "    Sparkle relaunched it as pid $new_pid"

echo
echo "==> C. Read what the relaunched build recorded"
sleep 3
defaults read "$SUITE" recentUpdate >/dev/null 2>&1 || fail "the new build did not record that it follows an update"
defaults read "$SUITE" stagedUpdate >/dev/null 2>&1 && fail "the new build still has the update recorded as staged"
[ "$(defaults read "$SUITE" lastLaunchedBuild 2>/dev/null || true)" = "$NEW_BUILD" ] \
  || fail "the running build did not record itself as $NEW_BUILD"
# An update arrives unannounced: the relaunch comes up as a login launch would,
# with no window. Read from the build's own launch log, which states the
# decision, and from what it actually ordered on screen.
launch_log="$(/usr/bin/log show --last 5m --style compact --predicate \
  "subsystem == \"com.gafiegarcia.scriber\" AND processIdentifier == $new_pid AND category == \"window-lifecycle\"")"
grep -q "afterUpdate=true startsInBackground=true" <<<"$launch_log" \
  || fail "the relaunched build did not recognise it was installed by an update, so it may show a window"
grep -q "showWindow: ordering front" <<<"$launch_log" \
  && fail "the relaunched build put a window on screen"
echo "    came back with no window"

echo
echo "Staged, killed, installed at the next launch, relaunched by Sparkle as $NEW_VERSION ($NEW_BUILD) with no window."
if [ "${KEEP_RUNNING:-}" = "1" ]; then
  # Left up for its Settings to be read through the accessibility tree.
  trap - EXIT
  kill "$server_pid" 2>/dev/null || true
  echo "KEEP_RUNNING=1: the new build is still running. kill $new_pid when done."
fi
