# Security

## Reporting

Please report security problems **privately** via [GitHub's private vulnerability reporting](../../security/advisories/new) (Security tab → *Report a vulnerability*), not in a public issue. This is a volunteer project. Expect an answer within a week, and a fix as fast as we can manage.

Supported: the latest release only.

## What counts

GrindGuard reads URLs, window titles and config files and passes data to AppleScript, `awk`, `launchctl` and PowerShell. Things we want to hear about:

- A crafted URL, page title, window title or app name that makes GrindGuard execute code, write files or crash in a way a website could trigger.
- Config parsing that executes content (`einstellungen.txt`, `websites.txt`, …).
- The installer or updater writing outside `~/GrindGuard` and `~/Library/LaunchAgents` (or the Windows equivalents), following symlinks, or being raceable.
- GrindGuard storing or leaking more than its documented data ([docs/PRIVACY.md](docs/PRIVACY.md)).
- Anything wrong with release artifacts, checksums or the build workflow.

## What does not count

**Bypassing the blocker is not a security vulnerability.** GrindGuard is a self-control tool that runs with your own rights on your own machine. You are supposed to be able to stop it outside a focus session. Ways around it are still very welcome. Please open a normal issue with the *Bypass* template, and we track them publicly in [docs/BYPASS-MATRIX.md](docs/BYPASS-MATRIX.md).

## Verifying a download

Every release comes with `SHA256SUMS.txt` and a signed build provenance attestation made by GitHub Actions:

```sh
grep GrindGuard-macOS.zip SHA256SUMS.txt | shasum -a 256 -c   # macOS
gh attestation verify GrindGuard-macOS.zip --repo levinalessio/grindguard
```

On Windows: `Get-FileHash GrindGuard-Windows.zip -Algorithm SHA256` and compare the result with `SHA256SUMS.txt`.
