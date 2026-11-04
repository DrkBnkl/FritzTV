#!/usr/bin/env zsh
# deploy-fritzradio.sh
# Baut die Release-Version von FritzRadio (Menüleisten-App) für macOS
# und installiert sie nach /Applications/FritzRadio.app.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== FritzRadio macOS Build & Installation ==="

if command -v xcodegen &> /dev/null; then
    echo "→ Aktualisiere Xcode-Projekt mit XcodeGen..."
    xcodegen generate --quiet
fi

BUILD_DIR="$PROJECT_DIR/build/macos"
mkdir -p "$BUILD_DIR"

CONFIGURATION="${CONFIGURATION:-Release}"

echo "→ Baue FritzRadio-macOS ($CONFIGURATION, Universal 2: Apple Silicon & Intel)..."
xcodebuild -project FritzTV.xcodeproj \
    -scheme FritzRadio-macOS \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/FritzRadio.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Fehler: $APP_PATH wurde nicht gefunden."
    exit 1
fi

# SKIP_INSTALL=1 (make-release.sh): nur fertig signieren, nichts installieren
if [[ -n "$SKIP_INSTALL" ]]; then
    codesign --force --deep --sign - "$APP_PATH"
    echo "✔ Gebaut: $APP_PATH"
    exit 0
fi

# Laufende Instanz beenden, sonst bleibt die alte Version in der Menüleiste
WAS_RUNNING=""
if pgrep -xq FritzRadio; then
    WAS_RUNNING=1
    osascript -e 'quit app "FritzRadio"' 2>/dev/null || pkill -x FritzRadio || true
    sleep 1
fi

TARGET_APP="/Applications/FritzRadio.app"
echo "→ Installiere nach $TARGET_APP..."
rm -rf "$TARGET_APP"
cp -R "$APP_PATH" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"
touch "$TARGET_APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$TARGET_APP" || true
fi

[[ -n "$WAS_RUNNING" ]] && open "$TARGET_APP"

echo "✔ Erfolgreich installiert: $TARGET_APP"
