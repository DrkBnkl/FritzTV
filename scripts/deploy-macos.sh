#!/usr/bin/env zsh
# deploy-macos.sh
# Baut die Release-Version von FritzTV für macOS inklusive vollständigem AppIcon.icns
# und installiert sie nach /Applications/FritzTV.app.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== FritzTV macOS Build & Installation ==="

if command -v xcodegen &> /dev/null; then
    echo "→ Aktualisiere Xcode-Projekt mit XcodeGen..."
    xcodegen generate --quiet
fi

BUILD_DIR="$PROJECT_DIR/build/macos"
mkdir -p "$BUILD_DIR"

CONFIGURATION="${CONFIGURATION:-Release}"

echo "→ Baue FritzTV-macOS ($CONFIGURATION)..."
xcodebuild -project FritzTV.xcodeproj \
    -scheme FritzTV-macOS \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/FritzTV.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Fehler: $APP_PATH wurde nicht gefunden."
    exit 1
fi

# Vollständiges hochauflösendes AppIcon.icns (bis 512x512@2x = 1024x1024) erzeugen,
# da actool unter neueren macOS-SDKs nur noch kleine Fallbacks in die .icns schreibt.
ICONSET_TMP=$(mktemp -d -t fritztv-icon).iconset
mkdir -p "$ICONSET_TMP"
cp "$PROJECT_DIR"/App/macOS/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET_TMP/"
iconutil -c icns "$ICONSET_TMP" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_TMP"

# Nach /Applications kopieren und neu signieren
TARGET_APP="/Applications/FritzTV.app"
echo "→ Installiere nach $TARGET_APP..."
rm -rf "$TARGET_APP"
cp -R "$APP_PATH" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP"
touch "$TARGET_APP"

# LaunchServices-Cache für das App-Bundle aktualisieren, damit Finder & Dock das Icon sofort zeigen
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$TARGET_APP" || true
fi

echo "✔ Erfolgreich installiert: $TARGET_APP"
