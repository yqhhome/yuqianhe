#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SINGBOX_VERSION:-}" ]]; then
  echo "SINGBOX_VERSION is required" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIBS_DIR="$ROOT_DIR/android/app/libs"
JNI_DIR="$ROOT_DIR/android/app/src/main/jniLibs"
PARTS_DIR="$ROOT_DIR/android/app/libbox_parts"

mkdir -p "$LIBS_DIR" "$JNI_DIR/armeabi-v7a" "$JNI_DIR/arm64-v8a"
rm -f "$JNI_DIR/armeabi-v7a/libsing-box.so" "$JNI_DIR/arm64-v8a/libsing-box.so"

if [[ ! -f "$LIBS_DIR/libbox.aar" ]]; then
  if compgen -G "$PARTS_DIR/libbox.aar.part-*" >/dev/null; then
    cat "$PARTS_DIR"/libbox.aar.part-* > "$LIBS_DIR/libbox.aar"
  else
    echo "vendored libbox.aar is missing: $LIBS_DIR/libbox.aar" >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download_and_install() {
  local arch="$1"
  local abi="$2"
  local filename="sing-box-${SINGBOX_VERSION}-android-${arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${filename}"
  local tarball="$TMP_DIR/$filename"
  local extract_dir="$TMP_DIR/$arch"

  curl -L --fail "$url" -o "$tarball"
  mkdir -p "$extract_dir"
  tar -xzf "$tarball" -C "$extract_dir"
  cp "$extract_dir/sing-box-${SINGBOX_VERSION}-android-${arch}/sing-box" \
    "$JNI_DIR/$abi/libsing-box.so"
  chmod 755 "$JNI_DIR/$abi/libsing-box.so"
}

download_and_install "arm" "armeabi-v7a"
download_and_install "arm64" "arm64-v8a"
