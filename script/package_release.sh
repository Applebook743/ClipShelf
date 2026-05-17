#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClipShelf"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$("$ROOT_DIR/script/build_app_bundle.sh")"
ZIP_PATH="$RELEASE_DIR/${APP_NAME}.zip"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$ZIP_PATH"
