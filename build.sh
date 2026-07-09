#!/bin/bash
# Builds ClaudeStatusBar.app (and optionally a .dmg with: ./build.sh --dmg).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudeStatusBar.app"
BIN="$APP/Contents/MacOS/ClaudeStatusBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling universal binary (arm64 + x86_64)…"
# Universal binary so it runs natively on both Apple Silicon and Intel (each Mac uses its own
# slice, so Rosetta is never involved). swiftc emits one arch per -target, so this is two
# compiles joined by lipo. Keep the deployment target pinned, else swiftc stamps the binary
# with the build machine's OS and it refuses to launch on older systems despite LSMinimumSystemVersion.
swiftc -O -target arm64-apple-macos12.0  Sources/*.swift -o "$BIN.arm64"  -framework Cocoa
swiftc -O -target x86_64-apple-macos12.0 Sources/*.swift -o "$BIN.x86_64" -framework Cocoa
lipo -create "$BIN.arm64" "$BIN.x86_64" -output "$BIN"
rm -f "$BIN.arm64" "$BIN.x86_64"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeStatusBar</string>
  <key>CFBundleDisplayName</key><string>Claude Status Bar</string>
  <key>CFBundleIdentifier</key><string>com.local.claudestatusbar</string>
  <key>CFBundleExecutable</key><string>ClaudeStatusBar</string>
  <key>CFBundleVersion</key><string>0.3.3</string>
  <key>CFBundleShortVersionString</key><string>0.3.3</string>
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

# `|| true` so a missing Developer ID cert (grep matches nothing → nonzero, which `set -eo pipefail`
# would otherwise treat as a fatal error) falls through to the ad-hoc dev build below instead of
# aborting the whole script.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | grep "$TEAM_ID" | head -1 | sed -E 's/.*"(.*)"/\1/')" || true

# Strip extended attributes (Finder info, quarantine, etc.) that bundled resources can
# carry — codesign rejects them ("resource fork, Finder information, ... not allowed").
xattr -cr "$APP"

if [[ -n "$SIGN_ID" ]]; then
  echo "Signing with Developer ID: $SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "No Developer ID cert for team $TEAM_ID found — ad-hoc signing (local dev build)."
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
  # Notarize + staple the APP first, so a copied-out .app is independently notarized.
  # The DMG itself is notarized + stapled later (below) — that's the check a downloader
  # actually hits, so the image must carry its own ticket to open without a warning.
  if [[ "${SKIP_NOTARIZE:-}" != "1" && -n "$SIGN_ID" ]]; then
    echo "Notarizing the app via profile '$NOTARY_PROFILE' (can take a minute)…"
    rm -f build/app-notarize.zip
    ditto -c -k --keepParent "$APP" build/app-notarize.zip
    xcrun notarytool submit build/app-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f build/app-notarize.zip
    echo "App notarized + stapled."
  fi

  echo "Packaging DMG…"
  DMG="build/ClaudeStatusBar.dmg"
  STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG" build/rw.dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"

  # Eject any stale "Claude Status Bar" volumes from earlier builds first. Otherwise a name
  # collision mounts this one as "Claude Status Bar 2", the hardcoded /Volumes path below points
  # at the wrong volume (layout capture silently fails), and the stale mounts pile up in Finder.
  for d in $(hdiutil info | awk '/Claude Status Bar/ {print $1}'); do hdiutil detach "$d" >/dev/null 2>&1 || true; done

  # Lay out the window on a read-write image to capture its .DS_Store, then build the final
  # image from the folder (see below).
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
  # Capture the layout Finder just wrote (.DS_Store), then discard the writable image and build
  # the final compressed image straight from the folder. Building from a folder never mounts a
  # writable volume, so macOS's fseventsd never creates a hidden .fseventsd in the shipped DMG.
  # (Removing .fseventsd from a mounted volume does not stick: the removal is itself an event
  # fseventsd logs, which recreates the folder.)
  cp "/Volumes/Claude Status Bar/.DS_Store" "$STAGE/.DS_Store" 2>/dev/null || true
  hdiutil detach "$device" >/dev/null || true
  rm -f build/rw.dmg
  # Scrub any hidden folder that may have accrued (.fseventsd, .Trashes, .Spotlight-V100, …),
  # keeping only the intentional .DS_Store that carries the window layout.
  find "$STAGE" -maxdepth 1 -name ".*" ! -name ".DS_Store" -exec rm -rf {} + 2>/dev/null || true
  hdiutil create -volname "Claude Status Bar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"

  # Guard: the shipped image must hold nothing but the app, the Applications symlink, and the
  # .DS_Store layout file. Mount read-only and abort before notarizing if any stray hidden entry
  # slipped in (the recurring .fseventsd/.Trashes problem).
  vdev="$(hdiutil attach -nobrowse -noautoopen -readonly "$DMG" | grep -E '^/dev/' | tail -1 | awk '{print $1}')"
  stray="$(find "/Volumes/Claude Status Bar" -maxdepth 1 -name ".*" ! -name ".DS_Store" 2>/dev/null)"
  hdiutil detach "$vdev" >/dev/null 2>&1 || true
  if [[ -n "$stray" ]]; then
    echo "ERROR: DMG has stray hidden entries, aborting before notarize:"; echo "$stray"; exit 1
  fi
  echo "DMG verified clean (no stray hidden folders)."

  # Sign, then notarize + staple the DMG so the downloaded image opens with no Gatekeeper
  # warning. Stapling writes the ticket into the read-only image's metadata; it does not
  # mount-and-write the inner filesystem, so .fseventsd does not come back.
  if [[ -n "$SIGN_ID" ]]; then
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
    if [[ "${SKIP_NOTARIZE:-}" != "1" ]]; then
      echo "Notarizing the DMG via profile '$NOTARY_PROFILE' (can take a minute)…"
      xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$DMG"
      echo "DMG notarized + stapled."
    else
      echo "SKIP_NOTARIZE=1 — DMG signed but NOT notarized (layout test only)."
    fi
  fi
  echo "Built $DMG"
fi
