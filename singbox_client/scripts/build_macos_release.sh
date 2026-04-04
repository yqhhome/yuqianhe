#!/usr/bin/env bash
# 兼容入口：默认改为构建 macOS 双版本（ARM + Intel），并内置 sing-box。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/build_macos_dual_release.sh"
