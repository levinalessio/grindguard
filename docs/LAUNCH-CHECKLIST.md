# Launch-Checkliste

Für Maintainer, deshalb auf Deutsch. Der Reihe nach abarbeiten. Was hier nicht abgehakt ist, ist nicht fertig.

## 1. Repo anlegen

- [ ] Öffentliches Repo `grindguard` anlegen. Vorher den Namen prüfen (Markenregister, App Store, bestehende Repos).
- [ ] Den Platzhalter `GITHUB_USER` durch deinen GitHub-Namen ersetzen. Der Release-Workflow bricht ab, solange er noch irgendwo steht:
  ```sh
  grep -rl GITHUB_USER README.md README.de.md SECURITY.md .github/ISSUE_TEMPLATE | xargs sed -i.bak "s/GITHUB_USER/DEINNAME/g" && find . -name '*.bak' -delete
  ```
- [ ] `LICENSE`: „GrindGuard contributors“ ist gültig. Deinen echten Namen nur eintragen, wenn er öffentlich sein soll.
- [ ] Erster Push: `git init && git add -A && git commit -m "GrindGuard 1.3" && git push`. `dist/` ist ignoriert.
- [ ] Prüfen, dass `.gitattributes` gewirkt hat: `python3 tools/check_encoding.py` auf einem frischen Klon.

## 2. Repo-Einstellungen

- [ ] *Security*: Private vulnerability reporting, Dependabot alerts und Secret scanning einschalten.
- [ ] *Rules* für `main`: Pull Request nötig, Status-Checks des CI nötig, kein Force-Push.
- [ ] *Actions → General*: Workflow-Rechte auf „Read repository contents“. Die Workflows fordern selbst an, was sie brauchen.
- [ ] *Environments*: `release` anlegen, Freigabe durch dich. Der Release-Workflow wartet dort auf dein OK.
- [ ] Discussions einschalten (Q&A, Ideen, Show & Tell).
- [ ] Topics: `focus`, `productivity`, `website-blocker`, `self-control`, `macos`, `windows`.
- [ ] Social Preview: echter Screenshot des Sperrbildschirms, 1280 × 640 PNG.

## 3. Echt testen – nicht verhandelbar

Das CI prüft gegen simulierte Befehle. Ob launchd auf macOS 27 die Datei wirklich lädt, sieht man nur auf einem echten Mac. Dein macOS 27.2.1 ist der wichtigste Testrechner, den es gibt.

- [ ] Release-ZIP mit **Safari** bzw. **Edge** herunterladen, damit die Download-Markierung drauf ist wie bei echten Nutzern.
- [ ] Mac: Update deiner bestehenden 1.2-Installation. Kommt die Merge-Abfrage? Bleiben deine Listen? Läuft er nach `grind start`?
- [ ] Mac: frische Installation in einem zweiten Benutzerkonto.
- [ ] `grind doctor` ohne Fehler, Automation-Erlaubnis für Safari und Chrome erteilt.
- [ ] Sperre für eine Website, eine `suche:`-Suche und eine App aus `apps.txt`: Ring, Ton, Stimme, Rückkehr zur letzten App.
- [ ] Zwei Bildschirme, eine App im Vollbild, heller und dunkler Modus, „Bewegung reduzieren“ an.
- [ ] `grind fokus 5`: `stop` und `pause` werden verweigert, der Notausstieg funktioniert, nach 5 Minuten ist die Sitzung vorbei.
- [ ] Neustart: Der Wächter läuft wieder (`grind status`).
- [ ] Windows 11: SmartScreen-Dialog, Tray-Menü, Fokus-Sitzung aus dem Tray, Edge + Chrome + Firefox, zwei Bildschirme.
- [ ] Screenshots für das README machen, ohne private Tabs, Namen oder Lesezeichen.

## 4. Release

