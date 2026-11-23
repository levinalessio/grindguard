# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/). Releases are Git tags `v<version>`, e.g. `v1.3`.

## [Unreleased]

## [1.3] – unreleased

First public release.

### Fixed
- **macOS 27:** launchd refuses to start a LaunchAgent whose plist carries the download quarantine flag, and GrindGuard used to swallow that error. The plist is now written atomically, the flag is removed from GrindGuard's own files only, and `grind start` and `grind doctor` show launchd's real error and state.
- **macOS 27:** `lsappinfo` now prints a header line (`"Terminal" ASN:…: (in front)`) before the requested value. GrindGuard read that line as the app name, never found the bundle ID, did not recognize browsers and therefore blocked no websites. Values are now read only from `KEY=value` lines, and if lsappinfo yields nothing usable, GrindGuard falls back to AppleScript.
- Path rules could be bypassed with doubled slashes (`//shorts`) or percent-encoded letters (`/%73horts`).
- Search terms were only found in the `q=` parameter. They are now also found in `p`, `query`, `text`, `wd`, `search_query`, `search` and `s` (Yahoo, Startpage, Yandex, Baidu, YouTube search, site searches), including `+` and `%XX` encoding.
- Overnight active times such as `22:00-02:00` checked the wrong weekday after midnight.
- Force-quitting is now optional (`HART_BEENDEN`). Before a kill, GrindGuard checks that the PID still belongs to the same program.
- PID file, LaunchAgent plist and installed scripts are replaced atomically, so a running guard never reads a half-written file.
- The error log is rotated at 512 KB.
- Updates no longer replace or switch on list entries silently. They show what is new and ask.

### Added
- **Focus sessions:** `grind fokus <minutes>` (5–240), also in the Windows tray menu. Lists are frozen, and `pause`, `stop` and `uninstall` are disabled. A session can be extended but not shortened. `grind notausstieg` ends one early after a typed sentence and a 10-minute delay.
- **Hunt detection:** three slips within 10 minutes give the maximum lock time immediately (`JAGD`).
- **Return to work:** after the lock, GrindGuard brings back the last allowed app or window (`ZURUECK`).
- **Tone presets:** `TON=brutal | direkt | ruhig`, plus `LAUTSTAERKE`.
- **New lock screen** on both platforms: dark full screen with a tone-dependent accent color, countdown ring, slip counter and footer, on every display. The fade-in respects *Reduce Motion* (macOS) and disabled UI effects (Windows).
- `grind check <url>` names the file and line number of the rule that matched.
- `grind doctor` reports launchd state, quarantine flags, which browsers really granted access, the running focus session and the tone.
- `state/status.txt` with a heartbeat, so `status` and `doctor` can tell a hung guard from a running one.
- Cross-platform URL corpus (106 cases) shared by macOS, Windows and a Python port of the Windows engine.
- CI on Linux, macOS and Windows (Windows PowerShell 5.1 parser, PSScriptAnalyzer, real PowerShell corpus run), and a release workflow with checksums and build provenance attestations.

### Changed
- Neutral default lists for the public: social media, video, streaming, converter detours and gambling are on. Shopping, news, games, image search and chats are included but switched off.
- Windows: apps are asked to close first (`CloseMainWindow`) and only killed after that.

## 1.0 – 1.2

Private prototypes for macOS, Windows and an iPhone Shortcuts guide. Not published.
