#!/usr/bin/env bash
#
# Ersetzt eine installierte MonDial durch einen frisch geladenen Build.
# Immer erst aufräumen, dann installieren - sonst läuft im Hintergrund weiter
# der alte Code, während im Programme-Ordner schon die neue Datei liegt.
#
#   ./tools/reinstall.sh ~/Downloads/MonDial-app.zip
#
set -euo pipefail

ZIP="${1:-}"
TARGET="/Applications/MonDial.app"

if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Aufruf: $0 <Pfad zu MonDial-app.zip>" >&2
  exit 1
fi

echo "==> Laufende Instanz beenden"
osascript -e 'quit app "MonDial"' 2>/dev/null || true
pkill -x MonDial 2>/dev/null || true
sleep 1

echo "==> Alte App entfernen: $TARGET"
rm -rf "$TARGET"

echo "==> Entpacken: $ZIP"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$ZIP" -d "$WORK"
APP="$(find "$WORK" -maxdepth 2 -name 'MonDial.app' -print -quit)"
if [[ -z "$APP" ]]; then
  echo "Im ZIP wurde kein MonDial.app gefunden." >&2
  exit 1
fi
cp -R "$APP" "$TARGET"

echo "==> Quarantäne entfernen"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> Installierte Version"
"$TARGET/Contents/Resources/mondialctl" --version

echo "==> MonDial starten"
open "$TARGET"