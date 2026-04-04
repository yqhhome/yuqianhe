#!/usr/bin/env bash
# 一键构建 macOS 多版本客户端（Apple Silicon + Intel + Universal），并内置匹配架构的 sing-box。
# 输出：
#   dist/macos/singbox_client-arm64.app
#   dist/macos/singbox_client-x86_64.app
#   dist/macos/singbox_client-universal.app
#   dist/macos/singbox_client-arm64.zip
#   dist/macos/singbox_client-x86_64.zip
#   dist/macos/singbox_client-universal.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER_BIN="${FLUTTER_BIN:-/Users/weiwei/development/flutter/bin/flutter}"
if [[ ! -x "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi
if [[ -z "${FLUTTER_BIN:-}" || ! -x "$FLUTTER_BIN" ]]; then
  echo "未找到 flutter，可设置 FLUTTER_BIN=/path/to/flutter" >&2
  exit 2
fi

export PATH="/opt/homebrew/bin:$PATH"

DIST_DIR="$ROOT/dist/macos"
APP_NAME="${APP_NAME:-宇千鹤}"
WORK_DIR="$ROOT/.build-tools/singbox-macos-dual"
SRC_DIR="$WORK_DIR/sources"
BIN_DIR="$WORK_DIR/bin"
mkdir -p "$DIST_DIR" "$SRC_DIR" "$BIN_DIR"
CACHE_BIN_DIR="${HOME}/.cache/singbox-client"
mkdir -p "$CACHE_BIN_DIR"

resolve_version() {
  if [[ -n "${SINGBOX_VERSION:-}" ]]; then
    echo "${SINGBOX_VERSION#v}"
    return 0
  fi
  python3 - <<'PY'
import json, urllib.request
u = "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
with urllib.request.urlopen(u, timeout=30) as r:
    data = json.load(r)
tag = data.get("tag_name","").strip()
if not tag:
    raise SystemExit("无法解析 sing-box 最新版本号")
print(tag.lstrip("v"))
PY
}

download_singbox() {
  local arch="$1"
  local version="$2"
  local archive="$SRC_DIR/sing-box-${version}-${arch}.tar.gz"
  local unpack="$SRC_DIR/unpack-${arch}"
  local src_bin="$unpack/sing-box-${version}-darwin-${arch}/sing-box"
  local out_bin="$BIN_DIR/sing-box-${arch}"

  local url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-darwin-${arch}.tar.gz"
  if [[ ! -f "$archive" ]]; then
    echo "==> 下载 $url"
    curl -fL --retry 8 --retry-delay 2 --retry-connrefused --retry-all-errors -C - "$url" -o "$archive"
  fi

  rm -rf "$unpack"
  mkdir -p "$unpack"
  if ! tar -xzf "$archive" -C "$unpack"; then
    echo "==> 压缩包损坏，重新下载: $archive"
    rm -f "$archive"
    curl -fL --retry 8 --retry-delay 2 --retry-connrefused --retry-all-errors -C - "$url" -o "$archive"
    rm -rf "$unpack"
    mkdir -p "$unpack"
    tar -xzf "$archive" -C "$unpack"
  fi
  if [[ ! -f "$src_bin" ]]; then
    echo "未找到解压后的 sing-box: $src_bin" >&2
    exit 3
  fi

  cp -f "$src_bin" "$out_bin"
  chmod +x "$out_bin"
  echo "==> 准备完成 $out_bin"
}

verify_arch() {
  local file="$1"
  local arch="$2"
  if ! /usr/bin/lipo "$file" -verify_arch "$arch" >/dev/null 2>&1; then
    /usr/bin/file "$file" >&2 || true
    echo "文件架构校验失败：$file 需包含 $arch" >&2
    exit 4
  fi
}

copy_app() {
  local src_app="$1"
  local dst_app="$2"
  rm -rf "$dst_app"
  cp -R "$src_app" "$dst_app"
}

pick_app_from_dir() {
  local dir="$1"
  local p
  for p in "$dir"/*.app; do
    if [[ -d "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  echo "未找到 .app 产物目录：$dir" >&2
  exit 5
}

zip_app() {
  local app_path="$1"
  local zip_path="$2"
  rm -f "$zip_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
}

VERSION="$(resolve_version)"
echo "==> 使用 sing-box 版本: v$VERSION"

download_singbox "arm64" "$VERSION"
download_singbox "amd64" "$VERSION"

verify_arch "$BIN_DIR/sing-box-arm64" "arm64"
verify_arch "$BIN_DIR/sing-box-amd64" "x86_64"
/usr/bin/lipo -create -output "$BIN_DIR/sing-box-universal" \
  "$BIN_DIR/sing-box-arm64" \
  "$BIN_DIR/sing-box-amd64"
chmod +x "$BIN_DIR/sing-box-universal"
verify_arch "$BIN_DIR/sing-box-universal" "arm64"
verify_arch "$BIN_DIR/sing-box-universal" "x86_64"
cp -f "$BIN_DIR/sing-box-arm64" "$CACHE_BIN_DIR/sing-box-arm64"
cp -f "$BIN_DIR/sing-box-amd64" "$CACHE_BIN_DIR/sing-box-amd64"
cp -f "$BIN_DIR/sing-box-universal" "$CACHE_BIN_DIR/sing-box-universal"
chmod +x "$CACHE_BIN_DIR"/sing-box-*

echo "==> flutter clean"
"$FLUTTER_BIN" clean
echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> 构建 Apple Silicon 包"
SINGBOX_PATH="$BIN_DIR/sing-box-arm64" \
BUNDLE_SINGBOX_REQUIRED=1 \
"$FLUTTER_BIN" build macos --release

ARM_APP_SRC="$(pick_app_from_dir "$ROOT/build/macos/Build/Products/Release")"
ARM_APP_DST="$DIST_DIR/${APP_NAME}-arm64.app"
copy_app "$ARM_APP_SRC" "$ARM_APP_DST"
zip_app "$ARM_APP_DST" "$DIST_DIR/${APP_NAME}-arm64.zip"

echo "==> 构建 Intel 包"
SINGBOX_PATH="$BIN_DIR/sing-box-amd64" \
BUNDLE_SINGBOX_REQUIRED=1 \
"$FLUTTER_BIN" build macos --release --config-only

SINGBOX_PATH="$BIN_DIR/sing-box-amd64" \
BUNDLE_SINGBOX_REQUIRED=1 \
xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath build/macos_intel \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  > "$WORK_DIR/xcodebuild-intel.log" 2>&1

INTEL_APP_SRC="$(pick_app_from_dir "$ROOT/build/macos_intel/Build/Products/Release")"
INTEL_APP_DST="$DIST_DIR/${APP_NAME}-x86_64.app"
copy_app "$INTEL_APP_SRC" "$INTEL_APP_DST"
zip_app "$INTEL_APP_DST" "$DIST_DIR/${APP_NAME}-x86_64.zip"

echo "==> 构建 Universal 包"
SINGBOX_PATH="$BIN_DIR/sing-box-universal" \
BUNDLE_SINGBOX_REQUIRED=1 \
"$FLUTTER_BIN" build macos --release --config-only

SINGBOX_PATH="$BIN_DIR/sing-box-universal" \
BUNDLE_SINGBOX_REQUIRED=1 \
xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath build/macos_universal \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  > "$WORK_DIR/xcodebuild-universal.log" 2>&1

UNIVERSAL_APP_SRC="$(pick_app_from_dir "$ROOT/build/macos_universal/Build/Products/Release")"
UNIVERSAL_APP_DST="$DIST_DIR/${APP_NAME}-universal.app"
copy_app "$UNIVERSAL_APP_SRC" "$UNIVERSAL_APP_DST"
zip_app "$UNIVERSAL_APP_DST" "$DIST_DIR/${APP_NAME}-universal.zip"

echo "==> 架构校验"
verify_arch "$ARM_APP_DST/Contents/Frameworks/objective_c.framework/objective_c" "arm64"
verify_arch "$ARM_APP_DST/Contents/Resources/sing-box" "arm64"
verify_arch "$INTEL_APP_DST/Contents/Frameworks/objective_c.framework/objective_c" "x86_64"
verify_arch "$INTEL_APP_DST/Contents/Resources/sing-box" "x86_64"
verify_arch "$UNIVERSAL_APP_DST/Contents/Frameworks/objective_c.framework/objective_c" "arm64"
verify_arch "$UNIVERSAL_APP_DST/Contents/Frameworks/objective_c.framework/objective_c" "x86_64"
verify_arch "$UNIVERSAL_APP_DST/Contents/Resources/sing-box" "arm64"
verify_arch "$UNIVERSAL_APP_DST/Contents/Resources/sing-box" "x86_64"

echo "==> 完成"
echo "ARM 包:   $ARM_APP_DST"
echo "Intel 包: $INTEL_APP_DST"
echo "Universal 包: $UNIVERSAL_APP_DST"
echo "ARM ZIP:   $DIST_DIR/${APP_NAME}-arm64.zip"
echo "Intel ZIP: $DIST_DIR/${APP_NAME}-x86_64.zip"
echo "Universal ZIP: $DIST_DIR/${APP_NAME}-universal.zip"
