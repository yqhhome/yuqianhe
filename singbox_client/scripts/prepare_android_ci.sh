#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SINGBOX_VERSION:-}" ]]; then
  echo "SINGBOX_VERSION is required" >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  echo "ANDROID_NDK_HOME is required" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${RUNNER_TEMP:-$ROOT_DIR/.ci-tmp}/sing-box-upstream"
LIBS_DIR="$ROOT_DIR/android/app/libs"
JNI_DIR="$ROOT_DIR/android/app/src/main/jniLibs"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$LIBS_DIR" "$JNI_DIR/armeabi-v7a" "$JNI_DIR/arm64-v8a"
rm -f "$LIBS_DIR/libbox.aar"
rm -f "$JNI_DIR/armeabi-v7a/libsing-box.so" "$JNI_DIR/arm64-v8a/libsing-box.so"

git clone --depth 1 --branch "v$SINGBOX_VERSION" https://github.com/SagerNet/sing-box.git "$WORK_DIR"

pushd "$WORK_DIR" >/dev/null
make lib_install
export PATH="$PATH:$(go env GOPATH)/bin"
make lib_android
cp libbox.aar "$LIBS_DIR/libbox.aar"
popd >/dev/null

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
