#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi
if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "未找到 flutter，可设置 FLUTTER_BIN=/path/to/flutter" >&2
  exit 2
fi

if [[ -z "${SINGBOX_VERSION:-}" ]]; then
  echo "SINGBOX_VERSION is required" >&2
  exit 1
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python || true)"
fi
if [[ -z "$PYTHON_BIN" ]]; then
  echo "未找到 Python，可设置 PYTHON_BIN=/path/to/python" >&2
  exit 3
fi

DIST_DIR="$ROOT/dist/android"
mkdir -p "$DIST_DIR"

echo "==> 准备 Android 原生依赖"
bash "$ROOT/scripts/prepare_android_ci.sh"

echo "==> flutter clean"
"$FLUTTER_BIN" clean
echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> 构建 Android App Bundle"
"$FLUTTER_BIN" build appbundle --release
cp -f \
  "$ROOT/build/app/outputs/bundle/release/app-release.aab" \
  "$DIST_DIR/singbox-client-release.aab"

echo "==> 构建 Android 通用 APK"
"$FLUTTER_BIN" build apk --release --target-platform android-arm,android-arm64,android-x64
cp -f \
  "$ROOT/build/app/outputs/flutter-apk/app-release.apk" \
  "$DIST_DIR/singbox-client-universal.apk"

echo "==> 构建 Android 分 ABI APK"
"$FLUTTER_BIN" build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
cp -f \
  "$ROOT/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" \
  "$DIST_DIR/singbox-client-armeabi-v7a.apk"
cp -f \
  "$ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" \
  "$DIST_DIR/singbox-client-arm64-v8a.apk"
cp -f \
  "$ROOT/build/app/outputs/flutter-apk/app-x86_64-release.apk" \
  "$DIST_DIR/singbox-client-x86_64.apk"

"$PYTHON_BIN" - <<'PY'
import pathlib
import zipfile

root = pathlib.Path("dist/android")
apk_names = [
    "singbox-client-universal.apk",
    "singbox-client-armeabi-v7a.apk",
    "singbox-client-arm64-v8a.apk",
    "singbox-client-x86_64.apk",
]

expected = {
    "singbox-client-universal.apk": [
        "lib/armeabi-v7a/libsing-box.so",
        "lib/arm64-v8a/libsing-box.so",
        "lib/x86_64/libsing-box.so",
    ],
    "singbox-client-armeabi-v7a.apk": ["lib/armeabi-v7a/libsing-box.so"],
    "singbox-client-arm64-v8a.apk": ["lib/arm64-v8a/libsing-box.so"],
    "singbox-client-x86_64.apk": ["lib/x86_64/libsing-box.so"],
}

for name in apk_names:
    path = root / name
    if not path.exists():
        raise SystemExit(f"missing artifact: {path}")
    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
    for lib_name in expected[name]:
        if lib_name not in names:
            raise SystemExit(f"{name} missing {lib_name}")

aab = root / "singbox-client-release.aab"
if not aab.exists():
    raise SystemExit(f"missing artifact: {aab}")

print("Android artifacts verified.")
PY

echo "==> 完成"
ls -lh "$DIST_DIR"
