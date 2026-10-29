#!/bin/bash
# Doppelklick im Finder: erzeugt das Xcode-Projekt neu und öffnet es.
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.homebrew/bin:$PATH"
./setup.sh
echo
echo "Fertig. Dieses Fenster kann geschlossen werden."
