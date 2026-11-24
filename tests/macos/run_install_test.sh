#!/bin/bash
# Testet Installation, Autostart-Datei, start/stop/uninstall mit simuliertem macOS.
HERE=$(cd "$(dirname "$0")" && pwd)
PKG="${GG_PKG:-$HERE/../../dist/macos/GrindGuard}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "erwartet [$2], bekommen [$3]"; fi; }
# laeuft der Prozess wirklich noch? (ein noch nicht abgeraeumter Zombie zaehlt nicht)
alive() { case $(ps -p "$1" -o stat= 2>/dev/null) in ''|Z*) return 1 ;; esac; return 0; }

TMPBASE=${TMPDIR:-/tmp}; TMPBASE=${TMPBASE%/}   # macOS: TMPDIR endet auf "/"
T=$(mktemp -d "$TMPBASE/gginst.XXXXXX")
export MOCK_DIR="$T/mock"; mkdir -p "$MOCK_DIR/apps" "$T/Downloads"
: > "$MOCK_DIR/events.log"
echo 1 > "$MOCK_DIR/overlay_sleep"
printf 'Eddy (Deutsch (Deutschland)) de_DE    # Hallo!\nPetra               de_DE    # Hallo, ich bin Petra.\nSamantha            en_US    # Hello!\n' > "$MOCK_DIR/voices"
echo "ASN:0x0-0x1001:" > "$MOCK_DIR/front_asn"
echo com.apple.Terminal > "$MOCK_DIR/apps/ASN_0x0-0x1001_.bundleid"; echo Terminal > "$MOCK_DIR/apps/ASN_0x0-0x1001_.name"
cp -R "$PKG" "$T/Downloads/GrindGuard"
export GRIND_TEST_BIN="$HERE/bin_mac:$HERE/bin" GRIND_TEST_LOCALE=${GRIND_TEST_LOCALE:-C.UTF-8} HOME="$T"
G="$T/GrindGuard/grind"
EV="$MOCK_DIR/events.log"

echo "1. Installation"
OUT=$(PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$T/Downloads/GrindGuard/install.sh" 2>&1)
check "Hauptskript installiert und ausfuehrbar" 1 "$([ -x "$G" ] && echo 1)"
check "Warnungs-Skript installiert" 1 "$([ -f "$T/GrindGuard/lib/overlay.js" ] && echo 1)"
check "vier Konfigurationsdateien" 4 "$(find "$T/GrindGuard/config" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
check "Anleitung kopiert" 1 "$([ -f "$T/GrindGuard/LIESMICH.txt" ] && echo 1)"
check "meldet: laeuft" 1 "$(printf '%s' "$OUT" | grep -c 'GrindGuard läuft (PID [0-9]*) und startet')"
check "meldet: Fertig" 1 "$(printf '%s' "$OUT" | grep -c '^Fertig\. GrindGuard läuft im Hintergrund')"
check "meldet: Installiere 1.3" 1 "$(printf '%s' "$OUT" | grep -c '^Installiere GrindGuard 1\.3 nach')"
check "Liste ist die aktuelle Vorlage" 1 "$(cmp -s "$T/GrindGuard/config/websites.txt" "$PKG/app/config/websites.txt" && echo 1)"
check "Hilfslisten werden nicht mitinstalliert" 1 "$([ ! -e "$T/GrindGuard/update" ] && [ ! -e "$T/GrindGuard/config/standard-aus.txt" ] && echo 1)"
check "Test-Warnung gezeigt" 1 "$(grep -c 'OVERLAY secs=6 arch=arm64 text=\[TESTALARM' "$EV")"
check "Test meldet Erfolg" 1 "$(printf '%s' "$OUT" | grep -c 'Vollbild-Warnung: funktioniert')"
check "Stimme ohne Klammerzusatz bevorzugt (Petra)" 1 "$(grep -c 'SAY -v Petra Testalarm\.' "$EV")"
PL="$T/Library/LaunchAgents/com.grindguard.agent.plist"
check "Autostart-Datei vorhanden" 1 "$([ -f "$PL" ] && echo 1)"
check "Autostart-Datei ist gueltig und vollstaendig" ok "$(python3 - "$PL" "$G" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
assert d['Label'] == 'com.grindguard.agent', d
assert d['ProgramArguments'] == ['/bin/bash', sys.argv[2], 'run'], d['ProgramArguments']
assert d['RunAtLoad'] is True and d['KeepAlive'] is True
assert d['LimitLoadToSessionType'] == 'Aqua' and d['ProcessType'] == 'Interactive'
assert d['StandardOutPath'].endswith('/GrindGuard/state/launchd.log')
print('ok')
PY
)"
check "launchctl bootstrap aufgerufen" 1 "$(grep -c "LAUNCHCTL bootstrap gui/$(id -u) $PL" "$EV")"
sleep 1
check "status: laeuft" 1 "$(bash "$G" status | grep -c 'läuft (PID')"
check "doctor: nur die Browser-Erlaubnis steht noch aus" "1 0" "$(bash "$G" doctor | grep -c '^Fast fertig') $(bash "$G" doctor | grep -c 'Punkte zu beheben')"
check "doctor nennt macOS-Version und Methode" 2 "$(bash "$G" doctor | grep -Ec '^macOS: +27.1 \(arm64\)|ok über lsappinfo – vorne ist gerade: Terminal')"
P1=$(cat "$T/GrindGuard/state/daemon.pid")

