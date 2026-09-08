#!/bin/bash
# The launch smoke check. Run it after any change to startup, the pill, or an
# NSViewRepresentable — it has caught a main-thread wedge no test did.
#
# Builds Debug, launches that build with activation, Dock presence and the menu
# bar item all suppressed, and kills it again. The before_pid guard and the
# absolute APP_PATH are what keep the final kill off the user's installed copy; they
# are the reason this is a script rather than a block to paste.
#
# What it cannot show: anything that needs a window to be presented a second
# time. Under --ui-testing-no-activate a closed window never comes back, while
# the window-lifecycle log still reports "ordering front" — so onAppear,
# didBecomeKey, and Settings tab routing all go quiet and read as broken. Take
# reopening behaviour to an activating launch or to the user.
#
# Pass --login to add --simulate-login-launch, which makes the app treat its
# launch as one macOS made at login. Run both: the app must come up with no
# window and `loginItem=true` with the flag, and must show the window without
# it. Either passing alone proves nothing.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_PATH="$REPO_ROOT/.build/xcode-debug/Build/Products/Debug/Scriber.app"

EXTRA_ARGS=()
if [ "${1:-}" = "--login" ]; then
  EXTRA_ARGS+=(--simulate-login-launch)
fi

echo "==> Building Debug"
xcodebuild -project "$REPO_ROOT/Scriber.xcodeproj" \
  -scheme Scriber -configuration Debug \
  -derivedDataPath "$REPO_ROOT/.build/xcode-debug" build \
  >/dev/null

if [ ! -d "$APP_PATH" ]; then
  echo "REFUSING: the Debug build produced no app at $APP_PATH" >&2
  exit 1
fi

before_pid="$(pgrep -n -x Scriber || true)"

echo "==> Launching the test build"
open -g -j -n -a "$APP_PATH" --args \
  --ui-testing \
  --ui-testing-no-activate \
  --ui-testing-missing-permissions \
  "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
sleep 6
pid="$(pgrep -n -x Scriber || true)"

if [ -z "$pid" ] || [ "$pid" = "$before_pid" ]; then
  echo "REFUSING: the test build never launched — not killing anything" >&2
  exit 1
fi

# A process that stays at high CPU or never idles is an app failure worth
# sampling before blaming the harness.
ps -p "$pid" -o pid,%cpu,command
kill "$pid"

echo
echo "Launched, rendered and exited. Read the log with:"
# By absolute path, because `log` can be shadowed by a shell builtin or function
# — it then fails with "too many arguments", which reads exactly like a query
# that ran and found nothing.
echo "  /usr/bin/log show --last 5m --predicate 'subsystem == \"com.gafiegarcia.scriber\"' --style compact"
