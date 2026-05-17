#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClipShelf"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$("$ROOT_DIR/script/build_app_bundle.sh")"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
DESKTOP_LINK="$HOME/Desktop/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "ClipShelfLite" >/dev/null 2>&1 || true

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
rm -rf "$INSTALL_DIR/ClipShelfLite.app"
ditto "$SOURCE_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$INSTALLED_APP" >/dev/null 2>&1 || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$INSTALLED_APP" >/dev/null 2>&1 || true

rm -f "$DESKTOP_LINK"
rm -f "$HOME/Desktop/ClipShelfLite.app"
ln -s "$INSTALLED_APP" "$DESKTOP_LINK"

open "$INSTALLED_APP"
echo "$INSTALLED_APP"
