#!/bin/bash
# Baut die beiden Pakete aus den Quellen:
#   dist/macos/GrindGuard/            -> dist/GrindGuard-macOS.zip
#   dist/windows/GrindGuard-Windows/  -> dist/GrindGuard-Windows.zip
# und schreibt dist/SHA256SUMS.txt.
#
#   tools/build.sh           Pakete bauen
#   tools/build.sh --no-zip  nur die Ordner (für die Tests)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$ROOT/dist"
ZIP=1
[ "${1:-}" = "--no-zip" ] && ZIP=0

rm -rf "$DIST"
MAC="$DIST/macos/GrindGuard"
WIN="$DIST/windows/GrindGuard-Windows"
mkdir -p "$MAC" "$WIN"

# --- macOS: Zeilenenden LF, UTF-8 ohne BOM ---
cp -R "$ROOT/macos/." "$MAC/"
cp "$ROOT/shared/config/websites.txt" "$ROOT/shared/config/sprueche.txt" "$MAC/app/config/"
mkdir -p "$MAC/app/update"
cp "$ROOT/shared/update/standard-aus.txt" "$MAC/app/update/"
chmod 755 "$MAC/install.sh" "$MAC/app/grind"

# --- Windows: Zeilenenden CRLF ---
cp -R "$ROOT/windows/." "$WIN/"
mkdir -p "$WIN/app/update"
to_crlf() {     # $1 = Quelle (LF), $2 = Ziel (CRLF)
    sed -e 's/\r$//' -e 's/$/\r/' "$1" > "$2"
}
to_crlf "$ROOT/shared/config/websites.txt" "$WIN/app/config/websites.txt"
to_crlf "$ROOT/shared/config/sprueche.txt" "$WIN/app/config/sprueche.txt"
to_crlf "$ROOT/shared/update/standard-aus.txt" "$WIN/app/update/standard-aus.txt"

if [ "$ZIP" = 1 ]; then
    VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/macos/app/grind")
    ( cd "$DIST/macos" && rm -f "../GrindGuard-macOS.zip" && zip -qr -X "../GrindGuard-macOS.zip" GrindGuard )
    ( cd "$WIN" && rm -f "../../GrindGuard-Windows.zip" && zip -qr -X "../../GrindGuard-Windows.zip" . )
    ( cd "$DIST" && sha256sum GrindGuard-macOS.zip GrindGuard-Windows.zip > SHA256SUMS.txt )
    echo "Gebaut: GrindGuard $VERSION"
    ls -l "$DIST"/*.zip "$DIST/SHA256SUMS.txt"
fi
