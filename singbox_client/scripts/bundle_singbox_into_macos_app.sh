#!/usr/bin/env bash
# 将本机已安装的 sing-box 复制到 .app/Contents/Resources/sing-box，供 GUI 双击运行时找到（不依赖 PATH）。
# 查找顺序：$SINGBOX_PATH → Homebrew 常见路径 → PATH 中的 sing-box。
# 若设置 BUNDLE_SINGBOX_REQUIRED=1（默认），未找到或架构不兼容会让构建失败，避免发出不可用安装包。
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/singbox_client.app" >&2
  exit 0
fi

RES="${APP}/Contents/Resources"
DST="${RES}/sing-box"
mkdir -p "$RES"
REQUIRED="${BUNDLE_SINGBOX_REQUIRED:-1}"
TARGET_ARCHS="${ARCHS:-}"

find_binary() {
  local p
  local root=""
  if [[ -n "${SRCROOT:-}" ]]; then
    root="$(cd "${SRCROOT}/.." && pwd)"
  fi

  if [[ -n "$root" ]]; then
    for p in \
      "$root/build/singbox-macos-dual/bin/sing-box-universal" \
      "$root/build/singbox-macos-dual/bin/sing-box-arm64" \
      "$root/build/singbox-macos-dual/bin/sing-box-amd64"; do
      if [[ -f "$p" ]] && arch_compatible "$p" "$TARGET_ARCHS"; then
        echo "$p"
        return 0
      fi
    done
  fi

  for p in \
    "${HOME}/.cache/singbox-client/sing-box-universal" \
    "${HOME}/.cache/singbox-client/sing-box-arm64" \
    "${HOME}/.cache/singbox-client/sing-box-amd64"; do
    if [[ -f "$p" ]] && arch_compatible "$p" "$TARGET_ARCHS"; then
      echo "$p"
      return 0
    fi
  done

  if [[ -n "${SINGBOX_PATH:-}" && -f "${SINGBOX_PATH}" ]]; then
    if arch_compatible "${SINGBOX_PATH}" "$TARGET_ARCHS"; then
      echo "${SINGBOX_PATH}"
      return 0
    fi
  fi

  for p in /opt/homebrew/bin/sing-box /usr/local/bin/sing-box; do
    if [[ -f "$p" ]] && arch_compatible "$p" "$TARGET_ARCHS"; then
      echo "$p"
      return 0
    fi
  done
  if p="$(command -v sing-box 2>/dev/null)" && [[ -n "$p" && -f "$p" ]] && arch_compatible "$p" "$TARGET_ARCHS"; then
    echo "$p"
    return 0
  fi
  return 1
}

arch_compatible() {
  local bin="$1"
  local archs="$2"
  if [[ -z "$archs" ]]; then
    return 0
  fi
  local a
  for a in $archs; do
    if ! /usr/bin/lipo "$bin" -verify_arch "$a" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

if ! bin="$(find_binary)"; then
  echo "bundle_singbox: 未找到 sing-box，请执行: brew install sing-box 后重新构建。" >&2
  if [[ "$REQUIRED" == "1" ]]; then
    exit 2
  fi
  exit 0
fi

if ! arch_compatible "$bin" "$TARGET_ARCHS"; then
  echo "bundle_singbox: sing-box 架构与目标不匹配。bin=$bin target_archs='$TARGET_ARCHS'" >&2
  /usr/bin/file "$bin" >&2 || true
  if [[ "$REQUIRED" == "1" ]]; then
    exit 3
  fi
  exit 0
fi

cp -f "$bin" "$DST"
chmod +x "$DST"
echo "bundle_singbox: 已复制 $bin -> $DST (target_archs='$TARGET_ARCHS')"
