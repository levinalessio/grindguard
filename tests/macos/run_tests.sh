#!/bin/bash
# shellcheck disable=SC1111,SC2254  # „…“ sind Teil der erwarteten Ausgabe, die case-Muster sind absichtlich Globs
# Testlauf mit simulierten macOS-Befehlen.
# Aufruf:  SH="dash" ./run_tests.sh      (oder SH="bash", SH="bash --posix")
SH=${SH:-bash}
HERE=$(cd "$(dirname "$0")" && pwd)
APP="${GG_APP:-$HERE/../../dist/macos/GrindGuard/app}"
BIN="$HERE/bin"
PASS=0
FAIL=0
TODAY=$(date +%Y-%m-%d)

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
check() { # $1 = Beschreibung, $2 = erwartet, $3 = tatsaechlich
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "erwartet [$2], bekommen [$3]"; fi
}
count() { grep -c -- "$1" "$2" 2>/dev/null; }
# Langsame Rechner (z. B. CI-Runner): GG_TEST_SLOW=2 verdoppelt alle Wartezeiten der Tests.
SLOW=${GG_TEST_SLOW:-1}
nap() { sleep "$(awk -v a="$1" -v f="$SLOW" 'BEGIN { printf "%.2f", a * f }')"; }
wait_gone() {   # $1 = PID, $2 = höchstens so viele Viertelsekunden warten; gibt 1 aus, wenn weg
    local i=0
    while kill -0 "$1" 2>/dev/null && [ "$i" -lt "$2" ]; do sleep 0.25; i=$((i + 1)); done
    kill -0 "$1" 2>/dev/null || echo 1
}

