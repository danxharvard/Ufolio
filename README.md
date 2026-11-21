# Hush Browser

A lightweight, native macOS web browser built on WebKit (the engine behind Safari).

- Calm, minimal interface that follows Day/Night mode (View › Appearance)
- Address bar with live Google suggestions as you type (↑/↓ to pick, Return to go)
- Bookmarks and a bookmarks bar (⌘D to bookmark, ⇧⌘B to show/hide, right-click to rename/move/remove)
- Built-in ad and tracker blocker (shield button in the toolbar)
- Tabs (⌘T, ⌘W, ⇧⌘[ / ⇧⌘]), zoom (⌘+ / ⌘- / ⌘0), downloads to ~/Downloads
- Under 3 MB, universal (Intel and Apple Silicon), macOS 13 or later

## Install

Download `HushBrowser-<version>.dmg` from [Releases](https://github.com/danxharvard/hushbrowser/releases),
open it and drag **Hush Browser** into **Applications**.

The first time you open it, right-click the app › **Open** › **Open**. macOS asks this once because
the app isn't signed with a paid Apple Developer ID.

## Build from source

Needs Apple's Command Line Tools (`xcode-select --install`); Xcode itself is optional.

```bash
./scripts/build-app.sh
```

This produces `build/Hush Browser.app` and `build/HushBrowser-<version>.dmg`.
The version number lives in the `VERSION` file.

## Project layout

| File | What it does |
| --- | --- |
| `Sources/HushApp.swift` | App entry point, menus and keyboard shortcuts |
| `Sources/BrowserWindow.swift` | Window layout, toolbar, page area, loading bar |
| `Sources/BrowserModel.swift` | A window's tabs |
| `Sources/BrowserTab.swift` | One tab: the WebKit view, navigation, pop-ups, downloads |
| `Sources/AddressBar.swift` | Address field and turning typed text into a URL or search |
| `Sources/Suggestions.swift` | Live Google and bookmark suggestions |
| `Sources/TabStrip.swift` | The tab strip |
| `Sources/Bookmarks.swift` | Bookmark storage, bookmarks bar, site icons, start page |
| `Sources/AdBlocker.swift` | Ad and tracker blocking rules |
| `scripts/build-app.sh` | Builds the app bundle and DMG |
| `scripts/make-icon.swift` | Draws the app icon |

## Privacy notes

- Live suggestions send what you type in the address bar to Google as you type, the same way
  Safari, Chrome and Firefox do with their default search engine.
- Site icons are fetched from each site directly, not through a third-party icon service.
- Bookmarks are stored locally in `~/Library/Application Support/Hush Browser/bookmarks.json`.

## License

Not chosen yet.
