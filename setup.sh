#!/bin/bash
# Penny installer.
#
# Builds Penny.app from source, installs it to /Applications, sets up the
# dictation daemon under ~/.penny/, and registers both LaunchAgents.
#
# Safe to re-run after a `git pull`. Existing user data
# (~/.penny/config.json, ~/.penny/modes.json, Keychain entries) is preserved.

set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.penny"
ENV_DIR="$INSTALL_DIR/env"
APP_BUNDLE="/Applications/Penny.app"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
REFINER_PLIST="$LAUNCH_AGENTS/com.penny.refiner.plist"
DICTATE_PLIST="$LAUNCH_AGENTS/com.penny.dictate.plist"
REFINER_LOG="$INSTALL_DIR/refiner.log"
DICTATE_LOG="$INSTALL_DIR/dictate.log"
DICTATE_SCRIPT="$INSTALL_DIR/whisper-dictate"
BUILD_DIR="$APP_DIR/build"
BUILD_BUNDLE="$BUILD_DIR/Penny.app"

echo "Setting up Penny…"

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS" "$BUILD_DIR"

# ── 1. Tear down any older installs (Text Refiner / whisper-dictate) ────────

for label in com.textrefiner com.penny.refiner com.jonre.whisper-dictate com.penny.dictate; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
done
pkill -9 -f TextRefiner 2>/dev/null || true
pkill -9 -f whisper-dictate 2>/dev/null || true
sleep 1

rm -rf /Applications/TextRefiner.app
rm -f "$HOME/Library/LaunchAgents/com.textrefiner.plist"
rm -f "$HOME/Library/LaunchAgents/com.jonre.whisper-dictate.plist"

# ── 2. Seed user-editable config + modes on first install ───────────────────

if [ ! -f "$INSTALL_DIR/config.json" ]; then
  cp "$APP_DIR/config/config.json" "$INSTALL_DIR/config.json"
fi
if [ ! -f "$INSTALL_DIR/modes.json" ]; then
  cp "$APP_DIR/config/modes.default.json" "$INSTALL_DIR/modes.json"
fi

# ── 3. Shared Python virtualenv + deps ──────────────────────────────────────

python3 -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"
python -m pip install --quiet --upgrade pip
echo "  Installing Python dependencies (this may take a few minutes)…"
python -m pip install --quiet -r "$APP_DIR/requirements.txt"

# ── 4. Build Penny.app ──────────────────────────────────────────────────────

rm -rf "$BUILD_BUNDLE"
mkdir -p "$BUILD_BUNDLE/Contents/MacOS" "$BUILD_BUNDLE/Contents/Resources"

xcrun swiftc $APP_DIR/native/*.swift \
  -framework AppKit \
  -framework ApplicationServices \
  -framework AVFoundation \
  -framework Carbon \
  -framework IOKit \
  -framework LocalAuthentication \
  -o "$BUILD_BUNDLE/Contents/MacOS/Penny"

cp "$APP_DIR/refiner_cli.py" "$BUILD_BUNDLE/Contents/Resources/"
cp -R "$APP_DIR/refiner" "$BUILD_BUNDLE/Contents/Resources/"
cp -R "$APP_DIR/utils"   "$BUILD_BUNDLE/Contents/Resources/"
cp -R "$APP_DIR/config"  "$BUILD_BUNDLE/Contents/Resources/"
cp "$APP_DIR/requirements.txt" "$BUILD_BUNDLE/Contents/Resources/"

cat > "$BUILD_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Penny</string>
    <key>CFBundleIdentifier</key>
    <string>com.penny.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Penny</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Penny needs Accessibility access to detect the Right Option trigger and replace selected text in any app.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Penny uses the microphone for hold-to-dictate transcription while you hold Right Option.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2026 jonrepine. MIT License.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.penny.app "$BUILD_BUNDLE"

# ── 5. Install Penny.app to /Applications (or ~/Applications as fallback) ───

INSTALL_TARGET="$APP_BUNDLE"
if ! rm -rf "$APP_BUNDLE" 2>/dev/null || ! cp -R "$BUILD_BUNDLE" "$APP_BUNDLE" 2>/dev/null; then
  INSTALL_TARGET="$HOME/Applications/Penny.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALL_TARGET"
  cp -R "$BUILD_BUNDLE" "$INSTALL_TARGET"
fi

# ── 6. Install dictation script into ~/.penny ───────────────────────────────

cp "$APP_DIR/dictate/whisper-dictate" "$DICTATE_SCRIPT"
chmod +x "$DICTATE_SCRIPT"

# ── 7. Render and load both LaunchAgents ────────────────────────────────────

sed \
  -e "s#__PROGRAM__#$INSTALL_TARGET/Contents/MacOS/Penny#g" \
  -e "s#__LOG__#$REFINER_LOG#g" \
  -e "s#__PATH__#$PATH#g" \
  "$APP_DIR/launchd/com.penny.refiner.plist" > "$REFINER_PLIST"

sed \
  -e "s#__PYTHON__#$ENV_DIR/bin/python3#g" \
  -e "s#__SCRIPT__#$DICTATE_SCRIPT#g" \
  -e "s#__LOG__#$DICTATE_LOG#g" \
  -e "s#__PATH__#$PATH#g" \
  "$APP_DIR/launchd/com.penny.dictate.plist" > "$DICTATE_PLIST"

launchctl bootstrap "gui/$(id -u)" "$REFINER_PLIST"
launchctl bootstrap "gui/$(id -u)" "$DICTATE_PLIST"
launchctl kickstart -k "gui/$(id -u)/com.penny.refiner"
launchctl kickstart -k "gui/$(id -u)/com.penny.dictate"

# ── 8. Done ─────────────────────────────────────────────────────────────────

cat <<EOF

✓ Penny installed.

  App:           $INSTALL_TARGET
  Dictation:     $DICTATE_SCRIPT  (logs to $DICTATE_LOG)
  Refinement:    LaunchAgent com.penny.refiner  (logs to $REFINER_LOG)

  Shortcuts:
    Hold Right ⌥        → dictate (release to paste)
    Double-tap Right ⌥  → refine (pick a mode)

  First-launch note:
    The first time you hold Right ⌥, faster-whisper downloads its
    transcription model (~3 GB) into ~/.cache/huggingface/. Be on
    Wi-Fi the first time.

  When the menu bar P icon appears, click it → Preferences… and
  paste your Anthropic API key.

  macOS will prompt for Accessibility, Input Monitoring, and
  Microphone the first time each is needed. The onboarding window
  walks you through it.
EOF
