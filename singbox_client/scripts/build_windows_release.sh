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

CLIENT_BUILD_SEQ="${CLIENT_BUILD_SEQ:-$("$PYTHON_BIN" - <<'PY'
from pathlib import Path
import re

text = Path("pubspec.yaml").read_text(encoding="utf-8")
match = re.search(r"^version:\s+[^\+]+\+(\d+)\s*$", text, re.M)
print(match.group(1) if match else "1")
PY
)}"
BUILD_LABEL="${CLIENT_BUILD_LABEL:-V${CLIENT_BUILD_SEQ}版本}"

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
ARCHIVE_PATH="$ARCHIVE" UNPACK_PATH="$UNPACK_DIR" "$PYTHON_BIN" - <<'PY'
import os
import pathlib
import zipfile

archive = pathlib.Path(os.environ["ARCHIVE_PATH"]).resolve()
unpack = pathlib.Path(os.environ["UNPACK_PATH"]).resolve()

if not archive.is_file():
    raise SystemExit(f"missing archive: {archive}")

with zipfile.ZipFile(archive) as zf:
    zf.extractall(unpack)

print(f"Extracted {archive.name} -> {unpack}")
PY

echo "==> flutter clean"
"$FLUTTER_BIN" clean
echo "==> flutter pub get"
"$FLUTTER_BIN" pub get
echo "==> 构建 Windows Release"
"$FLUTTER_BIN" build windows --release "--dart-define=CLIENT_BUILD_LABEL=${BUILD_LABEL}"

BUNDLE_DIR="$ROOT/build/windows/x64/runner/Release"
APP_DIR="$DIST_DIR/singbox-client-windows-x64"
ZIP_PATH="$DIST_DIR/singbox-client-windows-x64.zip"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
WINDOWS_BUNDLE_DIR="$BUNDLE_DIR" \
WINDOWS_APP_DIR="$APP_DIR" \
WINDOWS_UNPACK_DIR="$UNPACK_DIR" \
"$PYTHON_BIN" - <<'PY'
import os
import pathlib
import shutil

bundle_dir = pathlib.Path(os.environ["WINDOWS_BUNDLE_DIR"]).resolve()
app_dir = pathlib.Path(os.environ["WINDOWS_APP_DIR"]).resolve()
unpack_dir = pathlib.Path(os.environ["WINDOWS_UNPACK_DIR"]).resolve()

if not bundle_dir.is_dir():
    raise SystemExit(f"missing Windows bundle dir: {bundle_dir}")

for path in bundle_dir.iterdir():
    target = app_dir / path.name
    if path.is_dir():
        shutil.copytree(path, target, dirs_exist_ok=True)
    else:
        shutil.copy2(path, target)

exe_candidates = sorted(unpack_dir.rglob("sing-box.exe"))
if not exe_candidates:
    raise SystemExit(f"sing-box.exe not found under {unpack_dir}")
shutil.copy2(exe_candidates[0], app_dir / "sing-box.exe")

for dll in sorted(unpack_dir.rglob("*.dll")):
    shutil.copy2(dll, app_dir / dll.name)

print(f"Prepared Windows portable bundle at {app_dir}")
PY

rm -f "$ZIP_PATH"
APP_DIR_PATH="$APP_DIR" ZIP_PATH_VALUE="$ZIP_PATH" "$PYTHON_BIN" - <<'PY'
import os
import pathlib
import zipfile

app_dir = pathlib.Path(os.environ["APP_DIR_PATH"]).resolve()
zip_path = pathlib.Path(os.environ["ZIP_PATH_VALUE"]).resolve()

if not app_dir.is_dir():
    raise SystemExit(f"missing app dir: {app_dir}")

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in app_dir.rglob("*"):
        if path.is_file():
            zf.write(path, path.relative_to(app_dir.parent))

print(f"Created {zip_path}")
PY

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