echo "2. Erneut installieren behaelt eigene Listen"
echo "meineseite.ch" >> "$T/GrindGuard/config/websites.txt"
OUT=$(PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$T/Downloads/GrindGuard/install.sh" 2>&1)
check "meldet: behalte (drei Listen)" 3 "$(printf '%s' "$OUT" | grep -c 'behalte deine bestehende')"
check "meldet: websites.txt aktuell" 1 "$(printf '%s' "$OUT" | grep -c 'websites.txt: schon auf dem neuesten Stand')"
check "Update: keine zweite Test-Warnung" 1 "$(grep -c 'OVERLAY secs=6 arch=arm64 text=\[TESTALARM' "$EV")"
check "Update: meldet Versionen und fertig" "1 1" "$(printf '%s' "$OUT" | grep -c 'Aktualisiere GrindGuard 1\.3 -> 1\.3') $(printf '%s' "$OUT" | grep -c '^Update fertig\. GrindGuard 1\.3 läuft')"
check "eigener Eintrag noch da" 1 "$(grep -c '^meineseite.ch$' "$T/GrindGuard/config/websites.txt")"
check "nichts doppelt ergaenzt, wenn die Liste aktuell ist" 0 "$(grep -c 'Ergänzt beim Update' "$T/GrindGuard/config/websites.txt")"
grep -v -e '^reddit.com$' -e '^youtube.com$' "$T/GrindGuard/config/websites.txt" > "$T/w.txt"; echo "#tiktok.com" >> "$T/w.txt"; grep -v '^tiktok.com$' "$T/w.txt" > "$T/GrindGuard/config/websites.txt"
OUT=$(GRIND_JA=0 PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$T/Downloads/GrindGuard/install.sh" 2>&1)
check "Update zeigt die fehlenden Eintraege und fragt" "1 1 1" "$(printf '%s' "$OUT" | grep -c 'Einträge, die bei dir fehlen') $(printf '%s' "$OUT" | grep -c '^      reddit.com$') $(printf '%s' "$OUT" | grep -c '^      youtube.com$')"
check "abgelehnt: Liste unveraendert" "1 0" "$(printf '%s' "$OUT" | grep -c 'unverändert gelassen') $(grep -c '^youtube.com$' "$T/GrindGuard/config/websites.txt")"
OUT=$(PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$T/Downloads/GrindGuard/install.sh" 2>&1)
check "Update ergaenzt genau die fehlenden Eintraege" "1 1 1" "$(printf '%s' "$OUT" | grep -c 'websites.txt: 2 neue Einträge ergänzt') $(grep -c '^reddit.com$' "$T/GrindGuard/config/websites.txt") $(grep -c '^youtube.com$' "$T/GrindGuard/config/websites.txt")"
check "bewusst ausgeschaltete Eintraege bleiben aus" 0 "$(grep -c '^tiktok.com$' "$T/GrindGuard/config/websites.txt")"
sleep 1
sleep 1
P2=$(cat "$T/GrindGuard/state/daemon.pid")
check "Waechter wurde neu gestartet" 1 "$([ -n "$P2" ] && [ "$P1" != "$P2" ] && alive "$P2" && ! alive "$P1" && echo 1)"

echo "2b. Update einer aelteren Installation (eigene Liste bleibt, Neues wird ergaenzt)"
U=$(mktemp -d "$TMPBASE/ggupd.XXXXXX")
mkdir -p "$U/GrindGuard/lib" "$U/GrindGuard/config" "$U/GrindGuard/state"
sed 's/^VERSION=".*"$/VERSION="1.2"/' "$PKG/app/grind" > "$U/GrindGuard/grind"
for f in apps.txt einstellungen.txt sprueche.txt; do cp "$PKG/app/config/$f" "$U/GrindGuard/config/$f"; done
printf '# meine alte Liste\ninstagram.com\n#youtube.com\nmeineseite.ch\n#lichess.org\n#discord.com\nsuche: hausaufgaben loesung\n' > "$U/GrindGuard/config/websites.txt"
echo "Steam" >> "$U/GrindGuard/config/apps.txt"
# Paket-Kopie, in deren Vorlage lichess.org eingeschaltet ist (frueher ausgeschaltet geliefert)
cp -R "$T/Downloads/GrindGuard" "$U/paket"
sed -i.bak 's/^#lichess.org$/lichess.org/' "$U/paket/app/config/websites.txt"
OUT=$(HOME="$U" PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$U/paket/install.sh" 2>&1)
W="$U/GrindGuard/config/websites.txt"
check "meldet 1.2 -> 1.3" 1 "$(printf '%s' "$OUT" | grep -c 'Aktualisiere GrindGuard 1\.2 -> 1\.3')"
check "eigene Liste bleibt (kein Ersetzen)" "1 1 1" "$(grep -c '^meineseite.ch$' "$W") $(grep -c '^suche: hausaufgaben loesung$' "$W") $(grep -c '^# meine alte Liste$' "$W")"
check "selbst ausgeschaltet bleibt aus (youtube, discord)" "1 0 1 0" "$(grep -c '^#youtube.com$' "$W") $(grep -c '^youtube.com$' "$W") $(grep -c '^#discord.com$' "$W") $(grep -c '^discord.com$' "$W")"
check "frueher ausgeschaltet geliefert -> eingeschaltet" "1 0 1" "$(grep -c '^lichess.org$' "$W") $(grep -c '^#lichess.org$' "$W") $(printf '%s' "$OUT" | grep -c '1 bisher ausgeschaltete Einträge eingeschaltet')"
check "neue Eintraege ergaenzt" "1 1 1" "$(grep -c '^tiktok.com$' "$W") $(grep -c '^stake.com$' "$W") $(grep -c 'Ergänzt beim Update auf 1.3' "$W")"
check "andere Listen unangetastet" 1 "$(tail -n 1 "$U/GrindGuard/config/apps.txt" | grep -c '^Steam$')"
check "neue Version installiert" 1 "$(grep -c '^VERSION="1.3"' "$U/GrindGuard/grind")"
sleep 1
check "Waechter laeuft mit der neuen Version" 1 "$(HOME="$U" bash "$U/GrindGuard/grind" status | grep -c 'läuft (PID')"
check "neue Regeln aktiv" 1 "$(HOME="$U" bash "$U/GrindGuard/grind" check 'https://www.tiktok.com/' | grep -c '^BLOCKIERT')"
HOME="$U" bash "$U/GrindGuard/grind" uninstall > /dev/null
rm -rf "$U"

echo "2c. macOS 27: plist unter Quarantaene"
PL_Q="$PL.qtn"
bash "$G" stop > /dev/null
echo "0381;67000000;Safari;X" > "$PL_Q"
OUT=$(bash "$G" start); RC=$?
check "start entfernt die Quarantaene und startet" "0 1" "$RC $([ ! -f "$PL_Q" ] && echo 1)"
check "Waechter laeuft" 1 "$(bash "$G" status | grep -c 'läuft (PID')"
check "Programmdateien ohne Quarantaene" 1 "$([ ! -f "$G.qtn" ] && echo 1)"
touch "$MOCK_DIR/xattr_broken"
bash "$G" stop > /dev/null
echo "0381;67000000;Safari;X" > "$PL_Q"
OUT=$(bash "$G" start); RC=$?
check "laesst sich nicht entfernen: Status 1, Ursache im Klartext" "1 1" "$RC $(printf '%s' "$OUT" | grep -c 'steht unter Quarantäne')"
check "launchd-Zustand wird gezeigt" 1 "$(printf '%s' "$OUT" | grep -c 'launchd: state=not running exit=78: EX_CONFIG')"
check "doctor meldet die Quarantaene" 1 "$(bash "$G" doctor | grep -c 'Autostart-Datei:     FEHLER')"
rm -f "$MOCK_DIR/xattr_broken" "$PL_Q"
bash "$G" start > /dev/null; sleep 1
check "danach laeuft er wieder" 1 "$(bash "$G" status | grep -c 'läuft (PID')"
check "doctor zeigt den launchd-Zustand" 1 "$(bash "$G" doctor | grep -c '^launchd: *state=running exit=0')"
P2=$(cat "$T/GrindGuard/state/daemon.pid")

echo "3. stop / start / uninstall"
OUT=$(bash "$G" stop)
check "stop: Waechter sofort beendet" 1 "$(alive "$P2" || echo 1)"
check "stop: PID-Datei aufgeraeumt" 1 "$([ ! -f "$T/GrindGuard/state/daemon.pid" ] && echo 1)"
check "stop: Hinweis auf uninstall" 1 "$(printf '%s' "$OUT" | grep -c 'uninstall')"
check "status: laeuft nicht" 1 "$(bash "$G" status | grep -c 'läuft NICHT')"
touch "$MOCK_DIR/stuck_loaded"
OUT=$(bash "$G" stop); RC=$?
check "stop warnt, wenn macOS den Dienst nicht freigibt" "1 1" "$RC $(printf '%s' "$OUT" | grep -c 'nicht freigegeben')"
rm -f "$MOCK_DIR/stuck_loaded"
bash "$G" start > /dev/null; sleep 1
check "start: laeuft wieder" 1 "$(bash "$G" status | grep -c 'läuft (PID')"
touch "$MOCK_DIR/bootstrap_fails"
OUT=$(bash "$G" start); RC=$?
check "start scheitert: Status 1 und Hinweis auf Anmeldeobjekte" "1 1" "$RC $(printf '%s' "$OUT" | grep -c 'Anmeldeobjekte')"
check "start scheitert: zeigt die Meldung von launchctl" 1 "$(printf '%s' "$OUT" | grep -c 'launchctl meldet: Bootstrap failed: 5: Input/output error')"
rm -f "$MOCK_DIR/bootstrap_fails"
bash "$G" start > /dev/null; sleep 1
P3=$(cat "$T/GrindGuard/state/daemon.pid")
bash "$G" edit > /dev/null
check "edit oeffnet den Konfigurationsordner" 1 "$(grep -c "OPEN $T/GrindGuard/config" "$EV")"
OUT=$(bash "$G" uninstall)
check "uninstall: Autostart-Datei entfernt" 1 "$([ ! -f "$PL" ] && echo 1)"
check "uninstall: Waechter sofort beendet" 1 "$(alive "$P3" || echo 1)"
check "uninstall: Listen bleiben erhalten" 1 "$([ -f "$T/GrindGuard/config/websites.txt" ] && echo 1)"
check "keine Fehlermeldungen des Waechters" "" "$(grep -v 'nohup' "$MOCK_DIR/daemon.out" 2>/dev/null | head -3)"

echo "4. Unvollstaendiges Paket / falsches System"
mkdir -p "$T/kaputt"; cp "$PKG/install.sh" "$T/kaputt/"
OUT=$(PATH="$HERE/bin_mac:$HERE/bin:$PATH" bash "$T/kaputt/install.sh" 2>&1); RC=$?
check "fehlende Dateien: Abbruch mit Hinweis" "1 1" "$RC $(printf '%s' "$OUT" | grep -c 'vollständig entpacken')"
OUT=$(PATH="$HERE/bin_linux:$PATH" bash "$T/Downloads/GrindGuard/install.sh" 2>&1); RC=$?
check "kein macOS: Abbruch" "1 1" "$RC $(printf '%s' "$OUT" | grep -c 'Dieses Paket ist für macOS')"

rm -rf "$T"
echo
printf 'Ergebnis: %s bestanden, %s fehlgeschlagen\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
