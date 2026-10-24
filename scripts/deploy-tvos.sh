#!/usr/bin/env zsh
# deploy-tvos.sh
# Automatisiertes Bauen und Neuaufspielen von FritzTV auf das Apple TV.
# Einstellungen und Senderplätze bleiben beim Update erhalten.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== FritzTV Apple TV Deployment ==="

# 1. Xcode-Projekt aktualisieren
if command -v xcodegen &> /dev/null; then
    echo "→ Aktualisiere Xcode-Projekt mit XcodeGen..."
    xcodegen generate --quiet
fi

# 2. Apple TV Gerät ermitteln
DEVICE_ID="${1:-$APPLE_TV_DEVICE_ID}"

if [[ -z "$DEVICE_ID" ]]; then
    echo "→ Suche nach gekoppelten Apple TVs..."
    # Suche mit xcrun devicectl
    DEVICES_JSON=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null || true)
    
    # Extrahiere Apple TV Geräte-Identifier
    DEVICE_ID=$(echo "$DEVICES_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    devices = data.get("result", {}).get("devices", [])
    tv_devices = [d for d in devices if "appletv" in d.get("hardwareModel", "").lower() or "apple tv" in d.get("deviceProperties", {}).get("name", "").lower()]
    if tv_devices:
        print(tv_devices[0]["identifier"])
except Exception:
    pass
' 2>/dev/null || true)
fi

if [[ -z "$DEVICE_ID" ]]; then
    echo "Hinweis: Kein Apple TV automatisch erkannt."
    echo "Verwendung: ./scripts/deploy-tvos.sh <Apple-TV-Device-UUID>"
    echo "Gekoppelte Geräte anzeigen mit: xcrun devicectl list devices"
    echo ""
    echo "Führe trotzdem den Build für generisches tvOS aus..."
fi

# 3. App für tvOS bauen
BUILD_DIR="$PROJECT_DIR/build/tvos"
mkdir -p "$BUILD_DIR"

echo "→ Baue FritzTV-tvOS..."
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    TEAM_ARG="DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
else
    TEAM_ARG=""
fi

# -allowProvisioningUpdates: Mit kostenloser Apple-ID läuft das Profil nach 7 Tagen ab;
# so holt xcodebuild beim Bauen selbst ein neues (setzt eine in Xcode angemeldete Apple-ID voraus).
xcodebuild -scheme FritzTV-tvOS \
    -destination "generic/platform=tvOS" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    $TEAM_ARG \
    build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Debug-appletvos/FritzTV.app"

if [[ ! -d "$APP_PATH" ]]; then
    # Fallback Suche
    APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "FritzTV.app" -type d | head -n 1)
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "❌ Fehler: FritzTV.app wurde nicht gefunden."
    exit 1
fi

echo "✔ Build erfolgreich: $APP_PATH"

# 4. Installation auf Apple TV
if [[ -n "$DEVICE_ID" ]]; then
    echo "→ Installiere auf Apple TV ($DEVICE_ID)..."
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
    echo "✔ Erfolgreich auf Apple TV installiert! Einstellungen bleiben erhalten."
    echo "Hinweis: Mit kostenloser Apple-ID ist die Signatur 7 Tage gültig."
else
    echo "ℹ️  Zum Installieren auf dem Apple TV ausführen:"
    echo "   xcrun devicectl device install app --device <UUID> \"$APP_PATH\""
fi
