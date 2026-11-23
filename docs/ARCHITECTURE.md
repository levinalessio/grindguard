# Architecture (1.3)

GrindGuard 1.3 consists of two small programs with the same behavior: a POSIX shell script for macOS and a PowerShell script for Windows. They share no code. They share the config format, the default lists (`shared/`) and a test corpus that pins down every decision of the rule engine.

```
shared/            default lists (websites, quotes) + update metadata      → copied into both packages
macos/             grind (shell), lib/overlay.js (lock screen), install.sh, config, LIESMICH.txt
windows/           grindguard.ps1, grind.cmd, install.ps1, INSTALLIEREN.cmd, config, LIESMICH.txt
tests/macos/       ~190 checks against mocked macOS commands + installer tests + overlay mock
tests/windows/     static PowerShell checker, title-rule tests, Python port of the Windows engine
tests/corpus/      106 URLs + expected decisions, shared by all engines
tools/build.sh     builds dist/ (CRLF conversion for Windows, zips, SHA256SUMS)
```

## On disk after installing

| | macOS | Windows |
|---|---|---|
| Program | `~/GrindGuard/grind`, `~/GrindGuard/lib/overlay.js` | `%USERPROFILE%\GrindGuard\grindguard.ps1`, `grind.cmd` |
| Config | `~/GrindGuard/config/*.txt` | `%USERPROFILE%\GrindGuard\config\*.txt` |
| State | `~/GrindGuard/state/` | `%USERPROFILE%\GrindGuard\state\` |
| Autostart | LaunchAgent `~/Library/LaunchAgents/com.grindguard.agent.plist` (`RunAtLoad`, `KeepAlive`, `ThrottleInterval 10`, `LimitLoadToSessionType Aqua`) | `HKCU\…\CurrentVersion\Run\GrindGuard` |
| Rights | your user, no admin | your user, no admin |

`state/` holds `ausrutscher.log` (one line per slip), `grindguard.log` (errors, rotated at 512 KB), `status.txt` (heartbeat, detection method, browser permissions, pause/focus end), `daemon.pid`, `pause_bis`, `fokus_bis` and `fokus/` (the frozen copy of the lists during a focus session).

## The loop

```
every INTERVALL (default 1 s):
  every 15 rounds: reload the four config files
  front app  ← lsappinfo (macOS) / GetForegroundWindow (Windows)
  app in apps.txt?          → close app → punish
  browser?  url ← AppleScript per browser family (3 s timeout) / UI Automation
            url unreadable? → Windows: window-title rules; macOS: record missing permission
            decide(url)     → blocked → close tab → punish
  otherwise remember this app as "last good"
  every 10 rounds: write status.txt
```

**Closing.** On macOS the tab is closed via AppleScript, and only if it still shows exactly the blocked URL. The URL is passed as an argument, never interpolated into the script. On Windows GrindGuard sends Ctrl+W to the browser window. Apps get a normal quit first (`kill` on macOS, `CloseMainWindow` on Windows). A force-quit follows only with `HART_BEENDEN=1`, and only after checking that the PID still belongs to the same program.

**Punish.** The lock time is `SPERRZEIT_START + (n-1) × SPERRZEIT_PLUS`, capped at `SPERRZEIT_MAX`, where `n` counts today's slips. With hunt detection (`JAGD=1`), three slips within 600 seconds jump straight to the maximum. Then come the lock screen, alarm sound and voice. After that, `ZURUECK=1` brings back the last allowed app (`open -b` on macOS; `SetForegroundWindow` on Windows, restoring the window first if it is minimized).

## The rule engine

`decide(url)` is the same on both platforms (see [RULES.md](RULES.md) for the user-facing syntax):

1. Only `http(s)` URLs and bare `host/path` strings are considered. Everything else is allowed.
2. **Host:** lowercase. Userinfo, port, `www.` and a trailing dot are stripped. A `*.translate.goog` proxy host is decoded back to the original host.
3. **Path:** runs of `/` are collapsed. Percent-encoded *unreserved* characters (`A–Z a–z 0–9 - . _ ~`) are decoded before `?`/`#`, so `/%73horts` equals `/shorts`. Encoded `/` (`%2F`) stays encoded.
4. **Allow list** (`+…`) first: a match wins, the URL is allowed.
5. **Search terms** (`suche: …`): the values of `q p query text wd search_query search s` are decoded (`+` → space, `%XX`), lowercased (ASCII) and searched for the term as a substring.
6. **Block list:** entries without `*` match the host or any subdomain plus an optional path prefix. Entries with `*` are globs over `host + path + query`.

The macOS engine is shell + `awk`. The Windows engine is PowerShell. `tests/windows/mirror.py` ports the Windows engine line by line to Python so that it can be tested on any machine. `tests/corpus/run.sh` feeds the same 106 URLs to all of them and diffs the result against `expected.txt`. Every behavior change shows up as a diff in that file.

## Lock screen

**macOS:** `osascript -l JavaScript lib/overlay.js` with the texts in a temp file. The script creates one borderless `NSWindow` per screen at screen-saver level that joins all Spaces and full-screen apps. A small `NSView` subclass (`GGRingView`) draws the countdown ring. The pump loop runs every 50 ms. If the overlay cannot start, GrindGuard falls back to a dialog. Without a working lock screen there is no punishment, so the fallback matters.

**Windows:** one borderless, top-most WinForms form per screen. `FormClosing` is cancelled until the time is up. The ring is a small C# control compiled at runtime with `Add-Type`. If that fails, a plain number label is shown. If no form can be shown at all, a `WScript.Shell` popup is the fallback.

Colors follow the tone: red for `brutal`, amber for `direkt`, blue for `ruhig`.

## Focus sessions

`grind fokus N` copies the four config files to `state/fokus/` and writes the end time to `state/fokus_bis`. While a session is running, the guard reads only the frozen copy and ignores pauses and active times. `pause`, `stop` and `uninstall` refuse to run. `grind notausstieg` needs a terminal, the exact sentence, and sets the end to at most 10 minutes from now. When the session ends, the snapshot is deleted and the live config applies again.

## Known limits of this architecture

These are the reasons for the 2.0 proposal in [ROADMAP.md](ROADMAP.md):

- **Polling:** one round per second costs CPU wake-ups and leaves up to a second of reaction time.
- **Reading URLs from outside:** AppleScript cannot read Firefox-based browsers on macOS, needs an Automation permission per browser and adds latency per call. UI Automation on Windows breaks whenever browsers change their UI.
- **Two engines** have to be kept identical by tests instead of by construction.
- **Scripts cannot be notarized,** and an unsigned script that closes windows and sends keystrokes looks suspicious to antivirus heuristics and Smart App Control.
- **No real UI:** settings live in text files, and status is a CLI command (on Windows also a tray icon).
