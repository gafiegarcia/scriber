#!/bin/bash

set -euo pipefail

FFMPEG_VERSION="8.1.2"
FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
MACOS_MIN="12.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${SCRIBER_FFMPEG_BUILD_DIR:-$ROOT/.ffmpeg-build}"
ARTIFACT_ROOT="${SCRIBER_FFMPEG_ARTIFACT_DIR:-$ROOT/.ffmpeg}"
TARBALL="$BUILD_ROOT/ffmpeg-${FFMPEG_VERSION}.tar.xz"
SOURCE_DIR="$BUILD_ROOT/ffmpeg-${FFMPEG_VERSION}"
REQUESTED="${1:-arm64}"

# Prevent locally-installed libraries and compiler flags from leaking into a
# release artifact. The build intentionally uses only FFmpeg code + macOS SDK.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
unset CPATH CPLUS_INCLUDE_PATH C_INCLUDE_PATH LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
unset CFLAGS CPPFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS FFLAGS FCFLAGS LDFLAGS
unset SDKROOT MACOSX_DEPLOYMENT_TARGET DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH

fail() {
  echo "FFmpeg build failed: $*" >&2
  exit 1
}

prepare_source() {
  mkdir -p "$BUILD_ROOT" "$ARTIFACT_ROOT"
  if [[ ! -f "$TARBALL" ]]; then
    echo "Downloading FFmpeg $FFMPEG_VERSION from ffmpeg.org..."
    /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 "$FFMPEG_URL" --output "$TARBALL"
  fi

  local actual_sha
  actual_sha="$(/usr/bin/shasum -a 256 "$TARBALL" | /usr/bin/awk '{print $1}')"
  [[ "$actual_sha" == "$FFMPEG_SHA256" ]] || fail "source SHA-256 mismatch (got $actual_sha)"

  if [[ ! -d "$SOURCE_DIR" ]]; then
    /usr/bin/tar -xf "$TARBALL" -C "$BUILD_ROOT"
  fi
  [[ -x "$SOURCE_DIR/configure" ]] || fail "source extraction is incomplete"
}

build_arch() {
  local arch="$1"
  local artifact_arch build_dir artifact_dir sdk jobs
  local -a arch_flags configure_flags

  if [[ "$arch" != "arm64" ]]; then
    fail "unsupported architecture: $arch"
  fi
  artifact_arch="darwin-arm64"
  arch_flags=("--arch=arm64")

  build_dir="$BUILD_ROOT/build-$arch"
  artifact_dir="$ARTIFACT_ROOT/$artifact_arch"
  sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
  jobs="$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
  mkdir -p "$build_dir" "$artifact_dir"

  configure_flags=(
    "--prefix=$artifact_dir"
    "--target-os=darwin"
    "--cc=/usr/bin/clang"
    "--host-cc=/usr/bin/clang"
    "--sysroot=$sdk"
    "--extra-cflags=-arch $arch -mmacosx-version-min=$MACOS_MIN"
    "--extra-ldflags=-arch $arch -mmacosx-version-min=$MACOS_MIN"
    "--pkg-config=/usr/bin/false"
    "--disable-autodetect"
    "--disable-gpl"
    "--disable-nonfree"
    "--disable-version3"
    "--disable-iconv"
    "--disable-network"
    "--disable-avdevice"
    "--disable-devices"
    "--disable-hwaccels"
    "--disable-doc"
    "--disable-debug"
    "--disable-stripping"
    "--disable-programs"
    "--disable-shared"
    "--enable-static"
    "--enable-ffmpeg"
    "--enable-ffprobe"
  )

  echo "Configuring FFmpeg $FFMPEG_VERSION for $artifact_arch..."
  (
    cd "$build_dir"
    "$SOURCE_DIR/configure" "${arch_flags[@]}" "${configure_flags[@]}"
    /usr/bin/make -j "$jobs" ffmpeg ffprobe
  )

  /bin/cp "$build_dir/ffmpeg" "$artifact_dir/ffmpeg"
  /bin/cp "$build_dir/ffprobe" "$artifact_dir/ffprobe"
  /usr/bin/xcrun strip -x "$artifact_dir/ffmpeg" "$artifact_dir/ffprobe"
  /bin/chmod 755 "$artifact_dir/ffmpeg" "$artifact_dir/ffprobe"
  /bin/cp "$SOURCE_DIR/LICENSE.md" "$artifact_dir/LICENSE.md"
  /bin/cp "$SOURCE_DIR/COPYING.LGPLv2.1" "$artifact_dir/COPYING.LGPLv2.1"
  /bin/cp "$build_dir/config.h" "$artifact_dir/config.h"
  /bin/cp "$build_dir/ffbuild/config.mak" "$artifact_dir/config.mak"

  {
    echo "FFmpeg version: $FFMPEG_VERSION"
    echo "Official source: $FFMPEG_URL"
    echo "Source SHA-256: $FFMPEG_SHA256"
    echo "Target: $artifact_arch"
    echo "Minimum macOS: $MACOS_MIN"
    echo "SDK: $sdk"
    echo "Compiler: $(/usr/bin/clang --version | /usr/bin/head -n 1)"
    echo "Source changes: none"
    echo "Configure flags:"
    printf '  %q' "$SOURCE_DIR/configure" "${arch_flags[@]}" "${configure_flags[@]}"
    echo
  } > "$artifact_dir/BUILD_INFO.txt"

  "$ROOT/scripts/verify-ffmpeg-macos.sh" "$arch"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this script must run on macOS"
[[ "$(uname -m)" == "arm64" ]] || fail "Scriber desktop FFmpeg builds require Apple silicon"
prepare_source

case "$REQUESTED" in
  arm64)
    build_arch arm64
    ;;
  *)
    fail "usage: $0 [arm64]"
    ;;
esac

echo "FFmpeg macOS artifacts are ready under $ARTIFACT_ROOT."
