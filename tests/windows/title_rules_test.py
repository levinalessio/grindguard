"""Prüft die Fenstertitel-Regeln aus grindguard.ps1 mit realistischen Titeln."""
import re, sys
import os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'windows', 'app', 'grindguard.ps1'), encoding='utf-8-sig').read()
end = re.search(r"\$script:TitleEnd = '([^']*)'", src).group(1)
rules = []
for m in re.finditer(r"@\{ P = (.+?); Url = '([^']+)' \}", src):
    expr, url = m.group(1), m.group(2)
    # PowerShell-Ausdruck 'a' + $script:TitleEnd + 'b' zusammensetzen
    tokens = re.findall(r"'(?:[^']|'')*'|\$script:TitleEnd", expr)
    pat = ''.join(end if t == '$script:TitleEnd' else t[1:-1].replace("''", "'") for t in tokens)
    rules.append((re.compile(pat.replace('(?<q>', '(?P<q>')), url))
assert len(rules) == 18, len(rules)

def title_url(t):
    t = re.sub('[​-‏‪-‮⁠﻿]', '', t)
    for rx, url in rules:
        m = rx.search(t)
        if m:
            q = m.groupdict().get('q')
            return url + (q.strip() if q else '')
    return None

cases = [
    ('Lofi Girl - YouTube - Google Chrome', 'https://www.youtube.com/'),
    ('(3) I Studied for 1 Hour… Can I Pass the Final? - YouTube - Google Chrome', 'https://www.youtube.com/'),
    ('YouTube - Google Chrome', 'https://www.youtube.com/'),
    ('#shorts Lets hire my first employee - YouTube und 6 weitere Seiten - Persönlich – Microsoft​ Edge', 'https://www.youtube.com/'),
    ('Video - YouTube — Mozilla Firefox', 'https://www.youtube.com/'),
    ('Night Blooming Jasmine - YouTube Music - Google Chrome', 'https://music.youtube.com/'),
    ('Kanal-Dashboard - YouTube Studio - Google Chrome', 'https://studio.youtube.com/'),
    ('some artist song mp3 - Google Suche - Google Chrome', 'https://www.google.com/search?q=some artist song mp3'),
    ('funny cat meme - Google Suche und 2 weitere Seiten - Persönlich – Microsoft​ Edge', 'https://www.google.com/search?q=funny cat meme'),
    ('office meme - Google Search - Google Chrome', 'https://www.google.com/search?q=office meme'),
    ('night blooming jasmine at DuckDuckGo — Mozilla Firefox', 'https://duckduckgo.com/?q=night blooming jasmine'),
    ('Netflix Aktie - Google Suche - Google Chrome', 'https://www.google.com/search?q=Netflix Aktie'),
    ('Instagram - Google Chrome', 'https://www.instagram.com/'),
    ('(2) Instagram', 'https://www.instagram.com/'),
    ('Beispiel (@beispiel) • Instagram-Fotos und -Videos - Google Chrome', 'https://www.instagram.com/'),
    ('TikTok - Make Your Day - Google Chrome', 'https://www.tiktok.com/'),
    ('beispiel video | TikTok - Google Chrome', 'https://www.tiktok.com/'),
    ('TikTok', 'https://www.tiktok.com/'),
    ('Reddit - Dive into anything - Google Chrome', 'https://www.reddit.com/'),
    ('Wie lernt ihr? : r/Matura - Google Chrome', 'https://www.reddit.com/'),
    ('Netflix - Google Chrome', 'https://www.netflix.com/'),
    ('Home - Netflix - Google Chrome', 'https://www.netflix.com/'),
    ('somestreamer - Twitch - Google Chrome', 'https://www.twitch.tv/'),
    ('Facebook - Google Chrome', 'https://www.facebook.com/'),
    ('(5) Facebook', 'https://www.facebook.com/'),
    ('Home / X - Google Chrome', 'https://x.com/'),
    ('Elon on X: "something" / X - Google Chrome', 'https://x.com/'),
    # weitere Seiten-Typen
    ('Lerne Schach - indem du spielst! • lichess.org - Google Chrome', 'https://lichess.org/'),
    ('Du bist am Zug - Spielen Stockfish level 8 • lichess.org - Google Chrome', 'https://lichess.org/'),
    ('Ricardo - Sicher kaufen & verkaufen mit über 5 Mio. Nutzern - Google Chrome', 'https://www.ricardo.ch/'),
    ('Deine Angaben - Ricardo - Google Chrome', 'https://www.ricardo.ch/'),
    ('Angebote von beispiel123 | Ricardo - Die Nummer 1 für Secondhand - Google Chrome', 'https://www.ricardo.ch/'),
    ('Gratis Inserate in deiner Nähe - tutti - Google Chrome', 'https://www.tutti.ch/'),
    ('artist song title - download free mp3 - MP3.pm - Google Chrome', 'https://mp3.pm/'),
    ('SONG TITLE - LABEL, Artist - mp3 download | lyric - Musikseite', 'https://mp3.pm/'),
    ('Download Song Title by Artist | Listen MP3 & WAV for FREE on example', 'https://mp3.pm/'),
    ('Song by Artist: Listen on Audiomack - Google Chrome', 'https://audiomack.com/'),
    ('Stake: Online Casino & Sportwetten - Spielen & Wetten Sie online - Google Chrome', 'https://stake.com/'),
    ('ricardo verkaufen ab wie alt - Google Suche - Google Chrome', 'https://www.google.com/search?q=ricardo verkaufen ab wie alt'),
    # muss frei bleiben
    ('Ricardo Kaká – Wikipedia - Google Chrome', None),
    ('Schach lernen von Grund auf - Claude - Google Chrome', None),
    ('Klasse_Mathematik-Notizbuch - Google Chrome', None),
    ('Teams und Kanäle | Klasse_Mathematik | Allgemein | Microsoft Teams', None),
    ('Lineare Algebra – Lernplan - Claude - Google Chrome', None),
    ('Wie man YouTube-Videos schneidet - Google Docs - Google Chrome', None),
    ('18.06SC Linear Algebra | MIT OpenCourseWare - Google Chrome', None),
    ('Neuer Tab - Google Chrome', None),
    ('Wurzeln & Logarithmen – Lernskript - Claude', None),
    ('Lehrmittel Reader - Google Chrome', None),
    ('Matrix-Vektor-Multiplikation: Zeilen- vs. Spaltenweise - Google Gemini', None),
    ('Netflix-Doku Kritik - Zeitung', None),
]
fail = 0
for title, want in cases:
    got = title_url(title)
    ok = got == want
    fail += not ok
    print(('ok    ' if ok else 'FAIL  ') + title[:75] + ('' if ok else f'\n        erwartet {want}, bekommen {got}'))
print(f'\n{len(cases) - fail} von {len(cases)} richtig')
sys.exit(1 if fail else 0)
