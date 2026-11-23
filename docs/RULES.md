# Rules reference

Your lists live in `~/GrindGuard/config/` (Windows: `%USERPROFILE%\GrindGuard\config\`). Changes are picked up within about 15 seconds. During a focus session the guard uses a frozen copy, and your edits apply when the session ends.

To find out what a rule does, ask GrindGuard:

```text
$ grind check youtube.com/shorts/abc
  …
  Regel:    youtube.com/shorts  (websites.txt, Zeile 34)
```

## websites.txt

One entry per line. Everything is case-insensitive. `#` starts a comment, even in the middle of a line. A leading `http://`, `https://` or `www.` and trailing slashes are ignored, so `https://www.YouTube.com/` is the same entry as `youtube.com`.

| Line | Blocks |
|---|---|
| `youtube.com` | `youtube.com` and every subdomain (`m.youtube.com`, `music.youtube.com`, …), every path |
| `youtube.com/shorts` | only paths that **start with** `/shorts`, on the site and its subdomains. It is a plain prefix, so `/shortsfeed` is blocked too. |
| `+music.youtube.com` | **exception**: never blocked, even if another line matches. Exceptions always win. |
| `google.com/search*udm=7*` | **pattern** over host + path + query: `*` = any text (including `/`), `?` = any single character |
| `suche: mp3` | **search term**: blocks any search whose text contains `mp3` |

### Order of evaluation

1. An exception (`+…`) matches → allowed.
2. A search term matches → blocked (the lock screen names the term, not the site).
3. A site or pattern matches → blocked.
4. Otherwise → allowed.

### What GrindGuard normalizes for you

These all count as `youtube.com/shorts/x`:

```text
https://WWW.YOUTUBE.COM/shorts/x          case
https://youtube.com./shorts/x             trailing dot
https://youtube.com:443/shorts/x          port
https://user@youtube.com/shorts/x         user info
https://youtube.com//shorts///x           doubled slashes
https://youtube.com/%73horts/x            percent-encoded letters
https://youtube-com.translate.goog/shorts/x   Google Translate proxy
```

Encoded slashes (`%2F`) stay encoded. Like the web itself, GrindGuard treats `/a%2Fb` as a different path from `/a/b`.

Only `http` and `https` addresses are checked. `about:`, `chrome://`, `file://`, `mailto:` and `ftp://` are never blocked.

### Search terms in detail

GrindGuard looks at these query parameters, which covers Google, Bing, DuckDuckGo, Ecosia, Brave, Kagi, Yahoo, Startpage, Yandex, Baidu, YouTube and most site searches:

```text
q  p  query  text  wd  search_query  search  s
```

The value is decoded (`+` and `%20` become spaces, `%XX` is decoded) and lowercased before the term is searched as a plain substring. `suche: lustige videos` therefore matches `q=lustige+videos+katzen`, but not `q=lustige+katzenvideos`.

Limits:
- Only those parameter names are checked. `?term=mp3` on some site is not.
- Lowercasing is ASCII-only. Write terms without umlauts, or in the exact case the search engine sends.
- The fragment (`#…`) and other parameters such as `oq=` are ignored.

### Patterns in detail

A pattern is matched against `host + path + query + fragment` after normalization, with no `www.` and no scheme. Examples:

```text
*casino*/*            any host or path containing "casino" followed by more path
*.bet/*               any .bet domain
google.com/search*udm=2*   Google image results
```

`*` also matches `/` and `?`. `*mp3*/*` therefore blocks `music.example/mp3-player/` as well. Test new patterns with `grind check` before you rely on them.

## apps.txt

One program per line.

- **macOS:** the name as shown in the menu bar (`Steam`) or the bundle ID (`com.valvesoftware.steam`). The bundle ID is the robust choice, because renaming the app does not change it.
- **Windows:** the process name without `.exe`, as shown in Task Manager → Details (`steam`, `Discord`). Windows that the blocked program opened (a game started from Steam, say) are closed too.

A blocked program is asked to quit first. If it is still running after a moment (macOS about 2 s, Windows about 1 s) and `HART_BEENDEN=1`, it is force-quit, and unsaved work in it is lost. Do not list programs you also work with.

Some programs are never touched, even if listed. On macOS these are Finder, Dock, the login window, System Settings, Terminal, iTerm, Activity Monitor and the screen saver. On Windows they are Explorer, Task Manager, Settings, the consoles (cmd, PowerShell, Windows Terminal) and the system processes.

## Windows: window-title fallback

When Windows cannot read a browser's address bar (some fullscreen modes, unusual browsers), GrindGuard falls back to built-in rules that recognize YouTube, Instagram, TikTok, Reddit, Netflix, Twitch, Facebook, X, Lichess, Ricardo, tutti, MP3 sites, Stake and Google searches by the window title. Each title rule maps to a URL, which then goes through your normal `websites.txt` rules, so your exceptions still win.

## sprueche.txt

One quote per line, `#` for comments. A new quote is shown with every slip. With `TON=ruhig` this file is not used. Your own lines work best: your goal, your deadline, why you are doing this.
