# Contributing

Issues and pull requests in English or German are both fine. The app's UI and the code comments are German.

## The one rule that matters

**macOS and Windows must decide every URL the same way.** The rule engine exists twice: in `macos/app/grind` (POSIX shell + awk) and in `windows/app/grindguard.ps1` (PowerShell). [`tests/windows/mirror.py`](tests/windows/mirror.py) is a line-by-line port of the Windows engine, so it can run anywhere. All three are checked against the same corpus:

```sh
tests/corpus/run.sh                        # Mac + Python mirror
GG_PWSH=powershell tests/corpus/run.sh     # plus real PowerShell, on Windows
```

If you change how URLs are parsed, normalized or matched:

1. Add the URLs that show the change to `tests/corpus/urls.txt`. Add tricky ones too, not just the happy path.
2. Change the Mac engine, rebuild and regenerate the expectation:
   ```sh
   tools/build.sh --no-zip && tests/corpus/run.sh --update
   git diff tests/corpus/expected.txt
   ```
3. Read that diff line by line. Every changed line is a behavior change for real users.
4. Make the same change in `grindguard.ps1` **and** in `mirror.py` until `tests/corpus/run.sh` is green.

## Platform constraints

**macOS (`macos/`)**
- Production runs `/bin/bash` 3.2. The script also has to run under `dash`, so stick to POSIX sh plus `local`. That means no arrays, no `[[ ]]`, no `${var,,}`.
- BSD userland: `sed -i.bak` instead of `sed -i`, `date -v` with a GNU fallback, no `grep -P`, `readlink -f`, `timeout` or `stat -c`.
- `lib/overlay.js` must stay ASCII-only. Write umlauts as `ü`. Some `osascript` versions read the file in the wrong encoding.
- Never `eval` anything from config files.

**Windows (`windows/`)**
- Target is **Windows PowerShell 5.1**, which ships with every Windows 10 and 11. No PowerShell 7 syntax: no `??`, `?.`, `&&`, `||` and no `ForEach-Object -Parallel`.
- `.ps1` files are UTF-8 **with BOM** and CRLF, otherwise 5.1 garbles umlauts. All other files under `windows/` use CRLF. `python3 tools/check_encoding.py` checks this, and `.gitattributes` keeps Git from breaking it.
- No external modules, no admin rights, no installers that need elevation.
- `python3 tests/windows/ps_check.py windows/app/*.ps1` catches syntax errors and typical 5.1 traps. CI additionally parses everything with the real 5.1 parser and runs PSScriptAnalyzer.

## Tests

```sh
tools/build.sh --no-zip
bash tests/macos/run_tests.sh                 # ~190 checks, mocked macOS commands
SH=dash bash tests/macos/run_tests.sh
bash tests/macos/run_install_test.sh          # installer, update merge, quarantine, launchd errors
node tests/macos/overlay_mock.js dist/macos/GrindGuard/app/lib/overlay.js
tests/corpus/run.sh
python3 tests/windows/title_rules_test.py
python3 tests/windows/ps_check.py windows/app/*.ps1
python3 tools/check_encoding.py
shellcheck macos/app/grind macos/install.sh tools/build.sh tests/corpus/run.sh
```

A bug fix comes with a test that fails without it.

## Texts and tone

The warning is supposed to hurt a little. It should not do damage.

- Attack the behavior, never the person's worth. *"You just chose against your goal"* is fine. Insults about intelligence, looks, body, mental health or identity are not.
- No references to self-harm, eating, weight or substances, not even as a joke.
- `TON=ruhig` must stay genuinely calm. Some people need that setting on bad days.
- New UI strings need all three tones (`brutal`, `direkt`, `ruhig`) and must fit on the lock screen at 1280×720.

## Privacy

Never commit real browsing histories, screenshots with real tabs, real names or account handles, not even in tests. Use `example.org`, `example.com` and invented names. If you report a bug with logs, read them first: `state/` contains which sites you visited when.

## Pull requests

- One topic per PR. Explain the user-visible change in the description.
- Add a line to `CHANGELOG.md` under *Unreleased*.
- New rule-template entries (`shared/config/websites.txt`) should be broadly relevant. Niche or regional sites go in commented out.
- Releases are cut by maintainers. See [docs/LAUNCH-CHECKLIST.md](docs/LAUNCH-CHECKLIST.md).