- [ ] `CHANGELOG.md`: `## [1.3] – unreleased` bekommt das Datum.
- [ ] Version überall gleich: `VERSION="1.3"` in `macos/app/grind` und `'1.3'` in `windows/app/grindguard.ps1`. Der Workflow prüft das.
- [ ] Tag setzen: `git tag -a v1.3 -m "GrindGuard 1.3" && git push origin v1.3`
- [ ] Der Release-Workflow testet alles noch einmal, baut die ZIPs, `SHA256SUMS.txt` und die Build-Attestierung und legt einen **Entwurf** an. Durchlesen, dann *Publish release*.
- [ ] Prüfen: `gh attestation verify GrindGuard-macOS.zip --repo DEINNAME/grindguard`

## 5. Signieren

### macOS

- **1.3 (Skripte):** Notarisieren ist für Shell-Skripte nicht möglich und hier auch nicht nötig. Gatekeeper prüft kein Skript, das du im Terminal mit `bash` startest, und der Installer entfernt die Download-Markierung gezielt nur von GrindGuards eigenen Dateien.
- **Homebrew:** Seit Homebrew 5.0 sind unsignierte Casks abgekündigt, und `--no-quarantine` gibt es nicht mehr. Ein Cask lohnt sich deshalb erst mit einer signierten 2.0.
- **2.0 (.app):** Apple Developer Program, 99 USD pro Jahr. Damit: *Developer ID Application*-Zertifikat, Hardened Runtime, `xcrun notarytool submit --wait`, `xcrun stapler staple`. Ins CI kommen das Zertifikat (P12, base64) mit Passwort und ein App-Store-Connect-API-Schlüssel als Secrets der Environment `release`, nie als Repo-Secrets für alle Workflows.

### Windows

- **1.3:** Unsignierte Skripte aus dem Internet lösen SmartScreen aus („Trotzdem ausführen“). Mit Smart App Control werden sie blockiert. Das README sagt das offen.
- **Empfehlung: SignPath Foundation** (gratis für Open Source). Voraussetzungen: OSI-Lizenz (MIT erfüllt das), automatischer Build auf GitHub (gibt es), MFA für Maintainer und mindestens ein bereits veröffentlichtes Release. 1.3 erscheint also zuerst unsigniert, danach beantragen. Das Zertifikat lautet auf „SignPath Foundation“ und signiert auch `.ps1`-Dateien (Authenticode).
- Azure Artifact Signing steht Einzelpersonen nur in den USA und Kanada offen.
- Ein gekauftes Zertifikat geht auch, kostet aber jedes Jahr, und SmartScreen-Vertrauen entsteht trotzdem erst mit der Zeit.

## 6. Release-Notes (Vorlage)

```markdown
**GrindGuard 1.3**: erste öffentliche Version. macOS 13–27, Windows 10/11.

Neu: Fokus-Sitzungen, Jagd-Erkennung, Rückkehr zur Arbeit, neuer Sperrbildschirm, drei Tonarten.
Behoben: Start auf macOS 27 (Quarantäne-Markierung), Umgehung über //, %-Kodierung und andere Suchmaschinen.

Installieren: siehe README. Bekannte Grenzen: docs/BYPASS-MATRIX.md.
Prüfsummen: SHA256SUMS.txt · Herkunft: `gh attestation verify <zip> --repo DEINNAME/grindguard`
```

## 7. Community

- [ ] Labels anlegen: `bug`, `bypass`, `rules`, `macos`, `windows`, `good first issue`, `help wanted`.
- [ ] Ein Issue „Bekannte Umgehungen“ anpinnen, das auf die Bypass-Matrix verweist.
- [ ] In der ersten Woche jedes Issue innerhalb von 48 Stunden beantworten, auch wenn es nur „gesehen, schaue ich mir an“ ist.
- [ ] Zuerst deine Mitstudierenden: Sie haben schon ein Audit geschrieben. Bitte sie, die fünf härtesten Punkte als Issues einzutragen, dann sieht das Repo am ersten Tag lebendig und ehrlich aus.
- [ ] Danach einzeln und ohne Spam: *Show HN* (Titel: „Show HN: GrindGuard – closes distractions and locks your screen for a few seconds“), passende Subreddits (vorher die Regeln zu Eigenwerbung lesen), die Discord- oder Telegram-Gruppen deines Studiengangs.
- [ ] Die Grenzen offen nennen. Bei einem Tool, das Disziplin verspricht, ist die Bypass-Matrix das stärkste Vertrauenssignal, das du hast.
