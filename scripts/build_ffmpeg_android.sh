#!/usr/bin/env bash
set -euo pipefail

FFMPEG_VERSION="7.1.5"
FFMPEG_KEY_FINGERPRINT="FCF986EA15E6E293A5644F10B4322F04D67658D8"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_ROOT="$PROJECT_ROOT/engine/ffmpeg-android-lgpl"
BUILD_ROOT="${FFMPEG_BUILD_ROOT:-$OUTPUT_ROOT/.build}"
NDK_ROOT="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

if [[ -z "$NDK_ROOT" || ! -x "$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]]; then
  echo "ANDROID_NDK_HOME must point to an installed Linux Android NDK." >&2
  exit 2
fi

for tool in curl gpg make sha1sum tar xz; do
  command -v "$tool" >/dev/null || { echo "Required build tool missing: $tool" >&2; exit 2; }
done

if [[ $# -eq 0 ]]; then
  set -- arm64-v8a x86_64
fi

mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT/lib"
ARCHIVE="$BUILD_ROOT/ffmpeg-$FFMPEG_VERSION.tar.xz"
SIGNATURE="$ARCHIVE.asc"
KEY="$BUILD_ROOT/ffmpeg-devel.asc"

if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "$ARCHIVE"
fi
if [[ ! -f "$SIGNATURE" ]]; then
  curl --fail --location --retry 3 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" -o "$SIGNATURE"
fi
curl --fail --location --retry 3 https://ffmpeg.org/ffmpeg-devel.asc -o "$KEY"
sha1sum "$ARCHIVE" > "$ARCHIVE.sha1"

export GNUPGHOME="$BUILD_ROOT/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --import "$KEY" >/dev/null 2>&1
if ! gpg --batch --with-colons --fingerprint --list-keys | grep -Fq "$FFMPEG_KEY_FINGERPRINT"; then
  echo "FFmpeg signing key fingerprint did not match the official release key." >&2
  exit 2
fi
if ! gpg --batch --status-fd 1 --verify "$SIGNATURE" "$ARCHIVE" > "$BUILD_ROOT/signature-check.txt" 2>&1; then
  cat "$BUILD_ROOT/signature-check.txt" >&2
  exit 2
fi
grep -Fq "[GNUPG:] VALIDSIG $FFMPEG_KEY_FINGERPRINT " "$BUILD_ROOT/signature-check.txt" || {
  echo "FFmpeg release signature was not made by the expected official key." >&2
  exit 2
}

SOURCE_DIR="$BUILD_ROOT/ffmpeg-$FFMPEG_VERSION"
if [[ ! -f "$SOURCE_DIR/configure" ]]; then
  mkdir -p "$SOURCE_DIR"
  tar -xJf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"
fi

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
SYSROOT="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

for ABI in "$@"; do
  case "$ABI" in
    arm64-v8a)
      ARCH=aarch64
      TRIPLE=aarch64-linux-android
      LIB_DIR=arm64
      ;;
    x86_64)
      ARCH=x86_64
      TRIPLE=x86_64-linux-android
      LIB_DIR=amd64
      ;;
    *)
      echo "Unsupported ABI '$ABI'. Supported values: arm64-v8a, x86_64." >&2
      exit 2
      ;;
  esac

  PREFIX="$BUILD_ROOT/install-$ABI"
  mkdir -p "$PREFIX"
  make -C "$SOURCE_DIR" distclean >/dev/null 2>&1 || true

  (
    cd "$SOURCE_DIR"
    ./configure \
      --prefix="$PREFIX" \
      --target-os=android \
      --arch="$ARCH" \
      --cross-prefix="$TOOLCHAIN/$TRIPLE-" \
      --cc="$TOOLCHAIN/${TRIPLE}24-clang" \
      --cxx="$TOOLCHAIN/${TRIPLE}24-clang++" \
      --ar="$TOOLCHAIN/llvm-ar" \
      --nm="$TOOLCHAIN/llvm-nm" \
      --ranlib="$TOOLCHAIN/llvm-ranlib" \
      --strip="$TOOLCHAIN/llvm-strip" \
      --sysroot="$SYSROOT" \
      --enable-cross-compile \
      --enable-shared \
      --disable-static \
      --disable-programs \
      --disable-doc \
      --disable-debug \
      --disable-autodetect \
      --disable-gpl \
      --disable-nonfree \
      --disable-version3 \
      --enable-pic \
      --enable-pthreads \
      --enable-mediacodec \
      --extra-cflags="-fPIC -D__ANDROID_API__=24" \
      --extra-ldflags="-Wl,-z,max-page-size=16384"
    make -j"${FFMPEG_JOBS:-$(nproc)}"
    make install
  )

  DEST_LIB="$OUTPUT_ROOT/lib/$LIB_DIR"
  mkdir -p "$DEST_LIB" "$OUTPUT_ROOT/include"
  for LIB in avcodec avdevice avfilter avformat avutil swresample swscale; do
    cp -L "$PREFIX/lib/lib$LIB.so" "$DEST_LIB/lib$LIB.so"
  done
  if [[ ! -f "$OUTPUT_ROOT/include/libavutil/avutil.h" ]]; then
    cp -a "$PREFIX/include/." "$OUTPUT_ROOT/include/"
  fi

  printf 'Built FFmpeg %s (LGPL 2.1+, no GPL/nonfree, MediaCodec enabled) for %s\n' \
    "$FFMPEG_VERSION" "$ABI"
done

cp "$SOURCE_DIR/COPYING.LGPLv2.1" "$OUTPUT_ROOT/COPYING.LGPLv2.1"
printf 'FFmpeg %s; official source archive signature verified; key %s; configure: shared LGPL, --disable-gpl --disable-nonfree --disable-version3 --enable-mediacodec; NDK API 24; 16 KB ELF page alignment.\n' \
  "$FFMPEG_VERSION" "$FFMPEG_KEY_FINGERPRINT" > "$OUTPUT_ROOT/BUILDINFO.txt"
echo "FFmpeg Android libraries staged under $OUTPUT_ROOT."
