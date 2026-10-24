#!/bin/bash
# Erzeugt das Xcode-Projekt aus project.yml und öffnet es.
set -e
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installiere XcodeGen über Homebrew …"
    brew install xcodegen
  else
    echo "XcodeGen fehlt und Homebrew ist nicht im PATH."
    echo "Bitte Homebrew installieren (https://brew.sh) oder XcodeGen von https://github.com/yonaskolb/XcodeGen holen."
    exit 1
  fi
fi

xcodegen generate
open FritzTV.xcodeproj
