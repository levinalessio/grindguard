# Roadmap

> Status: **proposal.** The 2.0 architecture is not decided yet. Comments welcome in Discussions.

## Where 1.3 stands

1.3 is the last big release of the script version ("Classic"). It works, it is tested, and every limit it has is listed in [BYPASS-MATRIX.md](BYPASS-MATRIX.md). The remaining problems are structural: polling, reading URLs from outside the browser, two rule engines that have to be kept in sync by tests, scripts that cannot be notarized, and no real UI. More small features will not fix that.

Classic keeps getting bug fixes, list updates and bypass fixes as 1.3.x until 2.0 replaces it.

## 2.0 in one paragraph

A small **rule engine in Rust** runs natively in the guard and the CLI, and as WebAssembly in the browser extension, so a rule decides the same everywhere by construction. A **browser extension** (Chromium and Firefox first, Safari later) blocks sites before they load, including background tabs and embeds. **Event-driven guards** (NSWorkspace notifications on macOS, `SetWinEventHook` on Windows) replace once-a-second polling. A **Tauri 2 app** provides the menu bar / tray UI, settings, stats and a global command palette. While a session runs, a browser that does not report a working extension counts as a distraction. That closes the "just use another browser" hole without kernel extensions or a hosts file.

## Phases and gates

No dates. Each phase ships when its gate is met.

| Phase | Ships | Gate to the next phase |
|---|---|---|
| **0 · Classic 1.3** | Public alpha of the script version | CI green on Linux, macOS, Windows · tested by hand on real macOS 27 and Windows 11 · no personal data in the repo |
| **1 · Core** | `grindguard-core` crate + CLI (`grind check`, `grind corpus`), WASM build | 100 % identical decisions on the shared corpus · URL parser fuzzed · corpus extended with every bypass from the matrix |
| **2 · Extension** | Chromium + Firefox extension using `declarativeNetRequest`, native messaging to the guard | Blocks before the first render (automated browser test) · works in incognito when allowed · reports its health to the guard |
| **3 · Native guard + app** | Event-driven guards, Tauri menu bar / tray app, command palette, focus sessions that survive a reboot, stats heatmap | Guard idle < 0.5 % CPU and < 30 MB RAM · 95 % of app switches decided in < 100 ms · no data loss from default blocking |
| **4 · Signed release** | Developer ID + notarized `.dmg`, signed Windows installer, Homebrew cask, winget | Installs on a fresh Mac and Windows PC without security warnings |
| **later · Commit helper** | Optional privileged helper that guards autostart and the clock during commit sessions | Opt-in only, separately audited |

## Killer features for 2.0

1. **Return key:** after a lock, Enter takes you back to the last productive app or tab. GrindGuard measures how quickly you are back.
2. **Hunt detection** that also suggests a commit session.
3. **Commit sessions:** frozen rules, no stop or pause, they survive a reboot, and the emergency exit costs a waiting period plus a typed sentence.
4. **Allow mode:** during deep work, only your work sites are open.
5. **Explainable rules:** `grind check` shows the rule, the line and the exception that applied, and the app shows the same view.
6. **Command palette:** Cmd/Ctrl + Shift + G anywhere to start a session, block the current site, test a rule or request a pause.
7. **Patterns, not points:** a heatmap by hour and weekday, the day's first distraction, time to return. No badges and no leaderboard.
8. **Tone of your choice:** brutal, direct or calm. Brutal stays opt-in for new users.

## Not doing

- Cloud, accounts, AI coach, team dashboards, badges.
- Kernel extensions, firewall rules or the hosts file as the default mechanism.
- Hard-killing apps by default. Apps are asked to quit first and are only killed if you explicitly mark them that way.

## Open questions

- Apple Developer Program (99 USD/year) for notarization and the Safari extension: who pays, and from when?
- Windows code signing: SignPath Foundation (free for OSS, needs a track record and an OSI license) or a paid certificate?
- English UI: in Classic already, or only in 2.0?
- Default tone for new users: `direkt`?
