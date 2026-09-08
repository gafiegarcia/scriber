#!/bin/bash
# The routine pass. Run it after any change to Swift, and before any commit.
#
# The repo-local module cache and --disable-sandbox are what make the package
# tests work in managed sandboxes as well as an ordinary shell.
#
# Neither parse invocation typechecks, so a Debug xcodebuild is still the only
# real gate on `#if DEBUG` code.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
MODULE_CACHE="$REPO_ROOT/.build/module-cache"
mkdir -p "$MODULE_CACHE"

echo "==> Parsing"
swiftc -frontend -parse \
  "$REPO_ROOT"/Scriber/*.swift \
  "$REPO_ROOT"/ScriberCore/*.swift \
  "$REPO_ROOT"/ScriberCoreTests/*.swift

# Again with DEBUG defined. Without it, `#if DEBUG` regions are lexed but never
# parsed, so the pass above says nothing about AppLaunchConfiguration's flags or
# UITestingHistoryFixture.
echo "==> Parsing with DEBUG"
swiftc -frontend -parse -D DEBUG \
  "$REPO_ROOT"/Scriber/*.swift \
  "$REPO_ROOT"/ScriberCore/*.swift

echo "==> Typechecking ScriberCore"
swiftc -module-cache-path "$MODULE_CACHE" -typecheck \
  "$REPO_ROOT"/ScriberCore/*.swift

echo "==> Package tests"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
swift test --disable-sandbox --package-path "$REPO_ROOT"

echo "==> Info.plist"
plutil -lint "$REPO_ROOT/Scriber/Info.plist"

# Chained rather than left to be remembered: renaming a Swift symbol a document
# cites rots the citation, and nothing above would notice. It is pure Python
# with no build, so it costs nothing here.
echo "==> Documents"
"$REPO_ROOT/scripts/check-docs.sh"

echo
# Says what it did not do, because "OK" alone was read as "the app compiles".
# Nothing above typechecks the app target — the parse stages accept a wrong
# SwiftUI modifier overload, which has shipped a broken build before.
echo "Routine pass OK — app target parsed, not typechecked. Run ./scripts/smoke.sh to know it compiles."
