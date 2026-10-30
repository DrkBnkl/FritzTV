# Entwicklungs-Richtlinien für FritzTV

## Git- und Branch-Workflow
1. **Kein direkter Push auf `main`:**
   - Änderungen dürfen **niemals direkt auf den Branch `main`** committet oder gepusht werden.
   - Alle Entwicklungen, neuen Features und Bugfixes erfolgen auf dem Entwicklungszweig **`develop`** (oder auf einem separaten Branch wie `feature/*` bzw. `fix/*`, der in `develop` gemergt wird).
2. **Merge nach `main`:**
   - Ein Merge in den Branch `main` (und das Taggen eines neuen Releases) darf **ausschließlich nach ausdrücklicher Aufforderung durch den Benutzer** erfolgen.

## Lokales Testen & Deployment
- Nach relevanten Codeänderungen wird die macOS-App weiterhin lokal mit `./scripts/deploy-macos.sh` kompiliert und nach `/Applications/FritzTV.app` installiert, damit der Benutzer die Änderungen sofort lokal testen kann.
