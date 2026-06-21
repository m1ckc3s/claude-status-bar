#!/bin/bash
# Builds ClaudeStatusBar.app (and optionally a .dmg with: ./build.sh --dmg).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudeStatusBar.app"
BIN="$APP/Contents/MacOS/ClaudeStatusBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling…"
swiftc -O Sources/*.swift -o "$BIN" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeStatusBar</string>
  <key>CFBundleDisplayName</key><string>Claude Status Bar</string>
  <key>CFBundleIdentifier</key><string>com.local.claudestatusbar</string>
  <key>CFBundleExecutable</key><string>ClaudeStatusBar</string>
  <key>CFBundleVersion</key><string>0.0.1</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# Bundle the hook scripts (so first-launch self-install works) and the app icon.
mkdir -p "$APP/Contents/Resources"
cp hooks/update.js hooks/lifecycle.js hooks/install.js hooks/uninstall.js "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# --- Signing / notarization ---
# For a clean (no Gatekeeper warning) release you need, set up once on this Mac:
#   1. A "Developer ID Application" certificate in your keychain (Xcode > Settings > Accounts).
#   2. A notarytool credential profile:
#        xcrun notarytool store-credentials "claude-statusbar" \
#          --apple-id you@example.com --team-id W9JZ4932LA --password <app-specific-password>
# Then `./build.sh --dmg` auto-signs + notarizes. Without a cert it falls back to an
# ad-hoc dev build (runnable locally; users would need right-click > Open once).
TEAM_ID="W9JZ4932LA"
NOTARY_PROFILE="${NOTARY_PROFILE:-claude-statusbar}"

SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | grep "$TEAM_ID" | head -1 | sed -E 's/.*"(.*)"/\1/')"

if [[ -n "$SIGN_ID" ]]; then
  echo "Signing with Developer ID: $SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "No Developer ID cert for team $TEAM_ID found — ad-hoc signing (local dev build)."
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  echo "Packaging DMG…"
  DMG="build/ClaudeStatusBar.dmg"
  STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG" build/rw.dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"

  # Lay out the window on a read-write image, then compress it.
  hdiutil create -volname "Claude Status Bar" -srcfolder "$STAGE" -ov -format UDRW build/rw.dmg >/dev/null
  device="$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | grep -E '^/dev/' | head -1 | awk '{print $1}')"
  sleep 1
  osascript <<'OSA' || echo "(Finder layout skipped — DMG still has the app + Applications shortcut)"
tell application "Finder"
  tell disk "Claude Status Bar"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 880, 540}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to 100
    set text size of vo to 12
    set position of item "ClaudeStatusBar.app" of container window to {130, 150}
    set position of item "Applications" of container window to {350, 150}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  rm -rf "/Volumes/Claude Status Bar/.fseventsd" "/Volumes/Claude Status Bar/.Trashes" 2>/dev/null || true
  sync; sleep 1
  hdiutil detach "$device" >/dev/null || true
  hdiutil convert build/rw.dmg -format UDZO -o "$DMG" >/dev/null
  rm -rf build/rw.dmg "$STAGE"

  if [[ "${SKIP_NOTARIZE:-}" == "1" ]]; then
    echo "Skipped notarization (SKIP_NOTARIZE=1) — layout test only, not for distribution."
  elif [[ -n "$SIGN_ID" ]]; then
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
    echo "Notarizing via profile '$NOTARY_PROFILE' (can take a minute)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "Notarized + stapled."
  else
    echo "DMG is unsigned — users will need right-click > Open the first time."
  fi
  echo "Built $DMG"
fi
