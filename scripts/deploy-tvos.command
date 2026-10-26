#!/bin/zsh
# Doppelklick im Finder: FritzTV bauen und auf das gekoppelte Apple TV aufspielen.
# Protokoll in build/deploy-tvos.log.
cd "$(dirname "$0")/.."
mkdir -p build
./scripts/deploy-tvos.sh "$@" 2>&1 | tee build/deploy-tvos.log
echo ""
echo "Fertig (Protokoll: build/deploy-tvos.log). Dieses Fenster kann geschlossen werden."
