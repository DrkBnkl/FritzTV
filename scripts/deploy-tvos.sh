#!/usr/bin/env zsh
# deploy-tvos.sh
# Automatisiertes Bauen und Neuaufspielen von FritzTV auf das Apple TV.
# Einstellungen und Senderplätze bleiben beim Update erhalten.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== FritzTV Apple TV Deployment ==="

# Team für die Signatur: aus der Umgebung oder automatisch aus der in Xcode angemeldeten
# Apple-ID (kostenloses „Personal Team“ genügt). So muss das Team nicht im Projekt stehen,
# das XcodeGen bei jedem ./setup.sh neu erzeugt.
if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    DEVELOPMENT_TEAM=$(defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -c '
import plistlib, sys
try:
    prefs = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
teams = []
for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
    for entries in (prefs.get(key) or {}).values():
        for team in entries or []:
            if isinstance(team, dict) and team.get("teamID"):
                teams.append(team)
# Bevorzugt das kostenlose Personal Team, sonst das erste gefundene.
teams.sort(key=lambda t: not t.get("isFreeProvisioningTeam", False))
print(teams[0]["teamID"] if teams else "")
' 2>/dev/null || true)
fi
if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    echo "→ Signatur-Team: $DEVELOPMENT_TEAM"
else
    echo "⚠️  Kein Team gefunden. In Xcode unter Settings › Accounts die Apple-ID anmelden"
    echo "   oder DEVELOPMENT_TEAM=<Team-ID> setzen."
fi

# 1. Xcode-Projekt aktualisieren
if command -v xcodegen &> /dev/null; then
    echo "→ Aktualisiere Xcode-Projekt mit XcodeGen..."
    xcodegen generate --quiet
fi

# 2. Apple TV Gerät ermitteln
# DEVICE_ID: CoreDevice-Kennung (für devicectl), DEVICE_UDID: UDID (für xcodebuild -destination).
DEVICE_ID="${1:-$APPLE_TV_DEVICE_ID}"
DEVICE_UDID="${APPLE_TV_UDID:-}"

if [[ -z "$DEVICE_ID" || -z "$DEVICE_UDID" ]]; then
    echo "→ Suche nach gekoppelten Apple TVs..."
    # JSON in eine Datei: Auf die Standardausgabe schreibt devicectl zusätzlich seine Tabelle.
    DEVICES_JSON_FILE=$(mktemp -t fritztv-devices)
    xcrun devicectl list devices --json-output "$DEVICES_JSON_FILE" >/dev/null 2>&1 || true
    DEVICE_INFO=$(/usr/bin/python3 - "$DEVICES_JSON_FILE" "$DEVICE_ID" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        devices = json.load(f).get("result", {}).get("devices", [])
except Exception:
    sys.exit(0)
wanted = sys.argv[2] if len(sys.argv) > 2 else ""
for d in devices:
    hw = d.get("hardwareProperties", {}) or {}
    props = d.get("deviceProperties", {}) or {}
    is_tv = (str(hw.get("platform", "")).lower() == "tvos"
             or str(hw.get("deviceType", "")).lower() == "appletv"
             or "apple tv" in str(props.get("name", "")).lower())
    if not is_tv:
        continue
    # Simulatoren überspringen (devicectl listet gebootete Simulatoren ebenfalls als Apple TV).
    if str(hw.get("reality", "")).lower() == "simulated":
        continue
    if wanted and wanted not in (d.get("identifier"), hw.get("udid")):
        continue
    print(d.get("identifier", ""), hw.get("udid", ""), props.get("name", "Apple TV"), sep="\t")
    break
PY
)
    rm -f "$DEVICES_JSON_FILE"
    if [[ -n "$DEVICE_INFO" ]]; then
        DEVICE_ID=$(echo "$DEVICE_INFO" | cut -f1)
        DEVICE_UDID=$(echo "$DEVICE_INFO" | cut -f2)
        echo "→ Apple TV gefunden: $(echo "$DEVICE_INFO" | cut -f3) ($DEVICE_UDID)"
    fi
fi

if [[ -z "$DEVICE_ID" ]]; then
    echo "Hinweis: Kein Apple TV automatisch erkannt."
    echo "Verwendung: ./scripts/deploy-tvos.sh <Apple-TV-Device-UUID>"
    echo "Gekoppelte Geräte:"
    xcrun devicectl list devices 2>&1 || true
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
# Mit kostenloser Apple-ID gibt es ein Profil nur für ein registriertes Gerät: deshalb
# direkt für das gefundene Apple TV bauen (registriert es bei Bedarf im Personal Team).
if [[ -n "$DEVICE_UDID" ]]; then
    DESTINATION="platform=tvOS,id=$DEVICE_UDID"
else
    DESTINATION="generic/platform=tvOS"
fi

xcodebuild -scheme FritzTV-tvOS \
    -destination "$DESTINATION" \
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
