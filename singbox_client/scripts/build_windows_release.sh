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

VERSION="${SINGBOX_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  echo "SINGBOX_VERSION is required" >&2
  exit 1
fi
VERSION="${VERSION#v}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python || true)"
fi
if [[ -z "$PYTHON_BIN" ]]; then
  echo "未找到 Python，可设置 PYTHON_BIN=/path/to/python" >&2
  exit 3
fi

WINDOWS_ARCH="${WINDOWS_ARCH:-amd64}"
DIST_DIR="$ROOT/dist/windows"
WORK_DIR="$ROOT/.build-tools/singbox-windows"
CACHE_DIR="$WORK_DIR/cache/v$VERSION"
UNPACK_DIR="$WORK_DIR/unpack-$WINDOWS_ARCH"
mkdir -p "$DIST_DIR" "$CACHE_DIR"

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

ASSET="sing-box-${VERSION}-windows-${WINDOWS_ARCH}.zip"
URL="${SINGBOX_WINDOWS_URL:-https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${ASSET}}"
ARCHIVE="$CACHE_DIR/$ASSET"

download_file "$URL" "$ARCHIVE"

rm -rf "$UNPACK_DIR"
mkdir -p "$UNPACK_DIR"
pwsh -NoProfile -Command \
  "Expand-Archive -LiteralPath '$ARCHIVE' -DestinationPath '$UNPACK_DIR' -Force"

echo "==> flutter clean"
"$FLUTTER_BIN" clean
echo "==> flutter pub get"
"$FLUTTER_BIN" pub get
echo "==> 构建 Windows Release"
"$FLUTTER_BIN" build windows --release

BUNDLE_DIR="$ROOT/build/windows/x64/runner/Release"
APP_DIR="$DIST_DIR/singbox-client-windows-x64"
ZIP_PATH="$DIST_DIR/singbox-client-windows-x64.zip"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -R "$BUNDLE_DIR"/. "$APP_DIR"/
cp -f "$UNPACK_DIR/sing-box.exe" "$APP_DIR/sing-box.exe"
for dll in "$UNPACK_DIR"/*.dll; do
  if [[ -f "$dll" ]]; then
    cp -f "$dll" "$APP_DIR/"
  fi
done

rm -f "$ZIP_PATH"
pwsh -NoProfile -Command \
  "Compress-Archive -LiteralPath '$APP_DIR' -DestinationPath '$ZIP_PATH' -Force"

"$PYTHON_BIN" - <<'PY'
import pathlib
import zipfile

root = pathlib.Path("dist/windows")
zip_path = root / "singbox-client-windows-x64.zip"
if not zip_path.exists():
    raise SystemExit(f"missing artifact: {zip_path}")

with zipfile.ZipFile(zip_path) as zf:
    names = set(zf.namelist())

required = {
    "singbox-client-windows-x64/singbox_client.exe",
    "singbox-client-windows-x64/sing-box.exe",
}
missing = sorted(required - names)
if missing:
    raise SystemExit(f"windows zip missing files: {missing}")

print("Windows artifact verified.")
PY

echo "==> 完成"
ls -lh "$DIST_DIR"
