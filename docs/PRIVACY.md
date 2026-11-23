# Privacy

GrindGuard opens no network connections. It has no account, no analytics, no crash reporter and no update check. You download new versions yourself.

## What it reads

- The **name and bundle ID / process name** of the app in front, about once a second.
- The **address of the active browser tab** if that app is a browser (AppleScript on macOS, UI Automation on Windows), or its **window title** on Windows when the address cannot be read.

It does not read page content, keystrokes, form fields, cookies, history, other tabs or other windows.

## What it stores

Everything is in `~/GrindGuard/state/` (Windows: `%USERPROFILE%\GrindGuard\state\`):

| File | Content | Kept |
|---|---|---|
| `ausrutscher.log` | One line per slip: date and time, `web` or `app`, and the **host name** (e.g. `youtube.com`) or the **app name**. For searches only the matching term from your list, never the full search. | until you delete it; `grind stats` reads it |
| `grindguard.log` | Start/stop, errors, which browsers granted access, which app GrindGuard returned you to | rotated at 512 KB |
| `status.txt` | Process ID, last heartbeat, detection method, browser permissions, end of pause or focus session | overwritten |
| `warnung.txt` (macOS) | The texts of the last lock screen | overwritten |
| `daemon.pid`, `pause_bis`, `fokus_bis`, `fokus/` | Runtime state, the frozen lists of a running focus session | deleted when no longer needed |

Full URLs and page titles are not written to disk.

## Deleting it

Empty the `state` folder. `grind uninstall` removes the autostart; then delete the `GrindGuard` folder in your home folder.

## If you share logs

Logs show which sites you were blocked from and when. Read them before attaching them to an issue, and cut what you do not want to share.
