#!/bin/bash
# ============================================================================
#  GrindGuard installieren oder aktualisieren (macOS)
#
#  Im Terminal:   bash ~/Downloads/GrindGuard/install.sh
#
#  Kopiert alles nach ~/GrindGuard, richtet den Autostart ein und zeigt bei
#  der ersten Installation einmal die Test-Warnung. Erneut ausführen =
#  aktualisieren; deine eigenen Listen und Einstellungen bleiben erhalten.
#
#  Ohne Rückfragen (z. B. für Skripte):  GRIND_JA=1 bash install.sh  (0 = Neues ablehnen)
# ============================================================================

SRC=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
DEST="$HOME/GrindGuard"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Dieses Paket ist für macOS. Für Windows gibt es GrindGuard-Windows.zip."
    exit 1
fi
if [ ! -f "$SRC/app/grind" ] || [ ! -f "$SRC/app/lib/overlay.js" ]; then
    echo "Die Installationsdateien fehlen (Ordner 'app' neben install.sh)."
    echo "Bitte das ZIP vollständig entpacken und es noch einmal versuchen."
    exit 1
fi
if [ ! -f "$SRC/app/config/websites.txt" ]; then
    echo "Das ist der Quellcode von GitHub (\"Code > Download ZIP\"), nicht das fertige Paket."
    echo "Lade GrindGuard-macOS.zip hier herunter: https://github.com/levinalessio/grindguard/releases/latest"
    exit 1
fi

NEW_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SRC/app/grind" | head -n 1)
UPDATE=0
OLD_VERSION=""
if [ -f "$DEST/grind" ]; then
    UPDATE=1
    OLD_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$DEST/grind" | head -n 1)
fi

if [ "$UPDATE" -eq 1 ]; then
    echo "Aktualisiere GrindGuard ${OLD_VERSION:-?} -> $NEW_VERSION in $DEST …"
else
    echo "Installiere GrindGuard $NEW_VERSION nach $DEST …"
fi
if ! mkdir -p "$DEST/lib" "$DEST/config" "$DEST/state"; then
    echo "Kann $DEST nicht anlegen."
    exit 1
fi

# Programmdateien erst daneben kopieren und dann austauschen: Ein laufender
# Wächter liest nie eine halb kopierte Datei.
install_file() {        # $1 = Quelle, $2 = Ziel
    cp "$1" "$2.neu" && mv -f "$2.neu" "$2"
}
if ! install_file "$SRC/app/grind" "$DEST/grind" || ! install_file "$SRC/app/lib/overlay.js" "$DEST/lib/overlay.js"; then
    echo "Kopieren fehlgeschlagen."
    exit 1
fi
chmod 755 "$DEST/grind"
if [ -f "$SRC/LIESMICH.txt" ]; then
    cp "$SRC/LIESMICH.txt" "$DEST/LIESMICH.txt"
fi
# Die Download-Markierung nur von den Programmdateien entfernen. Ohne das würde
# macOS 27 den Autostart verweigern (die plist entsteht gleich bei "grind start").
for f in "$DEST/grind" "$DEST/lib/overlay.js"; do
    xattr -d com.apple.quarantine "$f" >/dev/null 2>&1
done

ask_yes() {     # $1 = Frage; Standard ist Ja. Ohne Terminal oder mit GRIND_JA=1: Ja.
    local a
    case ${GRIND_JA:-} in
        1) return 0 ;;
        0) return 1 ;;
    esac
    [ -t 0 ] || return 0
    printf '%s [J/n] ' "$1"
    a=""
    read -r a
    case $a in
        n|N|nein|Nein|no) return 1 ;;
    esac
    return 0
}

merge_websites() {      # neue Einträge der Vorlage anbieten, ohne deine Liste anzufassen
    local line added switched tmp new_lines switch_lines shown
    W="$DEST/config/websites.txt"
    new_lines=""
    switch_lines=""
    while IFS= read -r line; do
        case $line in
            ''|'#'*) continue ;;
        esac
        grep -qxF -e "$line" "$W" && continue
        if grep -qxF -e "#$line" "$W"; then
            # Stand in einer früheren Vorlage ausgeschaltet: darf eingeschaltet werden.
            # Hast du die Zeile selbst mit # ausgeschaltet, bleibt sie aus.
            if grep -qxF -e "#$line" "$SRC/app/update/standard-aus.txt" 2>/dev/null; then
                switch_lines="$switch_lines$line
