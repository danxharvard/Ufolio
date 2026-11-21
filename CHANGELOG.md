# Changelog

## 0.3.0

**New**
- Settings redesigned in the style of macOS System Settings: a sidebar with coloured icon tiles.
- Welcome screen on first launch, with import of your most-visited sites from Safari, Chrome,
  Brave, Edge, Arc, Vivaldi or Firefox.
- Hush asks to become your default browser when it opens (with “Don’t ask again”).
- Start page: Favourites and Frequently Visited, built from your Hush history.
- History, with address-bar suggestions from pages you’ve visited and automatic clean-up
  (after a day, week, two weeks, month, year, or manually).
- Passwords & AutoFill: save and fill passwords, credit cards and your contact card. Stored in the
  macOS Keychain; filled only after Touch ID or your Mac password, only on https pages, and only on
  the exact site a password belongs to.
- Downloads list in the toolbar with progress, Show in Finder and automatic clean-up options;
  optional opening of “safe” files after downloading.
- Location and camera/microphone requests: Allow Once, Always Allow or Don’t Allow, with
  per-site answers you can change in Settings.
- New windows can open your homepage; “Set to Current Page” for the homepage.

**Fixed (security and stability review)**
- Links from other apps now open in Hush when it’s the default browser (they were ignored).
- Websites can no longer open other apps on your Mac without asking.
- A page can no longer freeze Hush with endless pop-up messages; messages are per tab and can be
  silenced after the second one, and show the origin reported by WebKit rather than the page’s claim.
- Pages can no longer redirect you to `data:` or `javascript:` addresses (a phishing trick).
- Downloads are now quarantined so macOS Gatekeeper checks them before they open.
- Downloaded file names are sanitised.
- Hush’s own page scripts (ad-space collapsing, cookie banners, AutoFill) now run in WebKit’s
  isolated world, so pages can’t see, call or fingerprint them.
- Quit (⌘Q) no longer does nothing while a sheet such as the welcome screen is open.

**Faster**
- Ad-space collapsing scans at most every 0.6 s and pauses in background tabs.
- History is saved in the background, in batches.

## 0.2.0
- Settings window, Hush Shields (filter-list import, blocked counter, per-site shields,
  collapsing empty ad spaces, cookie banners), privacy options, location features, self-updating.

## 0.1.0
- First version: tabs, address bar with live suggestions, bookmarks, built-in ad blocker.
