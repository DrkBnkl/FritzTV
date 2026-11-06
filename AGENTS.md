# AGENTS.md – Richtlinien für FritzTV

Verbindliche Regeln für alle Änderungen an diesem Repository. Funktionsbeschreibung: [README.md](README.md), Architektur: [docs/anforderungen.md](docs/anforderungen.md).

## Projektüberblick

| Pfad | Inhalt |
| :--- | :--- |
| `FritzTVKit/` | Swift-Paket mit plattformunabhängiger Logik und Unit-Tests |
| `App/Shared/` | Gemeinsamer Code von `FritzTV-tvOS` und `FritzTV-macOS` |
| `App/tvOS/`, `App/macOS/`, `App/TopShelf/` | Plattformspezifischer Code, Top-Shelf-Erweiterung |
| `App/Radio/` | `FritzRadio` (macOS-Menüleisten-App) |
| `project.yml` | XcodeGen-Projektdefinition, Version und Build-Nummer |
| `scripts/` | Build-, Deploy- und Release-Skripte |

## Build und Test

- `./setup.sh` erzeugt `FritzTV.xcodeproj` aus `project.yml`. Das `.xcodeproj` ist generiert: Änderungen an Targets, Einstellungen oder Info.plist-Werten erfolgen ausschließlich in `project.yml`.
- Tests: `swift test --package-path FritzTVKit`. Vor jedem Merge nach `develop` müssen die Tests durchlaufen.
- Neue Logik ohne UI-Bezug gehört nach `FritzTVKit` und wird dort getestet.
- Signatur-Team und Zugangsdaten werden nicht ins Repository geschrieben (`deploy-tvos.sh` ermittelt das Team zur Laufzeit).

## Branches

- **`main`:** Nur veröffentlichte Stände. Kein direkter Commit oder Push.
- **`develop`:** Integrationszweig. Größere Änderungen auf `feature/*`, `fix/*`, `docs/*`, `refactor/*` oder `chore/*` entwickeln und per `--no-ff` nach `develop` mergen.
- **Merge nach `main`:** Ausschließlich auf ausdrückliche Anweisung des Benutzers, als `--no-ff`-Merge von `develop` mit der Nachricht `Merge develop into main (<Version oder Anlass>)`.

## Commits

- Format: `<typ>[(bereich)]: <Beschreibung>` auf Deutsch, im Imperativ bzw. als Zustandsbeschreibung, ohne Punkt am Ende.
- Typen: `feat`, `fix`, `refactor`, `docs`, `chore`. Bereich optional, z. B. `feat(radio): …`.
- Versionssprünge als eigener Commit: `chore: Version X.Y.Z (Build N)`.

## Versionierung und Release

- Version (`MARKETING_VERSION`) und Build-Nummer (`CURRENT_PROJECT_VERSION`) stehen in `project.yml`. Die Build-Nummer steigt mit jeder Version um 1.
- Semantische Versionierung: Fehlerkorrektur → Patch, neue Funktion → Minor.
- **Jeder Merge nach `main` erfordert aktuelle macOS-Universal-Builds** (`FritzTV-macOS-Universal.zip`, `FritzRadio-macOS-Universal.zip`, arm64 + x86_64) im GitHub-Release:
  - **Änderungen am App-Code:** Version anheben, dann `./scripts/make-release.sh --publish <notes.md>`. Das Skript testet, baut, prüft die Archive, taggt `vX.Y.Z`, pusht `main` und legt das Release an.
  - **Änderungen ohne Einfluss auf den App-Code** (z. B. Dokumentation): keine neue Version. `./scripts/make-release.sh` (Probelauf) ausführen und die Archive im aktuellen Release ersetzen: `gh release upload vX.Y.Z build/release/*.zip --clobber`. Prüfsummen anschließend mit dem Release abgleichen.
- **Release Notes:** Erste Zeile ist der Titel (`FritzTV X.Y.Z`), danach ein bis zwei allgemeine Sätze und ein Hinweis auf die Downloads. Keine Auflistung einzelner Änderungen; Details stehen in den Commits.

## Lokales Deployment

Nach Änderungen am App-Code (nicht bei reinen Doku-Änderungen) wird lokal installiert:

| Geändert | Skript | Ziel |
| :--- | :--- | :--- |
| `App/Shared`, `App/macOS`, `FritzTVKit` | `./scripts/deploy-macos.sh` | `/Applications/FritzTV.app` |
| `App/Radio`, Radio-Teile von `FritzTVKit` | `./scripts/deploy-fritzradio.sh` | `/Applications/FritzRadio.app` |
| `App/Shared`, `App/tvOS`, `App/TopShelf`, `FritzTVKit` | `./scripts/deploy-tvos.sh` | Gekoppeltes Apple TV |

Ist kein Apple TV erreichbar, schlägt `deploy-tvos.sh` fehl. Das ist kein Grund, die Änderung zurückzuhalten, wird aber im Ergebnis gemeldet.

## Dokumentation

- Sprache: Deutsch; die README enthält zusätzlich eine englische Zusammenfassung.
- Stil: sachlich, technisch, knapp. Keine persönlichen Angaben, keine Anrede, keine Werbesprache.
- Angaben zu Werten, Schnittstellen und Bezeichnern müssen dem Code entsprechen. Bei Änderungen an Funktionen, Bedienung oder Skripten werden `README.md`, `docs/anforderungen.md` und `FritzTVKit/README.md` mitgepflegt.
