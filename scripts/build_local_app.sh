#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${1:-NanoBananaDesktop.app}"
APP_PATH="$ROOT_DIR/$APP_NAME"
ICON_PATH="$ROOT_DIR/NanoBananaDesktop/Resources/AppIcon.icns"

echo "[build-local-app] Building release binary..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
EXEC_PATH="$BIN_DIR/NanoBananaDesktop"
if [[ ! -x "$EXEC_PATH" ]]; then
  echo "[build-local-app] ERROR: executable not found: $EXEC_PATH" >&2
  exit 1
fi

echo "[build-local-app] Creating app bundle: $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$EXEC_PATH" "$APP_PATH/Contents/MacOS/NanoBananaDesktop"
chmod +x "$APP_PATH/Contents/MacOS/NanoBananaDesktop"

# Copy SwiftPM resources (localizations and other runtime resources)
RESOURCE_BUNDLE="$(find "$(dirname "$BIN_DIR")" -maxdepth 3 -type d -name '*NanoBananaDesktop*.bundle' | head -n1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/"
fi

# Copy the canonical app icon if present
if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"
  ICON_PLIST_VALUE="AppIcon.icns"
else
  echo "[build-local-app] WARNING: icon not found at $ICON_PATH. Building without custom icon."
  ICON_PLIST_VALUE=""
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>NanoBananaDesktop</string>
  <key>CFBundleDisplayName</key>
  <string>NanoBananaDesktop</string>
  <key>CFBundleIdentifier</key>
  <string>com.nanobanana.desktop.local</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>NanoBananaDesktop</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
PLIST

if [[ -n "$ICON_PLIST_VALUE" ]]; then
  cat >> "$APP_PATH/Contents/Info.plist" <<PLIST
  <key>CFBundleIconFile</key>
  <string>$ICON_PLIST_VALUE</string>
PLIST
fi

cat >> "$APP_PATH/Contents/Info.plist" <<'PLIST'
</dict>
</plist>
PLIST

echo "[build-local-app] Applying ad-hoc code signature..."
codesign --force --deep --sign - "$APP_PATH"

echo "[build-local-app] Done: $APP_PATH"
