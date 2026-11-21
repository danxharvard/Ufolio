# Releasing Hush

Every release goes through the same checklist before it's tagged.

## 1. Security and bug review

Read through everything that changed, plus anything it touches, looking for:

- **Web content crossing into the app**: anything a page can trigger (dialogs, pop-ups, downloads,
  app links, permission requests, messages to native code). Pages must never be able to freeze
  Hush, open apps or files without asking, or fake where a request came from.
- **Secrets**: passwords and cards stay in the Keychain, are only filled after Touch ID or the Mac
  password, only into the top-level page, only on https, and only on the exact site they belong to.
  Values go to pages as arguments, never pasted into JavaScript.
- **Page scripts**: Hush's own scripts run in WebKit's isolated client world unless they must touch
  the page's JavaScript (Global Privacy Control). Pages can't see or call them.
- **Files**: download names are sanitised; downloads are quarantined so Gatekeeper checks them;
  updates are checked against GitHub's SHA-256 and the bundle ID and version before installing.
- **Crashes**: force-unwraps, threading, observers and timers that outlive their owners.

## 2. Speed and stability

- Nothing heavy on the main thread (file I/O, parsing, network).
- Page scripts are throttled and skip background tabs.
- Saves are batched (history, sessions, statistics).
- Check memory with several tabs open and closed.

## 3. Test

- `./scripts/build-app.sh` builds with no errors or warnings.
- Smoke test: start page, search suggestions, a few real sites, the ad counter, Settings.
- Anything new gets its own test before release.

## 4. Release

1. Put the new version in `VERSION` and note the changes in `CHANGELOG.md`.
2. Commit, then `git tag vX.Y.Z && git push origin main vX.Y.Z`.
3. GitHub Actions builds and publishes the DMG and update zip; installed copies update themselves.
