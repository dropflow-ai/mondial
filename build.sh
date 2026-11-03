#!/usr/bin/env bash
#
# Baut MonDial.app und das Kommandozeilenwerkzeug mondialctl.
#
#   ./build.sh              baut nach dist/
#   ./build.sh --install    baut und kopiert die App nach /Applications
#   ./build.sh --run        baut und startet die App
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
APP_NAME="MonDial"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Baue ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"
swift build -c "$CONFIG" --product mondialctl

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_PATH/mondialctl" "$DIST/mondialctl"
# Das CLI liegt zusätzlich im Bundle, damit es ohne Installation nutzbar ist.
cp "$BIN_PATH/mondialctl" "$APP/Contents/Resources/mondialctl"
chmod +x "$DIST/mondialctl"

if [ -f "Resources/AppIcon.png" ]; then
    ICONSET="$DIST/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET"
fi

# Ad-hoc-Signatur: reicht für den lokalen Betrieb und für LaunchAgents.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "Hinweis: Ad-hoc-Signatur fehlgeschlagen – die App startet trotzdem."

echo "==> Fertig"
echo "    App:  $APP"
echo "    CLI:  $DIST/mondialctl"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installiere nach /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    if [ -w /usr/local/bin ]; then
        ln -sf "$PWD/$DIST/mondialctl" /usr/local/bin/mondialctl
        echo "    CLI verlinkt: /usr/local/bin/mondialctl"
    else
        echo "    Für den CLI-Link bitte manuell ausführen:"
        echo "    sudo ln -sf \"$PWD/$DIST/mondialctl\" /usr/local/bin/mondialctl"
    fi
    open "/Applications/$APP_NAME.app"
fi

if [ "${1:-}" = "--run" ]; then
    open "$APP"
fi