"
            fi
            continue
        fi
        new_lines="$new_lines$line
"
    done < "$SRC/app/config/websites.txt"

    if [ -z "$new_lines$switch_lines" ]; then
        echo "  websites.txt: schon auf dem neuesten Stand"
        return 0
    fi
    echo "  websites.txt: Die neue Vorlage enthält Einträge, die bei dir fehlen:"
    shown=0
    printf '%s%s' "$new_lines" "$switch_lines" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        shown=$((shown + 1))
        [ "$shown" -le 15 ] && printf '      %s\n' "$line"
    done
    added=$(printf '%s%s' "$new_lines" "$switch_lines" | grep -c .)
    [ "$added" -gt 15 ] && printf '      … und %s weitere\n' "$((added - 15))"
    if ! ask_yes "  Übernehmen?"; then
        echo "  websites.txt: unverändert gelassen"
        return 0
    fi
    switched=0
    if [ -n "$switch_lines" ]; then
        printf '%s' "$switch_lines" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            tmp="$W.tmp"
            awk -v off="#$line" -v on="$line" '$0 == off { print on; next } { print }' "$W" > "$tmp" && mv -f "$tmp" "$W"
        done
        switched=$(printf '%s' "$switch_lines" | grep -c .)
        echo "  websites.txt: $switched bisher ausgeschaltete Einträge eingeschaltet"
    fi
    if [ -n "$new_lines" ]; then
        printf '\n# --- Ergänzt beim Update auf %s (zum Ausschalten # davor setzen) ---\n' "$NEW_VERSION" >> "$W"
        printf '%s' "$new_lines" >> "$W"
        added=$(printf '%s' "$new_lines" | grep -c .)
        echo "  websites.txt: $added neue Einträge ergänzt, deine eigenen Änderungen bleiben"
    fi
}

for f in einstellungen.txt websites.txt apps.txt sprueche.txt; do
    if [ ! -f "$DEST/config/$f" ]; then
        cp "$SRC/app/config/$f" "$DEST/config/$f"
    elif [ "$f" = websites.txt ]; then
        merge_websites
    else
        echo "  behalte deine bestehende $f"
    fi
done

echo
/bin/bash "$DEST/grind" start
started=$?

if [ "$UPDATE" -eq 0 ]; then
    echo
    /bin/bash "$DEST/grind" test
fi

echo
echo "------------------------------------------------------------------------"
if [ "$started" -ne 0 ]; then
    echo "Kopiert, aber der Hintergrunddienst läuft noch nicht (siehe Hinweis oben)."
elif [ "$UPDATE" -eq 1 ]; then
    echo "Update fertig. GrindGuard $NEW_VERSION läuft schon mit den neuen Listen."
    echo
    echo "Neu: Fokus-Sitzungen (grind fokus 50) und Regel-Erklärung (grind check ADRESSE)."
    exit 0
else
    echo "Fertig. GrindGuard läuft im Hintergrund und startet bei jeder Anmeldung mit."
fi
if [ "$UPDATE" -eq 0 ]; then
    cat <<EOF

Jetzt noch einmalig:
  1. Wechsle in deinen Browser (Safari, Chrome …). macOS fragt dann, ob "bash"
     oder "osascript" den Browser steuern darf – mit "Erlauben" bestätigen.
     Ohne dieses OK kann GrindGuard keine Websites sehen.
     (Die Rückfrage kommt einmal pro Browser, beim ersten Benutzen nach der Installation.)
  2. Meldet macOS ein neues Hintergrundobjekt namens "bash": Das ist GrindGuard.
  3. Kontrolle:  $DEST/grind doctor

Fokus-Sitzung starten:  $DEST/grind fokus 50
Listen anpassen:        $DEST/grind edit
Alle Befehle:           $DEST/grind help
Anleitung (auch fürs iPhone):  $DEST/LIESMICH.txt
EOF
fi
