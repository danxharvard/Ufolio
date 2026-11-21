# Hush Browser

A lightweight, native macOS web browser built on WebKit (the engine behind Safari).

- Calm, minimal, native interface with Day/Night themes, accent colours and start-page styles
- Address bar with live search suggestions (Google, DuckDuckGo, Bing, Brave Search or Ecosia)
- Bookmarks and a bookmarks bar (⌘D to bookmark, ⇧⌘B to show/hide, right-click to rename/move/remove)
- **Hush Guard**: built-in ad and tracker blocking, a blocked counter, per-site on/off,
  collapsing of empty ad spaces, cookie-banner hiding, and import of your own filter lists
  (EasyList, uBlock/Adblock Plus lists, hosts files, Safari content-blocker JSON)
- Privacy: third-party cookie blocking, HTTPS upgrade, Global Privacy Control, fraud warnings,
  per-site location/camera/microphone permissions, one-click clearing of website data
- Start page with Favourites and Frequently Visited, plus optional local weather
- Passwords & AutoFill (Keychain-backed, Touch ID): passwords, credit cards, your contact card
- History with address-bar suggestions, and import from Safari, Chrome, Brave, Edge, Arc, Vivaldi, Firefox
- Downloads list with progress
- Chrome extensions from the Chrome Web Store (macOS 15.4 or later)
- Updates itself from GitHub releases (Settings › Updates)
- Tabs (⌘T, ⌘W, ⇧⌘[ / ⇧⌘]), zoom, downloads, restore last session
- Under 3 MB, universal (Intel and Apple Silicon), macOS 13 or later

All settings live in **Hush Browser › Settings…** (⌘,).

## Install

Download `HushBrowser-<version>.dmg` from [Releases](https://github.com/danxharvard/hushbrowser/releases),
open it and drag **Hush Browser** into **Applications**.

The first time you open it, macOS says it can't verify Hush, because it isn't signed with a paid
Apple Developer ID. Click **Done**, open **System Settings › Privacy & Security**, scroll to
**Security** and click **Open Anyway** next to Hush Browser. You only do this once.

## Build from source

Needs Apple's Command Line Tools (`xcode-select --install`); Xcode itself is optional.

```bash
./scripts/build-app.sh
```

This produces `build/Hush Browser.app`, `build/HushBrowser-<version>.dmg` (the installer) and
`build/HushBrowser-<version>.zip` (what installed copies download to update themselves).

## Releasing an update

1. Go through [RELEASING.md](RELEASING.md) (security, bug and performance review), then put the new
   version number in `VERSION`, note the changes in `CHANGELOG.md` and commit.
2. Tag and push:

   ```bash
   git tag v0.3.0 && git push origin main v0.3.0
   ```

GitHub Actions (`.github/workflows/release.yml`) builds the app and publishes a release with the
DMG and the update zip. Installed copies check every few hours and install it the next time they
quit — or straight away from Settings › Updates.

## Project layout

| File | What it does |
| --- | --- |
| `Sources/HushApp.swift` | App entry point, menus and keyboard shortcuts |
| `Sources/BrowserWindow.swift` | Window layout, toolbar, page area, loading bar |
| `Sources/BrowserModel.swift` | A window's tabs |
| `Sources/BrowserTab.swift` | One tab: the WebKit view, navigation, pop-ups, downloads |
| `Sources/AddressBar.swift` | Address field and turning typed text into a URL or search |
| `Sources/Suggestions.swift` | Live search and bookmark suggestions |
| `Sources/TabStrip.swift` | The tab strip |
| `Sources/Bookmarks.swift` | Bookmark storage, bookmarks bar, site icons, start page |
| `Sources/SettingsStore.swift` | Every setting's key and default, plus search engines and other options |
| `Sources/SettingsView.swift` | The Settings window |
| `Sources/ContentBlocker.swift` | Ad/tracker blocking, per-site on/off, page scripts, blocked counter |
| `Sources/FilterConverter.swift` | Turns imported filter lists into WebKit rules |
| `Sources/Location.swift` | Site permissions and local weather for the start page |
| `Sources/Updater.swift` | Checks for, downloads and installs updates |
| `Sources/History.swift` | History, Frequently Visited and importing from other browsers |
| `Sources/Autofill.swift` | Passwords, cards and contact AutoFill (Keychain + Touch ID) |
| `Sources/Downloads.swift` | Downloads and the downloads list |
| `Sources/Welcome.swift` | Welcome screen and default-browser prompt |
| `Sources/Extensions.swift` | Chrome extensions: installing, running, toolbar buttons |
| `scripts/build-app.sh` | Builds the app bundle, update zip and DMG |
| `scripts/make-dmg-background.swift`, `scripts/dmg-settings.py` | The styled installer window |
| `scripts/make-icon.swift` | Draws the app icon |

## Privacy notes

- Live suggestions send what you type in the address bar to your chosen search engine as you
  type, like other browsers do. They can be turned off in Settings › General.
- The ad counter uses WebKit's reporting of blocked requests (the private API Safari itself uses).
- Location for the start page is rounded to about 1 km and sent only to Open-Meteo (weather) and
  Apple (town name), and only if you turn it on.
- Site icons are fetched from each site directly, not through a third-party icon service.
- Bookmarks and history are stored only on this Mac, in `~/Library/Application Support/Hush Browser/`.
- Passwords and cards are stored in the macOS Keychain and filled only after Touch ID or your password.

## License

Not chosen yet.
