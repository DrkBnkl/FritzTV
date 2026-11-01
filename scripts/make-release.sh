#!/usr/bin/env zsh
# make-release.sh
# Baut die macOS-Universal-Version als FritzTV-macOS-Universal.zip und prüft sie.
# Die Version kommt aus project.yml.
#
#   ./scripts/make-release.sh                     Probelauf: bauen und prüfen, nichts veröffentlichen
#   ./scripts/make-release.sh --publish notes.md  zusätzlich main pushen, taggen und das
#                                                 GitHub-Release anlegen (erste Zeile = Titel)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

fail() { echo "❌ $1" >&2; exit 1; }

NOTES=""
if [[ "$1" == "--publish" ]]; then
    NOTES="$2"
    [[ -f "$NOTES" ]] || fail "Datei mit den Release Notes fehlt: --publish <notes.md>"
elif [[ -n "$1" ]]; then
    fail "Unbekannte Option: $1"
fi

VERSION=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml)
BUILD=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "([^"]+)".*/\1/p' project.yml)
[[ -n "$VERSION" && -n "$BUILD" ]] || fail "Version in project.yml nicht gefunden."
TAG="v$VERSION"
echo "=== FritzTV $VERSION (Build $BUILD) ==="

command -v xcodegen &> /dev/null || fail "XcodeGen fehlt (brew install xcodegen)."

if [[ -n "$NOTES" ]]; then
    command -v gh &> /dev/null || fail "GitHub CLI fehlt (brew install gh)."
    [[ "$(git symbolic-ref --short HEAD)" == "main" ]] || fail "Veröffentlichen geht nur von main aus."
    [[ -z "$(git status --porcelain)" ]] || fail "Es gibt nicht committete Änderungen."
    git fetch -q origin --tags
    git merge-base --is-ancestor origin/main HEAD || fail "Lokales main ist nicht auf dem Stand von origin/main."
    if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
        fail "Tag $TAG gibt es schon. Zuerst die Version in project.yml anheben."
    fi
    LATEST=$(git tag --list 'v*' --sort=-version:refname | head -n 1)
    [[ "$(printf '%s\n%s\n' "$LATEST" "$TAG" | sort -V | tail -n 1)" == "$TAG" ]] \
        || fail "$TAG ist nicht neuer als $LATEST."
fi

echo "→ Teste FritzTVKit..."
swift test --package-path FritzTVKit --quiet

export CONFIGURATION=Release
SKIP_INSTALL=1 ./scripts/deploy-macos.sh
APP_PATH="$PROJECT_DIR/build/macos/DerivedData/Build/Products/Release/FritzTV.app"

RELEASE_DIR="$PROJECT_DIR/build/release"
ZIP="$RELEASE_DIR/FritzTV-macOS-Universal.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP"
echo "→ Erzeuge $(basename "$ZIP")..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

# Geprüft wird, was ausgeliefert wird: die entpackte ZIP-Datei.
echo "→ Prüfe das Archiv..."
CHECK_DIR=$(mktemp -d -t fritztv-release)
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$ZIP" "$CHECK_DIR"
APP="$CHECK_DIR/FritzTV.app"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || fail "Falsche Version im Bundle."
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")" == "$BUILD" ]] || fail "Falsche Build-Nummer im Bundle."
for BINARY in "$APP/Contents/MacOS/FritzTV" "$APP/Contents/Frameworks/VLCKit.framework/Versions/A/VLCKit"; do
    ARCHS=$(lipo -archs "$BINARY")
    [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "$(basename "$BINARY") ist nicht universal: $ARCHS"
done
codesign --verify --deep --strict "$APP" || fail "Signatur ungültig."
for LICENSE_FILE in LICENSE-FritzTV.txt LGPL-2.1.txt GPL-2.0.txt THIRD-PARTY-NOTICES.txt; do
    [[ -s "$APP/Contents/Resources/Licenses/$LICENSE_FILE" ]] || fail "Lizenzdatei fehlt im Bundle: $LICENSE_FILE"
done
cmp -s LICENSE "$APP/Contents/Resources/Licenses/LICENSE-FritzTV.txt" || fail "Licenses/LICENSE-FritzTV.txt weicht von LICENSE ab."

SHA=$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)
echo "✔ Archiv in Ordnung: $ZIP"
echo "  SHA-256: $SHA"

if [[ -z "$NOTES" ]]; then
    echo "Probelauf: nichts veröffentlicht."
    exit 0
fi

TITLE=$(head -n 1 "$NOTES" | sed -E 's/^#+[[:space:]]*//')
echo "→ Veröffentliche $TAG: $TITLE"
git tag -a "$TAG" -m "Release $TAG"
git push origin main "$TAG"
gh release create "$TAG" "$ZIP" --title "$TITLE" --notes-file "$NOTES" --verify-tag --latest

REMOTE_SHA=$(gh release view "$TAG" --json assets --jq '.assets[0].digest' | sed 's/^sha256://')
[[ "$REMOTE_SHA" == "$SHA" ]] || fail "Prüfsumme auf GitHub weicht ab: $REMOTE_SHA"
echo "✔ Release $TAG veröffentlicht."