setup() {
    T=$(mktemp -d "${TMPDIR:-/tmp}/ggtest.XXXXXX")
    cp -R "$APP" "$T/app"
    export MOCK_DIR="$T/mock"
    mkdir -p "$MOCK_DIR/apps" "$T/app/state"
    : > "$MOCK_DIR/events.log"
    : > "$MOCK_DIR/osascript.log"
    printf 'Anna                de_DE    # Hallo! Ich heisse Anna.\nSamantha            en_US    # Hello!\n' > "$MOCK_DIR/voices"
    printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nSPERRZEIT_PLUS=1\nSPERRZEIT_MAX=5\nJAGD=0\n' > "$T/app/config/einstellungen.txt"
    echo 1 > "$MOCK_DIR/overlay_sleep"
    EV="$MOCK_DIR/events.log"
    STR="$T/app/state/ausrutscher.log"
    GLOG="$T/app/state/grindguard.log"
}
set_app() { # $1 = ASN wie von "front" gemeldet, $2 = Bundle-ID, $3 = Name, $4 = PID, $5 = ASN-Form fuer "info"
    local spec f
    echo "$1" > "$MOCK_DIR/front_asn"
    spec=${5:-$1}
    f="$MOCK_DIR/apps/$(printf '%s' "$spec" | tr ':/ ' '___')"
    echo "$2" > "$f.bundleid"
    echo "$3" > "$f.name"
    [ -n "$4" ] && echo "$4" > "$f.pid"
    return 0
}
# Feste Testliste: prueft die Regel-Engine unabhaengig von der mitgelieferten Vorlage
test_sites() {
    cat > "$T/app/config/websites.txt" <<'EOF'
# Testliste
youtube.com
instagram.com
x.com
reddit.com
tiktok.com
netflix.com
twitch.tv
beispiel-musik.example
example.org/shorts
google.com/search*udm=7*
google.com/search*udm=2*
*mp3*/*
*.bet/*
suche: mp3
suche: meme

+music.youtube.com
EOF
}
grind() { GRIND_TEST_BIN="$BIN" GRIND_TEST_LOCALE=${GRIND_TEST_LOCALE:-C.UTF-8} HOME="$T" $SH "$T/app/grind" "$@"; }
start() {
    GRIND_TEST_BIN="$BIN" GRIND_TEST_LOCALE=${GRIND_TEST_LOCALE:-C.UTF-8} HOME="$T" $SH "$T/app/grind" run > "$T/out.log" 2>&1 &
    DPID=$!
}
stop() {
    kill "$DPID" 2>/dev/null
    wait "$DPID" 2>/dev/null
    if [ -s "$T/out.log" ]; then bad "keine Shell-Fehlermeldungen" "$(head -3 "$T/out.log")"; fi
    rm -rf "$T"
}

echo "=== Shell: $SH ==="

echo "1. Blockierte Website in Safari: Tab zu, Warnung, Zaehler, Eskalation"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/watch?v=1" > "$MOCK_DIR/url"
echo "https://github.com/" > "$MOCK_DIR/url_next"
start; nap 4
check "Tab wurde geschlossen" 1 "$(count 'CLOSETAB https://www.youtube.com/watch?v=1' "$EV")"
check "eine Warnung, 3 Sekunden" 1 "$(count 'OVERLAY secs=3 ' "$EV")"
check "Ueberschrift STOPP" 1 "$(count 'text=\[STOPP\.|' "$EV")"
check "Detailzeile nennt die Seite" 1 "$(count 'youtube.com wurde geschlossen. Erster Ausrutscher' "$EV")"
check "ein Eintrag im Protokoll" 1 "$(count "^$TODAY .*|web|youtube.com\$" "$STR")"
check "Stimme: Anna, sagt Stopp" 1 "$(count 'SAY -v Anna Stopp\. ' "$EV")"
check "Alarmton" 1 "$(count 'AFPLAY ' "$EV")"
check "Safari-Vokabular (current tab)" 1 "$(grep -c 'current tab' "$MOCK_DIR/osascript.log" | awk '{print ($1 > 0)}')"
nap 2
check "erlaubte Seite danach: keine weitere Warnung" 1 "$(count 'OVERLAY' "$EV")"
echo "https://x.com/home" > "$MOCK_DIR/url"
nap 4
check "zweiter Ausrutscher: 4 Sekunden" 1 "$(count 'OVERLAY secs=4 ' "$EV")"
check "Ueberschrift SCHON WIEDER" 1 "$(count 'text=\[SCHON WIEDER\.|' "$EV")"
check "zwei Eintraege im Protokoll" 2 "$(count "^$TODAY" "$STR")"
echo "https://www.reddit.com/r/all" > "$MOCK_DIR/url"; nap 4
echo "https://www.tiktok.com/" > "$MOCK_DIR/url"; nap 5
check "dritter und vierter Ausrutscher: Obergrenze 5 Sekunden" 2 "$(count 'OVERLAY secs=5 ' "$EV")"
check "Ueberschrift NR. 4 HEUTE" 1 "$(count 'text=\[NR\. 4 HEUTE\.|' "$EV")"
check "Stimme sagt Nummer 4" 1 "$(count 'SAY -v Anna Ausrutscher Nummer 4 heute\.' "$EV")"
check "status zeigt 4 Ausrutscher" 1 "$(grind status | grep -c '4 Ausrutscher')"
check "Browser-Zugriff genau einmal bestaetigt" 1 "$(count 'Browser-Zugriff ok: Safari' "$GLOG")"
check "doctor zeigt die Erlaubnis" 1 "$(grind doctor | grep -c 'Browser-Erlaubnis:   erteilt für Safari')"
check "doctor verlangt dann keine Browser-Bestaetigung mehr" 0 "$(grind doctor | grep -c 'Fast fertig')"
stop

echo "2. Ausnahme und normale Seiten bleiben in Ruhe"
setup
set_app "ASN:0x0-0x1001:" com.google.Chrome "Google Chrome"
echo "https://music.youtube.com/watch?v=9" > "$MOCK_DIR/url"
start; nap 3
echo "https://docs.google.com/document/d/1" > "$MOCK_DIR/url"; nap 2
echo "missing value" > "$MOCK_DIR/url"; nap 2
check "keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
check "kein Tab geschlossen" 0 "$(count 'CLOSETAB' "$EV")"
check "Chrome-Vokabular (active tab)" 1 "$(grep -c 'active tab' "$MOCK_DIR/osascript.log" | awk '{print ($1 > 0)}')"
stop

echo "3. Blockiertes Programm wird beendet"
setup
sleep 300 & VICTIM=$!
set_app "ASN:0x0-0x2002:" com.valvesoftware.steam Steam "$VICTIM"
( while kill -0 "$VICTIM" 2>/dev/null; do sleep 0.1; done
  f="$MOCK_DIR/apps/ASN_0x0-0x3003_"; echo com.apple.finder > "$f.bundleid"; echo Finder > "$f.name"
  echo "ASN:0x0-0x3003:" > "$MOCK_DIR/front_asn" ) &
start; nap 4
if kill -0 "$VICTIM" 2>/dev/null; then bad "Programm wurde beendet"; kill "$VICTIM"; else ok "Programm wurde beendet"; fi
check "eine Warnung" 1 "$(count 'OVERLAY secs=3 ' "$EV")"
check "Detailzeile nennt das Programm" 1 "$(count 'Steam wurde geschlossen' "$EV")"
check "Protokoll: app|Steam" 1 "$(count '|app|Steam$' "$STR")"
stop

echo "4. Geschuetzte Programme werden nie beendet"
setup
sleep 300 & VICTIM=$!
printf 'Terminal\ncom.apple.Terminal\n' > "$T/app/config/apps.txt"
set_app "ASN:0x0-0x2002:" com.apple.Terminal Terminal "$VICTIM"
start; nap 3
if kill -0 "$VICTIM" 2>/dev/null; then ok "Terminal lebt noch"; else bad "Terminal lebt noch"; fi
check "keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
kill "$VICTIM" 2>/dev/null
stop

echo "5. Programm ohne Prozessnummer: per AppleScript beenden"
setup
printf 'Twitch\n' > "$T/app/config/apps.txt"
set_app "ASN:0x0-0x2002:" tv.twitch.desktop Twitch
start; nap 2.5
check "quit wurde geschickt" 1 "$(count 'QUIT .*tell application id "tv.twitch.desktop"' "$EV" | awk '{print ($1 > 0)}')"
stop

echo "6. Schliessen scheitert: nach drei Versuchen Ruhe statt Endlosschleife"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo error > "$MOCK_DIR/close_mode"
start; nap 9
check "genau zwei Warnungen, dann Schluss" 2 "$(count 'OVERLAY' "$EV")"
check "Warnung sagt: ist noch offen" 2 "$(count 'youtube.com ist noch offen' "$EV")"
check "Mitteilung an dich" 1 "$(count 'NOTIFY youtube.com liess sich nicht schliessen' "$EV")"
check "Fehler im Protokoll" 1 "$(count 'FEHLER: youtube.com liess sich dreimal nicht schliessen' "$GLOG")"
stop

echo "7. Tab inzwischen gewechselt: nichts schliessen, keine Warnung"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo changed > "$MOCK_DIR/close_mode"
start; nap 2.5
check "keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
stop

echo "8. Pause"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
check "pause meldet Dauer" 1 "$(grind pause 5 | grep -c 'Pause: 5 Minuten, bis [0-9][0-9]:[0-9][0-9] Uhr')"
start; nap 3
check "waehrend der Pause keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
check "status zeigt Pause" 1 "$(grind status | grep -c 'pausiert bis')"
grind weiter > /dev/null
nap 3
check "nach 'weiter' wieder scharf" 1 "$(count 'OVERLAY' "$EV")"
stop
setup
check "pause ohne Zahl wird abgelehnt" 1 "$(grind pause abc 2>&1 | grep -c 'als Zahl')"
check "pause ist auf 120 Minuten begrenzt" 1 "$(grind pause 999 | grep -c 'Maximal 120')"
rm -rf "$T"

echo "9. Abgelaufene Pause endet von selbst"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo $(( $(date +%s) + 2 )) > "$T/app/state/pause_bis"
start; nap 6
check "Warnung nach Pausenende" 1 "$(count 'OVERLAY' "$EV" | awk '{print ($1 > 0)}')"
check "Mitteilung: Pause vorbei" 1 "$(count 'NOTIFY Pause vorbei' "$EV")"
stop

echo "10. Fehlende Erlaubnis wird gemeldet (einmal), keine Warnung"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "33:54: execution error: Not authorized to send Apple events to Safari. (-1743)" > "$MOCK_DIR/url_error"
start; nap 4
check "keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
check "ein Protokolleintrag" 1 "$(count 'KEINE ERLAUBNIS' "$GLOG")"
check "eine Mitteilung" 1 "$(count 'NOTIFY Systemeinstellungen' "$EV")"
check "status nennt das Problem" 1 "$(grind status | grep -c 'KEINE ERLAUBNIS')"
check "doctor: nicht bestaetigt + Abhilfe" "1 1" "$(grind doctor | grep -c 'noch nicht bestätigt') $(grind doctor | grep -c 'tccutil reset AppleEvents')"
stop

echo "11. lsappinfo meldet die Nummer ohne zweites 0x (neuere macOS-Versionen)"
setup
set_app "ASN:0x0-4004:" com.apple.Safari Safari "" "ASN:0x0-0x4004:"
echo "https://www.instagram.com/" > "$MOCK_DIR/url"
start; nap 3
check "Warnung trotzdem" 1 "$(count 'OVERLAY' "$EV")"
check "Protokoll nennt lsappinfo" 1 "$(count 'App-Erkennung: lsappinfo' "$GLOG")"
stop

echo "11b. lsappinfo kennt nur die Schreibweise bundleID"
setup
touch "$MOCK_DIR/key_case_sensitive"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.instagram.com/" > "$MOCK_DIR/url"
start; nap 3
check "Warnung trotzdem" 1 "$(count 'OVERLAY' "$EV")"
stop

echo "11b2. macOS 27: lsappinfo schreibt eine Kopfzeile vor die Werte"
setup
touch "$MOCK_DIR/ls_header"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.instagram.com/" > "$MOCK_DIR/url"
start; nap 3
check "Warnung trotzdem" 1 "$(count 'OVERLAY' "$EV")"
check "doctor zeigt sauberen Namen + Bundle-ID" "0 1" "$(grind doctor | grep -c 'ASN:0x0-0x1001: (in front)') $(grind doctor | grep -c 'com.apple.Safari')"
stop

echo "11b3. macOS 27: lsappinfo liefert nur die Kopfzeile -> AppleScript"
setup
touch "$MOCK_DIR/ls_header_only"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "com.apple.Safari|Safari.app" > "$MOCK_DIR/as_front"
echo "https://www.instagram.com/" > "$MOCK_DIR/url"
start; nap 3
check "Warnung trotzdem" 1 "$(count 'OVERLAY' "$EV")"
check "kein Name mit ASN-Resten" 0 "$(grind doctor | grep -c 'in front')"
stop

echo "11c. Listen: Schreibweisen werden vereinheitlicht"
setup
printf '  HTTPS://WWW.Beispiel.CH/  \n+ https://www.erlaubt.beispiel.ch\nhttp://nur-pfad.ch/shorts/   # Kommentar\n+plus.ch\n\n#aus.ch\n' > "$T/app/config/websites.txt"
check "Grossschreibung, https, www, Schraegstrich" 1 "$(grind check beispiel.ch/x | grep -c '^BLOCKIERT')"
check "Unterseite blockiert" 1 "$(grind check sub.beispiel.ch | grep -c '^BLOCKIERT')"
check "Ausnahme mit Leerzeichen nach dem Plus" 1 "$(grind check erlaubt.beispiel.ch/a | grep -c '^erlaubt')"
check "Pfad-Eintrag trifft nur den Pfad" "1 1" "$(grind check nur-pfad.ch/shorts/abc | grep -c '^BLOCKIERT') $(grind check nur-pfad.ch/watch | grep -c '^erlaubt')"
check "auskommentierter Eintrag wirkt nicht" 1 "$(grind check aus.ch | grep -c '^erlaubt')"
check "status zaehlt 2 Websites" 1 "$(grind status | grep -c 'Blockiert: *2 Websites')"
printf 'Steam.app\n  EPIC Games Launcher  \n#Discord\n' > "$T/app/config/apps.txt"
check "status zaehlt 2 Apps" 1 "$(grind status | grep -c ', 2 Apps')"
rm -rf "$T"

echo "11d. Regel-Engine: Suchbegriffe, Muster, Umwege"
setup
test_sites
for u in \
  'B|https://www.google.com/search?client=safari&q=some+song+mp3&ie=UTF-8|mp3' \
  'B|https://www.google.com/search?q=songtitlemp3|mp3' \
  'B|https://www.google.com/search?q=%C2%A0song+title+mp3&start=10|mp3' \
  'B|https://www.google.com/search?q=funny+meme&udm=2|meme' \
  'B|https://duckduckgo.com/?q=artist+mp3&ia=web|mp3' \
  'B|https://www.bing.com/search?form=QBLH&q=MP3+Download|mp3' \
  'B|https://search.yahoo.com/search?p=artist+mp3&fr=yfp|mp3' \
  'B|https://www.startpage.com/do/search?query=artist+mp3|mp3' \
  'B|https://www.youtube.com/results?search_query=artist+mp3|mp3' \
  'B|https://www.google.com/search?q=%6D%70%33+download|mp3' \
  'B|https://www.google.com/search?q=%4D%50%33|mp3' \
  'B|https://www.google.com/search?q=lofi&udm=7|' \
  'B|https://www.youtube.com/shorts/abc123|' \
  'B|https://m.youtube.com/watch?v=1|' \
  'B|https://example.org/shorts/abc|' \
  'B|https://example.org//shorts/abc|' \
  'B|https://example.org/%73horts/abc|' \
  'B|https://example.org/%53HORTS/abc|' \
  'B|https://www33.musikseite.example/music-mp3/titel/|' \
  'B|https://titel.mp3.example/|' \
  'B|https://tracking.wetten.bet/go/x?e=5|' \
  'B|https://youtube-com.translate.goog/watch?v=1&_x_tr_sl=en|' \
  'B|https://www-instagram-com.translate.goog/reels/|' \
  'B|https://user:pw@www.reddit.com:443/r/all|' \
  'B|https://www.x.com./home|' \
  'E|https://example.org/watch|' \
  'E|https://example.org/%2fshorts/abc|' \
  'E|https://www.google.com/search?q=log4(0.25)&oq=mp3|' \
  'E|https://www.google.com/search?q=8+hoch+1+drittel|' \
  'E|https://www.google.com/search?q=lofi&udm=50|' \
  'E|https://www.google.com/maps/@47.27,9.53,15z|' \
  'E|https://music.youtube.com/search?q=mp3|' \
  'E|https://music.youtube.com/watch?v=abc&list=RDMM|' \
  'E|https://de-m-wikipedia-org.translate.goog/wiki/Logarithmus|' \
  'E|https://notreddit.com/|' \
  'E|https://www.3blue1brown.com/lessons/vectors|' \
  'E|https://ocw.mit.edu/courses/18-06sc-linear-algebra-fall-2011/|' \
  'E|https://claude.ai/new|'; do
    want=${u%%|*}; rest=${u#*|}; url=${rest%|*}; kw=${rest##*|}
    out=$(grind check "$url" | head -n 1)
    case $want in
        B) if [ -n "$kw" ]; then exp="BLOCKIERT*(Suchbegriff „${kw}“)"; else exp="BLOCKIERT*"; fi ;;
        E) exp="erlaubt*" ;;
    esac
    case $out in
        $exp) ok "$want $(printf '%s' "$url" | cut -c9-68)" ;;
        *) bad "$want $(printf '%s' "$url" | cut -c9-68)" "$out" ;;
    esac
done
check "status zaehlt Suchbegriffe" 1 "$(grind status | grep -c 'Apps, 2 Suchbegriffe')"
check "doctor zaehlt Suchbegriffe" 1 "$(grind doctor | grep -c 'Apps, 2 Suchbegriffe blockiert')"
OUT=$(grind check youtube.com/shorts/x)
check "check nennt Regel und Zeile" 1 "$(printf '%s' "$OUT" | grep -c 'Regel:    youtube.com  (websites.txt, Zeile 2)')"
OUT=$(grind check 'google.com/search?q=mp3+song')
check "check nennt den Suchbegriff mit Zeile" 1 "$(printf '%s' "$OUT" | grep -c 'Regel:    suche: mp3  (websites.txt, Zeile 15)')"
OUT=$(grind check music.youtube.com/watch)
check "check nennt die Ausnahme" 1 "$(printf '%s' "$OUT" | grep -c 'Ausnahme: +music.youtube.com  (websites.txt, Zeile 18)')"
OUT=$(grind check 'example.org//shorts/x')
check "check nennt die Pfad-Regel" 1 "$(printf '%s' "$OUT" | grep -c 'Regel:    example.org/shorts  (websites.txt, Zeile 10)')"
rm -rf "$T"

echo "11d2. Mitgelieferte Vorlage: Kernseiten gesperrt, Lernseiten offen"
setup
for u in \
  'B|https://www.instagram.com/|' \
  'B|https://www.tiktok.com/@x/video/1|' \
  'B|https://www.youtube.com/shorts/x|' \
  'B|https://www.netflix.com/browse|' \
  'B|https://stake.com/casino/home|' \
  'B|https://ytmp3s.example/#u=x|' \
  'B|https://www.google.com/search?q=lofi&udm=7|' \
  'E|https://music.youtube.com/watch?v=1|' \
  'E|https://www.wikipedia.org/|' \
  'E|https://claude.ai/new|' \
  'E|https://ocw.mit.edu/|' \
  'E|https://www.google.com/search?q=lineare+algebra|' \
  'E|https://lichess.org/learn|' \
  'E|https://www.amazon.de/|'; do
    want=${u%%|*}; rest=${u#*|}; url=${rest%|*}
    out=$(grind check "$url" | head -n 1)
    case $want in
        B) exp="BLOCKIERT*" ;;
        E) exp="erlaubt*" ;;
    esac
    case $out in
        $exp) ok "$want $(printf '%s' "$url" | cut -c9-60)" ;;
        *) bad "$want $(printf '%s' "$url" | cut -c9-60)" "$out" ;;
    esac
done
rm -rf "$T"

echo "11e. MP3-Suche im Browser: Tab zu, Warnung nennt die Suche"
setup
test_sites
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.google.com/search?client=safari&rls=en&q=song+title+mp3&ie=UTF-8&oe=UTF-8&safe=active" > "$MOCK_DIR/url"
echo "https://www.google.com/" > "$MOCK_DIR/url_next"
start; nap 3
check "Tab geschlossen" 1 "$(count 'CLOSETAB https://www.google.com/search?client=safari&rls=en&q=song+title+mp3' "$EV")"
check "Warnung nennt die Suche" 1 "$(count 'Suche nach „mp3“ wurde geschlossen\. Erster Ausrutscher' "$EV")"
check "Statistik: web|Suche nach „mp3“" 1 "$(count '|web|Suche nach „mp3“$' "$STR")"
check "stats listet die Suche" 1 "$(grind stats | grep -c '1×  Suche nach „mp3“')"
check "Overlay bekommt Zaehler und Ziel" 1 "$(count 'AUSRUTSCHER 01 · 3 S|Suche nach „mp3“|brutal|' "$EV")"
stop

echo "12. lsappinfo kaputt: Ausweichen auf AppleScript"
setup
touch "$MOCK_DIR/lsappinfo_broken"
echo "com.google.Chrome|Google Chrome.app" > "$MOCK_DIR/as_front"
echo "https://www.netflix.com/browse" > "$MOCK_DIR/url"
start; nap 3
check "Warnung" 1 "$(count 'OVERLAY' "$EV")"
check "Protokoll nennt applescript" 1 "$(count 'App-Erkennung: applescript' "$GLOG")"
stop

echo "13. lsappinfo und AppleScript kaputt: Ausweichen auf JXA"
setup
touch "$MOCK_DIR/lsappinfo_broken"
echo "com.brave.Browser|4242|Brave Browser" > "$MOCK_DIR/jxa_front"
echo "https://www.twitch.tv/x" > "$MOCK_DIR/url"
start; nap 3
check "Warnung" 1 "$(count 'OVERLAY' "$EV")"
check "Protokoll nennt jxa" 1 "$(count 'App-Erkennung: jxa' "$GLOG")"
stop

echo "14. Ausserhalb der aktiven Tage passiert nichts"
setup
OTHER=$(( $(date +%u) % 7 + 1 ))
printf 'INTERVALL=0.5\nAKTIVE_TAGE=%s\n' "$OTHER" > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
stop

echo "15. Ausserhalb der aktiven Uhrzeit passiert nichts; innerhalb schon"
setup
H=$(date +%H); H=${H#0}
FROM=$(printf '%02d:00' $(( (H + 2) % 24 ))); TO=$(printf '%02d:00' $(( (H + 3) % 24 )))
printf 'INTERVALL=0.5\nAKTIVE_ZEIT=%s-%s\n' "$FROM" "$TO" > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "ausserhalb ($FROM-$TO): keine Warnung" 0 "$(count 'OVERLAY' "$EV")"
stop
setup
FROM=$(printf '%02d:00' "$H"); TO=$(printf '%02d:00' $(( (H + 1) % 24 )))
[ "$TO" = "00:00" ] && TO="24:00"
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nAKTIVE_ZEIT=%s-%s\n' "$FROM" "$TO" > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "innerhalb ($FROM-$TO): Warnung" 1 "$(count 'OVERLAY' "$EV")"
stop

echo "16. Vollbild scheitert: Dialogfenster als Ersatz"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo 1 > "$MOCK_DIR/overlay_rc"; echo 0 > "$MOCK_DIR/overlay_sleep"
start; nap 3
check "Dialog wurde gezeigt" 1 "$(count 'DIALOG secs=3 head=\[Zur' "$EV")"
check "Fehler im Protokoll" 1 "$(count 'FEHLER: Vollbild-Warnung' "$GLOG")"
stop

echo "17. Dauer der Warnung: endet mit dem Fenster, nicht erst am Sicherheitsnetz"
setup
echo 2 > "$MOCK_DIR/overlay_sleep"
S=$(date +%s); OUT=$(grind test); E=$(date +%s)
D=$((E - S))
if [ "$D" -le 4 ]; then ok "grind test dauerte $D s (Fenster 2 s)"; else bad "grind test dauerte $D s (Fenster 2 s)"; fi
check "meldet Erfolg" 1 "$(printf '%s' "$OUT" | grep -c 'Vollbild-Warnung: funktioniert')"
check "Testtext" 1 "$(count 'OVERLAY secs=6 .*text=\[TESTALARM\.|' "$EV")"
echo 30 > "$MOCK_DIR/overlay_sleep"
S=$(date +%s); grind test > /dev/null; E=$(date +%s)
D=$((E - S))
if [ "$D" -ge 10 ] && [ "$D" -le 13 ]; then ok "haengendes Fenster wird nach 6+5 s beendet ($D s)"; else bad "haengendes Fenster wird nach 6+5 s beendet" "$D s"; fi
rm -rf "$T"

echo "18. Listen-Aenderung wirkt ohne Neustart"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.example.org/page" > "$MOCK_DIR/url"
start; nap 2
check "noch nicht blockiert" 0 "$(count 'OVERLAY' "$EV")"
echo "example.org" >> "$T/app/config/websites.txt"
nap 10
check "nach dem Eintragen blockiert" 1 "$(count 'OVERLAY' "$EV")"
stop

echo "19. Zweite Instanz startet nicht doppelt"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
start; nap 1.5
GRIND_TEST_BIN="$BIN" GRIND_TEST_LOCALE=${GRIND_TEST_LOCALE:-C.UTF-8} HOME="$T" $SH "$T/app/grind" run > "$T/zweite.log" 2>&1 &
ZP=$!
n=0; while kill -0 "$ZP" 2>/dev/null && [ "$n" -lt 18 ]; do sleep 0.5; n=$((n + 1)); done
kill "$ZP" 2>/dev/null; wait "$ZP" 2>/dev/null
OUT=$(cat "$T/zweite.log")
check "meldet: laeuft bereits" 1 "$(printf '%s' "$OUT" | grep -c 'bereits')"
check "PID-Datei gehoert der ersten Instanz" "$DPID" "$(cat "$T/app/state/daemon.pid")"
stop

echo "19b. Beenden mitten in einer Warnung: Waechter und Warnfenster sind sofort weg"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo 30 > "$MOCK_DIR/overlay_sleep"
printf 'INTERVALL=0.5\nSPERRZEIT_START=60\nSPERRZEIT_MAX=60\n' > "$T/app/config/einstellungen.txt"
start; nap 3
check "Warnung laeuft" 1 "$(count 'OVERLAY secs=60' "$EV")"
S=$(date +%s); kill "$DPID"; wait "$DPID" 2>/dev/null; E=$(date +%s)
if [ $((E - S)) -le 2 ]; then ok "Waechter beendet sich innerhalb von 2 s"; else bad "Waechter beendet sich innerhalb von 2 s" "$((E - S)) s"; fi
nap 0.5
check "Warnfenster-Prozess ist weg" 0 "$(pgrep -f "$T/app/lib/overlay.js" | wc -l | tr -d ' ')"
check "PID-Datei aufgeraeumt" 1 "$([ ! -f "$T/app/state/daemon.pid" ] && echo 1)"
rm -rf "$T"

echo "19c. Fremde PID-Datei wird beim Beenden nicht geloescht; verwaiste wird uebernommen"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo 999999 > "$T/app/state/daemon.pid"
start; nap 1.5
check "verwaiste PID-Datei uebernommen" "$DPID" "$(cat "$T/app/state/daemon.pid")"
echo 424242 > "$T/app/state/daemon.pid"
kill "$DPID"; wait "$DPID" 2>/dev/null
check "fremde PID-Datei bleibt stehen" 424242 "$(cat "$T/app/state/daemon.pid" 2>/dev/null)"
rm -rf "$T"

echo "20. Befehle: check, stats, status, help"
setup
check "check blockiert" 1 "$(grind check youtube.com/shorts | grep -c '^BLOCKIERT')"
check "check erlaubt" 1 "$(grind check wikipedia.org | grep -c '^erlaubt')"
check "stats ohne Daten" 1 "$(grind stats | grep -c 'Noch kein einziger')"
Y=$(date -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
printf '%s 10:00:00|web|youtube.com\n%s 11:00:00|web|youtube.com\n%s 09:00:00|app|Steam\n' "$TODAY" "$TODAY" "$Y" > "$STR"
OUT=$(grind stats)
check "stats: 7 Tageszeilen" 7 "$(printf '%s\n' "$OUT" | grep -c '^  [MDFS][oira] [0-9][0-9]\.[0-9][0-9]\.')"
check "stats: heute 2" 1 "$(printf '%s\n' "$OUT" | grep -c "$(date +%d.%m.)   2  ██")"
check "stats: Rangliste" 1 "$(printf '%s\n' "$OUT" | grep -c '  2×  youtube.com')"
check "status ohne Waechter" 1 "$(grind status | grep -c 'läuft NICHT')"
check "status zaehlt Listen" 1 "$(grind status | grep -Ec 'Blockiert: +[0-9]+ Websites, [0-9]+ Apps')"
check "help" 1 "$(grind help | grep -c 'grind pause')"
check "unbekannter Befehl -> Status 1" 1 "$(grind quatsch > /dev/null 2>&1; echo $?)"
rm -rf "$T"

echo "21. Kaputte Einstellungen bringen nichts zum Absturz"
setup
printf 'SPERRZEIT_START=abc\nSPERRZEIT_MAX=999999\nSPERRZEIT_PLUS=010\nINTERVALL=0\nAKTIVE_ZEIT=quatsch\nAKTIVE_TAGE=89\nSTIMME=ja\n=\n===\nFOO\n  # Kommentar\nINTERVALL = 0.5   # mit Kommentar\n' > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "Standardwert 10 Sekunden greift" 1 "$(count 'OVERLAY secs=10 ' "$EV")"
stop

echo "22. Jagd-Erkennung: dritter Umweg in 10 Minuten -> Maximum"
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nSPERRZEIT_PLUS=1\nSPERRZEIT_MAX=6\nJAGD=1\n' > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/watch?v=1" > "$MOCK_DIR/url"; start; nap 3.5
echo "https://www.reddit.com/r/all" > "$MOCK_DIR/url"; nap 4
echo "https://www.tiktok.com/" > "$MOCK_DIR/url"; nap 5
check "erste zwei normal (3 und 4 Sekunden)" "1 1" "$(count 'OVERLAY secs=3 ' "$EV") $(count 'OVERLAY secs=4 ' "$EV")"
check "dritter: Jagd, Maximum 6 Sekunden" 1 "$(count 'OVERLAY secs=6 .*text=\[JAGD ERKANNT\.|' "$EV")"
check "Zaehlerzeile nennt die Jagd" 1 "$(count 'AUSRUTSCHER 03 · 6 S · JAGD|' "$EV")"
check "Protokoll nennt die Jagd" 1 "$(count 'Jagd erkannt (3 in 10 Minuten)' "$GLOG")"
stop

echo "23. Ton: direkt und ruhig"
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nTON=ruhig\n' > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "ruhig: Ueberschrift" 1 "$(count 'text=\[KURZ ZURÜCK\.|' "$EV")"
check "ruhig: eingebauter ruhiger Spruch statt sprueche.txt" 1 "$(grep -c 'Kurz durchatmen\|Abgelenkt passiert jedem\|nächste Aufgabe\|Leg das Handy weg' "$EV" | awk '{print ($1 > 0)}')"
stop
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nTON=direkt\nALARMTON=1\nLAUTSTAERKE=40\n' > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "direkt: Ueberschrift" 1 "$(count 'text=\[ABLENKUNG GESPERRT\.|' "$EV")"
check "Alarm mit Lautstaerke 0.40" 1 "$(count 'AFPLAY -v 0.40 ' "$EV")"
stop

echo "24. Rueckkehr: nach der Sperre zurueck zur letzten erlaubten App"
setup
sleep 300 & VICTIM=$!
f="$MOCK_DIR/apps/com.apple.dt.Xcode"; echo 4711 > "$f.pid"
set_app "ASN:0x0-0x5005:" com.apple.dt.Xcode Xcode
start; nap 1.5
set_app "ASN:0x0-0x2002:" com.valvesoftware.steam Steam "$VICTIM"
nap 4
check "Steam beendet" 1 "$(kill -0 "$VICTIM" 2>/dev/null || echo 1)"
check "zurueck zu Xcode" 1 "$(count 'OPEN -b com.apple.dt.Xcode' "$EV")"
check "Protokoll: Zurueck zu Xcode" 1 "$(count 'Zurück zu Xcode' "$GLOG")"
kill "$VICTIM" 2>/dev/null
stop
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nZURUECK=0\n' > "$T/app/config/einstellungen.txt"
sleep 300 & VICTIM=$!
f="$MOCK_DIR/apps/com.apple.dt.Xcode"; echo 4711 > "$f.pid"
set_app "ASN:0x0-0x5005:" com.apple.dt.Xcode Xcode
start; nap 1.5
set_app "ASN:0x0-0x2002:" com.valvesoftware.steam Steam "$VICTIM"
nap 4
check "ZURUECK=0: keine Rueckkehr" 0 "$(count 'OPEN -b' "$EV")"
kill "$VICTIM" 2>/dev/null
stop

echo "25. Hartes Beenden nur mit HART_BEENDEN=1"
setup
VICTIM=$(sh -c 'trap "" TERM; while :; do sleep 1; done' > /dev/null 2>&1 & echo $!)
nap 0.3
set_app "ASN:0x0-0x2002:" com.valvesoftware.steam Steam "$VICTIM"
start
check "ignoriert SIGTERM -> hart beendet" 1 "$(wait_gone "$VICTIM" 48)"
kill -9 "$VICTIM" 2>/dev/null
stop
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nHART_BEENDEN=0\nJAGD=0\n' > "$T/app/config/einstellungen.txt"
VICTIM=$(sh -c 'trap "" TERM; while :; do sleep 1; done' > /dev/null 2>&1 & echo $!)
nap 0.3
set_app "ASN:0x0-0x2002:" com.valvesoftware.steam Steam "$VICTIM"
start; nap 4.5
check "HART_BEENDEN=0: Prozess lebt noch" 1 "$(kill -0 "$VICTIM" 2>/dev/null && echo 1)"
check "Warnung sagt: ist noch offen" 1 "$(count 'Steam ist noch offen' "$EV" | awk '{print ($1 > 0)}')"
kill -9 "$VICTIM" 2>/dev/null
stop

echo "26. Fokus-Sitzung: Listen eingefroren, pause/stop gesperrt, Notausstieg"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.example.org/" > "$MOCK_DIR/url"
echo "example.org" >> "$T/app/config/websites.txt"
OUT=$(grind fokus 30)
check "fokus meldet Ende" 1 "$(printf '%s' "$OUT" | grep -c 'Fokus-Sitzung: 30 Minuten, bis [0-9][0-9]:[0-9][0-9] Uhr')"
check "fokus friert die Listen ein" 1 "$([ -f "$T/app/state/fokus/websites.txt" ] && echo 1)"
check "fokus unter 5 Minuten abgelehnt" 1 "$(grind fokus 2 2>&1 | grep -c '5 bis 240')"
check "verkuerzen geht nicht" 1 "$(grind fokus 5 | grep -c 'Verkürzen geht nicht')"
check "pause gesperrt" "1 1" "$(grind pause 10 > /dev/null 2>&1; echo $?) $(grind pause 10 2>&1 | grep -c 'Fokus-Sitzung läuft bis')"
check "stop gesperrt" 1 "$(grind stop > /dev/null 2>&1; echo $?)"
check "uninstall gesperrt" 1 "$(grind uninstall > /dev/null 2>&1; echo $?)"
grep -v '^example.org$' "$T/app/config/websites.txt" > "$T/w"; cp "$T/w" "$T/app/config/websites.txt"
check "check nutzt die eingefrorene Liste" 1 "$(grind check example.org | grep -c '^BLOCKIERT')"
check "check nennt die eingefrorene Liste" 1 "$(grind check example.org | grep -c 'eingefrorene Liste der Fokus-Sitzung')"
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nAKTIVE_TAGE=%s\n' "$(( $(date +%u) % 7 + 1 ))" > "$T/app/config/einstellungen.txt"
echo $(( $(date +%s) + 600 )) > "$T/app/state/pause_bis"
start; nap 3
check "Sitzung: gesperrt trotz geaenderter Liste, Pause und anderem Tag" 1 "$(count 'OVERLAY' "$EV" | awk '{print ($1 > 0)}')"
check "status zeigt die Sitzung" 1 "$(grind status | grep -c 'FOKUS-SITZUNG bis')"
check "Notausstieg ohne Terminal abgelehnt" 1 "$(grind notausstieg < /dev/null 2>&1 | grep -c 'nur von Hand')"
check "Notausstieg mit falschem Satz abgelehnt" 1 "$(printf 'falsch\n' | GRIND_TEST_TTY=1 grind notausstieg 2>&1 | grep -c 'Nicht genau abgetippt')"
OUT=$(printf 'Ich breche meine Fokus-Sitzung bewusst ab\n' | GRIND_TEST_TTY=1 grind notausstieg 2>&1)
check "Notausstieg: endet erst nach 10 Minuten" 1 "$(printf '%s' "$OUT" | grep -c 'Die Sitzung endet um')"
E=$(cat "$T/app/state/fokus_bis"); N=$(date +%s)
check "Ende liegt 10 Minuten in der Zukunft" 1 "$([ $((E - N)) -ge 590 ] && [ $((E - N)) -le 600 ] && echo 1)"
echo $(( $(date +%s) - 1 )) > "$T/app/state/fokus_bis"
nap 2
check "nach dem Ende: Mitteilung" 1 "$(count 'NOTIFY Fokus-Sitzung vorbei' "$EV")"
check "nach dem Ende: Kopie weggeraeumt" 1 "$([ ! -d "$T/app/state/fokus" ] && echo 1)"
stop

echo "27. Zeitfenster ueber Mitternacht gehoert zum Vortag"
H=$(date +%H); H=${H#0}
if [ "$H" -ge 1 ] && [ "$H" -le 21 ]; then
    FROM=$(printf '%02d:00' $((H + 2))); TO=$(printf '%02d:00' $((H + 1)))
    TODAY_D=$(date +%u); YDAY=$(( (TODAY_D + 5) % 7 + 1 ))
    setup
    printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nAKTIVE_ZEIT=%s-%s\nAKTIVE_TAGE=%s\n' "$FROM" "$TO" "$YDAY" > "$T/app/config/einstellungen.txt"
    set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
    echo "https://www.youtube.com/" > "$MOCK_DIR/url"
    start; nap 3
    check "Fenster $FROM-$TO, nur Vortag aktiv: jetzt aktiv" 1 "$(count 'OVERLAY' "$EV" | awk '{print ($1 > 0)}')"
    stop
    setup
    printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nAKTIVE_ZEIT=%s-%s\nAKTIVE_TAGE=%s\n' "$FROM" "$TO" "$TODAY_D" > "$T/app/config/einstellungen.txt"
    set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
    echo "https://www.youtube.com/" > "$MOCK_DIR/url"
    start; nap 3
    check "Fenster $FROM-$TO, nur heute aktiv: jetzt NICHT aktiv" 0 "$(count 'OVERLAY' "$EV")"
    stop
else
    ok "uebersprungen (kurz vor Mitternacht)"
fi
setup
printf 'INTERVALL=0.5\nSPERRZEIT_START=3\nAKTIVE_ZEIT=07:00-07:00\n' > "$T/app/config/einstellungen.txt"
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
start; nap 3
check "gleiche Start- und Endzeit = ganzer Tag" 1 "$(count 'OVERLAY' "$EV" | awk '{print ($1 > 0)}')"
stop

echo "28. Status-Datei: Herzschlag, ausgesetzter Schutz, Browser-Erlaubnis"
setup
set_app "ASN:0x0-0x1001:" com.apple.Safari Safari
echo "https://www.youtube.com/" > "$MOCK_DIR/url"
echo error > "$MOCK_DIR/close_mode"
start; nap 9
check "status.txt mit PID" 1 "$(grep -c "^pid=$DPID\$" "$T/app/state/status.txt")"
check "status zeigt ausgesetzten Schutz" 1 "$(grind status | grep -c 'Schutz für youtube.com ausgesetzt bis')"
check "doctor nennt den Browser aus dem laufenden Waechter" 1 "$(grind doctor | grep -c 'Browser-Erlaubnis:   erteilt für Safari')"
stop

echo "29. __corpus fuer die plattformuebergreifenden Tests"
setup
test_sites
printf 'https://www.youtube.com/shorts/x\nhttps://www.google.com/search?q=a+mp3\n# Kommentar\nwikipedia.org\n' > "$T/c.txt"
check "Ausgabe" "B -|B mp3|E -" "$(grind __corpus "$T/c.txt" | tr '\n' '|' | sed 's/|$//')"
rm -rf "$T"

echo
printf 'Ergebnis (%s): %s bestanden, %s fehlgeschlagen\n' "$SH" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
