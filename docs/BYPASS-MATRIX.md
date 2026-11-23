# Bypass matrix

Every blocker that runs on your own machine can be beaten by you. Pretending otherwise would be the corporate move. This is the honest list instead: every known way around GrindGuard 1.3, whether it works, and what 2.0 is supposed to do about it.

Found one that is missing? [Open a bypass report](../../../issues/new?template=bypass.yml). It is not a security issue, and we would rather know.

**Legend:** ✅ caught · 🟡 partly / slowed down · ❌ not caught · ⚙️ allowed on purpose

## Stopping GrindGuard itself

| Way around | macOS 1.3 | Windows 1.3 | Plan for 2.0 |
|---|---|---|---|
| `grind stop`, `pause`, `uninstall` | ⚙️ allowed. During a focus session: ✅ refused | same | Pause budget: pauses cost something and are counted |
| Kill the process (Activity Monitor, `kill`, Task Manager) | 🟡 launchd restarts it after about 10 s | ❌ stays dead until next login | Watchdog service; during a commit session a privileged helper (opt-in) |
| Remove the autostart (`launchctl bootout`, delete the plist / Run key) | ❌ | ❌ | Commit helper notices and restores it during a session |
| Kill the lock-screen process | ❌ ends the lock early | ❌ ends the lock early (Task Manager can be on top) | Lock screen inside the native app, guarded by the watchdog |
| Change the system clock | ❌ ends pauses and focus sessions early | ❌ same | Monotonic time for running sessions |
| Edit the lists during a focus session | ✅ frozen copy, edits apply afterwards | ✅ | same |
| Second user account, guest account | ❌ installed per user | ❌ | Optional system-wide install |

## Browsers

| Way around | macOS 1.3 | Windows 1.3 | Plan for 2.0 |
|---|---|---|---|
| Firefox, Zen, LibreWolf | ❌ address not readable; `grind doctor` warns | ✅ read via UI Automation | Extension; "unprotected browser = distraction" during sessions |
| A browser GrindGuard does not know | ❌ | ❌ unless the window title matches a title rule | Same policy: unknown browser = distraction in sessions |
| Deny the Automation permission (macOS) | ❌ sites no longer seen; `status`/`doctor` show it | n/a | Same policy |
| Run the browser as administrator (Windows) | n/a | ❌ GrindGuard cannot read or close elevated windows | Detect and treat as unprotected |
| Private / incognito window | 🟡 should work, not systematically tested | 🟡 same | Extension must be allowed in incognito, otherwise unprotected |
| Blocked page in a background tab (audio keeps playing) | ❌ only the active tab is checked | ❌ | Extension blocks the request itself |
| Video embedded on an allowed site, picture-in-picture | ❌ | ❌ | Extension blocks embeds (`sub_frame` requests) |
| Mirrors and alternative front ends (Invidious instances, other proxies) | 🟡 only those in your list; `youtube-nocookie.com`, `yewtu.be`, `piped.video` are in the default list | 🟡 same | Shared, updatable detour list |
| Google Translate as a proxy | ✅ | ✅ | ✅ |
| `//shorts`, `%73horts`, upper case, port, `user@` in the address | ✅ | ✅ | ✅ |
| Typing the address slowly, address bar focused | ✅ waits until the page has loaded | ✅ | Extension blocks before the first render |
| Search engine with a different parameter name (`?term=`) | ❌ | ❌ | Per-engine parser in the shared core |
| Search terms with umlauts or non-Latin script | 🟡 ASCII lowercasing only | 🟡 same | Unicode case folding in the core |

## Apps

| Way around | macOS 1.3 | Windows 1.3 | Plan for 2.0 |
|---|---|---|---|
| Rename or copy the app | ✅ if the list has the bundle ID | ❌ the match is by process name | Match by bundle ID / code signature |
| Web version of a blocked app (Discord in the browser) | ❌ unless the site is in `websites.txt` | ❌ same | Shared app ↔ site mapping |
| App that ignores a normal quit | ✅ force-quit (`HART_BEENDEN=1`) | ✅ same | Only for apps you explicitly mark |
| App running as administrator | n/a | ❌ cannot be closed | Commit helper (opt-in) |

## Outside the computer

| Way around | Status |
|---|---|
| Phone, tablet, second laptop | ❌ out of scope. The iPhone guide in `LIESMICH.txt` covers Screen Time and Shortcuts. |
| Virtual machine, remote desktop | ❌ |
| Muting the speakers | ⚙️ the lock still happens, only the alarm is silent |

## Why so much is ❌

1.3 watches the screen from the outside: it asks the OS which app is in front and asks the browser for its address. Anything that happens without passing through the front window stays invisible: background tabs, embeds, browsers that do not answer. 2.0 moves website blocking into a browser extension, which sees every request before it loads. It also treats a browser without the extension as a distraction while a session is running. See [ROADMAP.md](ROADMAP.md).
