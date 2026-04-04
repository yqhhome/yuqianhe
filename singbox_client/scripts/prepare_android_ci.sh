#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SINGBOX_VERSION:-}" ]]; then
  echo "SINGBOX_VERSION is required" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIBS_DIR="$ROOT_DIR/android/app/libs"
JNI_DIR="$ROOT_DIR/android/app/src/main/jniLibs"
WORK_DIR="$ROOT_DIR/.build-tools/android-deps"
CACHE_DIR="$WORK_DIR/cache/v${SINGBOX_VERSION}"
ANDROID_ABIS="${ANDROID_ABIS:-armeabi-v7a,arm64-v8a}"

mkdir -p "$LIBS_DIR" "$JNI_DIR" "$CACHE_DIR"

download_file() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" && -s "$out" ]]; then
    return 0
  fi
  echo "==> 下载 $url"
  curl -fL --retry 8 --retry-delay 2 --retry-connrefused --retry-all-errors \
    -o "$out" "$url"
}

ensure_libbox() {
  local target="$LIBS_DIR/libbox.aar"
  if [[ -s "$target" ]]; then
    echo "==> 使用现有 libbox.aar"
    return 0
  fi
  if [[ -n "${LIBBOX_AAR_PATH:-}" && -s "${LIBBOX_AAR_PATH}" ]]; then
    cp -f "${LIBBOX_AAR_PATH}" "$target"
    echo "==> 从 LIBBOX_AAR_PATH 复制 libbox.aar"
    return 0
  fi
  if [[ -n "${LIBBOX_AAR_URL:-}" ]]; then
    local cached="$CACHE_DIR/libbox.aar"
    download_file "${LIBBOX_AAR_URL}" "$cached"
    cp -f "$cached" "$target"
    echo "==> 从 LIBBOX_AAR_URL 下载 libbox.aar"
    return 0
  fi
  echo "missing libbox.aar: set LIBBOX_AAR_URL or LIBBOX_AAR_PATH, or provide $target" >&2
  exit 1
}

abi_to_arch() {
  case "$1" in
    armeabi-v7a) echo "arm" ;;
    arm64-v8a) echo "arm64" ;;
    x86) echo "386" ;;
    x86_64) echo "amd64" ;;
    *)
      echo "unsupported abi: $1" >&2
      exit 2
      ;;
  esac
}

download_and_install() {
  local abi="$1"
  local arch
  arch="$(abi_to_arch "$abi")"

  local target_dir="$JNI_DIR/$abi"
  local target="$target_dir/libsing-box.so"
  mkdir -p "$target_dir"
  if [[ -s "$target" ]]; then
    chmod 755 "$target"
    echo "==> 使用现有 $abi/libsing-box.so"
    return 0
  fi

  local filename="sing-box-${SINGBOX_VERSION}-android-${arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${filename}"
  local tarball="$CACHE_DIR/$filename"
  local extract_dir="$CACHE_DIR/unpack-$arch"

  download_file "$url" "$tarball"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xzf "$tarball" -C "$extract_dir"
  cp "$extract_dir/sing-box-${SINGBOX_VERSION}-android-${arch}/sing-box" "$target"
  chmod 755 "$target"
  echo "==> 已准备 $abi/libsing-box.so"
}

ensure_libbox

IFS=',' read -r -a abi_list <<< "$ANDROID_ABIS"
for abi in "${abi_list[@]}"; do
  download_and_install "$abi"
done

echo "==> Android 依赖准备完成"
ls -lh "$LIBS_DIR/libbox.aar"
for abi in "${abi_list[@]}"; do
  ls -lh "$JNI_DIR/$abi/libsing-box.so"
done
