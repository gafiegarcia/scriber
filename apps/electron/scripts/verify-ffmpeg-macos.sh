#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_ROOT="${SCRIBER_FFMPEG_ARTIFACT_DIR:-$ROOT/.ffmpeg}"
REQUESTED="${1:-arm64}"

fail() {
  echo "FFmpeg verification failed: $*" >&2
  exit 1
}

verify_arch() {
  local arch="$1"
  local artifact_arch expected_lipo dir binary file_output linkage config
  if [[ "$arch" != "arm64" ]]; then
    fail "unsupported architecture: $arch"
  fi
  artifact_arch="darwin-arm64"
  expected_lipo="arm64"

  dir="$ARTIFACT_ROOT/$artifact_arch"
  [[ -f "$dir/BUILD_INFO.txt" ]] || fail "$dir/BUILD_INFO.txt is missing"
  [[ -f "$dir/LICENSE.md" ]] || fail "$dir/LICENSE.md is missing"
  [[ -f "$dir/COPYING.LGPLv2.1" ]] || fail "$dir/COPYING.LGPLv2.1 is missing"

  for binary in ffmpeg ffprobe; do
    [[ -x "$dir/$binary" ]] || fail "$dir/$binary is missing or not executable"
    file_output="$(/usr/bin/file "$dir/$binary")"
    [[ "$file_output" == *"Mach-O 64-bit executable"* ]] || fail "$binary is not a 64-bit Mach-O executable"
    [[ "$(/usr/bin/lipo -archs "$dir/$binary")" == "$expected_lipo" ]] || fail "$binary has the wrong CPU architecture"

    config="$(/usr/bin/strings "$dir/$binary")"
    [[ "$config" != *"--enable-gpl"* ]] || fail "$binary enables GPL components"
    [[ "$config" != *"--enable-nonfree"* ]] || fail "$binary enables nonfree components"
    [[ "$config" != *"--enable-version3"* ]] || fail "$binary enables version-3-only components"

    linkage="$(/usr/bin/otool -L "$dir/$binary")"
    [[ "$linkage" != *"/opt/homebrew"* ]] || fail "$binary links to Homebrew"
    [[ "$linkage" != *"/usr/local"* ]] || fail "$binary links to /usr/local"
    [[ "$linkage" != *"@rpath"* ]] || fail "$binary has an unresolved @rpath dependency"
    [[ "$linkage" != *"@loader_path"* ]] || fail "$binary has an unresolved @loader_path dependency"
  done

  if [[ "$(uname -m)" == "arm64" ]]; then
    local license_output
    license_output="$($dir/ffmpeg -hide_banner -L 2>&1)"
    [[ "$license_output" == *"GNU Lesser General Public"* ]] || fail "ffmpeg does not report LGPL terms"
    [[ "$license_output" != *"not legally redistributable"* ]] || fail "ffmpeg reports an unredistributable build"
    "$dir/ffmpeg" -hide_banner -encoders 2>&1 | /usr/bin/grep -Eq ' A.* aac ' || fail "native AAC encoder is missing"
    "$dir/ffmpeg" -hide_banner -muxers 2>&1 | /usr/bin/grep -Eq ' E .* (mov|mp4)' || fail "MOV/MP4 muxer is missing"
    node "$ROOT/scripts/verify-ffmpeg-functional.js" "$dir/ffmpeg" "$dir/ffprobe"
    echo "Functional checks passed for $artifact_arch."
  else
    fail "functional verification requires Apple silicon"
  fi
}

case "$REQUESTED" in
  arm64)
    verify_arch arm64
    ;;
  *)
    fail "usage: $0 [arm64]"
    ;;
esac

echo "FFmpeg macOS artifact verification passed."
