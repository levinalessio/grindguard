#!/bin/bash
# Gemeinsamer Testkatalog: Mac (grind), Windows-Nachbau (Python) und – wenn vorhanden –
# die echte Windows-Version (PowerShell) müssen für jede Adresse dasselbe entscheiden.
#
#   tests/corpus/run.sh                 Mac + Python-Nachbau
#   GG_PWSH=powershell tests/corpus/run.sh   zusätzlich die echte Windows-Version
#   tests/corpus/run.sh --update        expected.txt aus der Mac-Version neu schreiben
#                                       (danach den Diff Zeile für Zeile lesen!)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
[ -d "$ROOT/dist/macos/GrindGuard" ] || "$ROOT/tools/build.sh" --no-zip > /dev/null
T=$(mktemp -d "${TMPDIR:-/tmp}/ggcorpus.XXXXXX")
trap 'rm -rf "$T"' EXIT
FAIL=0

cp -R "$ROOT/dist/macos/GrindGuard/app" "$T/mac"
cp "$HERE/websites.txt" "$T/mac/config/websites.txt"
GRIND_TEST_LOCALE=${GRIND_TEST_LOCALE:-C.UTF-8} HOME="$T" bash "$T/mac/grind" __corpus "$HERE/urls.txt" > "$T/mac.txt"
if [ "${1:-}" = "--update" ]; then
    cp "$T/mac.txt" "$HERE/expected.txt"
    echo "expected.txt neu geschrieben ($(wc -l < "$T/mac.txt" | tr -d ' ') Adressen). Jetzt: git diff tests/corpus/expected.txt"
fi
if diff -u "$HERE/expected.txt" "$T/mac.txt" > "$T/mac.diff"; then
    echo "ok    Mac: $(wc -l < "$T/mac.txt" | tr -d ' ') Adressen wie erwartet"
else
    echo "FAIL  Mac weicht ab:"; cat "$T/mac.diff"; FAIL=1
fi

python3 "$ROOT/tests/windows/mirror.py" "$HERE/websites.txt" "$HERE/urls.txt" > "$T/mirror.txt"
if diff -u "$HERE/expected.txt" "$T/mirror.txt" > "$T/mirror.diff"; then
    echo "ok    Windows-Nachbau (Python): gleich"
else
    echo "FAIL  Windows-Nachbau weicht ab:"; cat "$T/mirror.diff"; FAIL=1
fi

if [ -n "${GG_PWSH:-}" ]; then
    cp -R "$ROOT/dist/windows/GrindGuard-Windows/app" "$T/win"
    cp "$HERE/websites.txt" "$T/win/config/websites.txt"
    "$GG_PWSH" -NoProfile -ExecutionPolicy Bypass -File "$T/win/grindguard.ps1" __corpus "$HERE/urls.txt" | tr -d '\r' > "$T/win.txt"
    if diff -u "$HERE/expected.txt" "$T/win.txt" > "$T/win.diff"; then
        echo "ok    Windows (PowerShell): gleich"
    else
        echo "FAIL  Windows (PowerShell) weicht ab:"; cat "$T/win.diff"; FAIL=1
    fi
fi
exit $FAIL
