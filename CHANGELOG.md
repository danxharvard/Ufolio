# Changelog

## 0.16.0

**New: Settings › Performance**
- Five modes:
  - **Automatic** (the default): Balanced when plugged in, Battery Saver on battery or in
    Low Power Mode.
  - **Performance:** up to 120 Hz scrolling and animation on ProMotion displays, and links
    looked up before you click them.
  - **Balanced:** fast and efficient, for every day.
  - **Battery Saver:** background tabs slow down and sleep after 5 minutes, 3D graphics use
    the energy-saving chip, and the start page stops animating.
  - **Eco:** everything in Battery Saver, plus no autoplaying video and nothing playing in
    background tabs, for the smallest energy use and carbon footprint.
- **Memory:** see how much memory Hush and each tab use, live, and put heavy tabs to sleep with
  one click.
- **Free up memory automatically:** when your Mac runs low, background tabs go to sleep
  straight away.
- **Pause sound and video in background tabs**, if you'd like that in any mode.
- **Your footprint:** a rough estimate of the data Hush Guard saved you this month.
- Tab Sleep moved here from General.

## 0.15.0

**New: Favourites suggestions**
- When you visit a site at least 6 times a day for 3 days in a row, Hush offers to add it to your
  Favourites with a slim bar above the page. One click and it's on your start page.
- Not Now asks again in a week, or choose Never for This Site. Browsing around inside one site
  counts as one visit, so only real return trips count.
- The counts stay on this Mac, cover only the last few days and are wiped when you clear your
  history. Turn it off in Settings › General › History.

## 0.14.0

**Changed**
- Hush now needs macOS 15 Sequoia or later. Apple only keeps the web engine that Hush, like Safari,
  is built on up to date on recent versions of macOS, so this keeps you on a patched one.
- Software Update won't install a version of Hush that your Mac can't open. It tells you which
  macOS you need instead.

## 0.13.0

**New: extensions in the toolbar**
- Up to three of your extensions now have a button right next to Hush Guard.
- Got more than three? A small extensions button shows how many more there are, and opens
  Settings › Extensions, where every extension is listed.
- To pick which three get a button, choose Show in Toolbar from an extension's ⋯ menu in
  Settings › Extensions. The same menu has Use on Current Page for the others.

## 0.12.1

**Improved**
- Personalise Start Page now suggests places as you type a town or postcode. Click one, or use
  the arrow keys and Return, to choose it.

## 0.12.0

**New: Personalise Start Page**
- A small Personalise Start Page button sits in the corner of every new tab. Click it and type
  your town or postcode to see your local weather under the greeting. More personal touches
  are coming soon.
- You can change or remove your town any time, from the same button or Settings › Location.

**Fixed**
- Hush no longer asks macOS for your location when it starts. It never uses your Mac's location
  for itself any more. Websites can still ask, and Hush checks with you first.

## 0.11.0

**New look for Settings**
- A clean, Safari-style layout: no boxes or divider lines, settings on the left and their
  controls on the right, with room to breathe between sections.
- Each section opens with its icon on the left and a short description beside it.
- A slim title bar instead of the tall one.
- Checkboxes, like Safari's Settings, with the coloured icons kept for the main options.

## 0.10.0

**New: Safari extensions** (macOS 15.4 or later)
- Settings › Extensions now lists the Safari extensions that came with apps on your Mac (usually
  from the Mac App Store). Click Add and the extension runs in Hush straight from its app.
- Safari content blockers that include their rules as a file can share them with Hush Guard
  (Import Rules). Some keep their rules private inside their app; Hush shows when that's the case.

**Improved**
- A little more space between the search field and the Hush card in the Settings sidebar.

## 0.9.2

**Improved**
- Hush Guard panel: the count is large and centred with its description underneath, and the panel
  now has a solid background so it stays readable over bright pages.
- Settings › Software Update: earlier versions sit at the bottom, showing three with Show More.
- The Hush card in the Settings sidebar lines up with the search field.
- Settings section icons have a tighter, softer glow.

## 0.9.1

**New**
- Add to Hush: on an extension's page in the Chrome Web Store, a bar above the page offers a
  one-click Add to Hush button. No more copying links into Settings.
- Long addresses: the address bar shows the website's name, and hovering over it shows the full address.
- Each release on GitHub now lists exactly what's new, the same as Hush's What's New screen.

## 0.9.0

**New**
- What's New: after each update, Hush shows what changed the first time it opens.
- Settings › Software Update shows what's in the version you have installed, plus earlier versions.
- Search in Settings: type in the sidebar to find any setting ("cookies", "zoom", "password"…).

**New look**
- Settings has a Hush card at the top of the sidebar showing your version and whether you're up to date.
- Each section opens with a large, glowing icon and a short description.
- Main settings have small coloured icons, so each list is quicker to scan.
- Sections fade gently into place as you move between them.

## 0.8.1

**Improved**
- Websites' location, camera and microphone requests: "Don't Allow" is now remembered too, and
  "Allow Once" lasts until you quit Hush, so sites stop asking every time. Change any answer in
  Settings › Location or Privacy & Security.
- The Hush Guard panel shows the Hush logo when there's no website open (instead of a blank icon).

## 0.8.0

**New: Chrome extensions** (macOS 15.4 or later)
- Settings › Extensions: paste a Chrome Web Store link and Hush downloads, unpacks and adds the
  extension, after showing what it will be able to access. Developers can also load an unpacked folder.
- Extension buttons appear in the toolbar, with their pop-ups and badges.
- Switch extensions on or off, or remove them, in Settings › Extensions.
- Built on WebKit's own extension support, so most Chrome extensions work; a few that rely on
  Chrome-only features may not.

## 0.7.2

**Improved**
- The Hush Guard illustration is now free-standing with no background: a softly lit Hush moon,
  stars drifting past and tracker beads sinking into its curve, with only the browser behind it.
- The Hush moon is drawn as one clean shape everywhere (no faint seams).

## 0.7.1

**Fixed**
- "Hush Guard Settings…", Hush Browser › Check for Updates… and the AutoFill "Settings…" link did
  nothing on macOS 14 and later. They now open Settings on the right section.

## 0.7.0

**New look**
- The Hush logo, "Eclipse": a crescent moon quietly swallowing a tracker. New app icon, and the
  logo now appears on the start page, the Privacy Report, the welcome screen, Settings and as the
  Hush Guard button in the toolbar (dimmed when Hush Guard is off for a site).
- The Hush Guard panel opens with an illustration: tracker dots drifting into the moon and
  vanishing, one for each thing blocked; when Hush Guard is off, the trackers roam free.

**Subtle animations**
- The logo plays its eclipse on the welcome screen and start page.
- The Hush Guard button gives a small pulse when something is blocked.
- Start page sections float gently into place. All of this respects Reduce Motion.

**Improved**
- Hush remembers its window size and position between launches.

## 0.6.1

**Fixed**
- Hush could open two windows at launch. Hush now has exactly one browser window (with unlimited
  tabs), and only one copy of Hush can run at a time: opening it again brings the running one forward.

**Changed**
- "Hush Shields" is now **Hush Guard**.

## 0.6.0

**New**
- Element Zapper: right-click a page › Hide Elements on This Page…, then click anything to hide it.
  Hidden elements stay hidden on that site (applied by WebKit before the page draws). Review or
  bring them back in Settings › Hush Guard › Hidden elements.
- Tab Sleep: background tabs you haven't used for a while (15 minutes by default) free their
  memory and wake instantly, with their page and back/forward history intact. Tabs playing sound or
  video, or using the camera or microphone, never sleep. Settings › General › Performance.

**Improved**
- More space between the icons and names in the Settings sidebar.

## 0.5.0

**New**
- Clean Links: tracking tags (utm_…, fbclid, gclid and ~30 more) are removed before pages load.
  Edit › Copy Clean Link (⇧⌘C) copies the current address without them.
- Look-alike site warning: fake copies of sites you use (paypa1.com, аpple.com with a Cyrillic
  "а", g00gle.com) are stopped before they load, with a button to go to the real site.
- Cookie banners are rejected automatically ("Reject all") on the major consent tools.
- Switches for all three in Settings (Privacy & Security, Hush Guard).

## 0.4.0

**New start page**
- Frosted and translucent: your desktop shows softly through, with your theme as a tint.
- Recently Closed Tabs, with Clear All. Plus History › Reopen Closed Tab (⇧⌘T).
- Favourites as large, app-icon-style tiles.
- Suggestions: cards tinted with each site's own colour, with when you last visited.
- Privacy Report: trackers blocked in the last 30 days, the share of websites that tried to track
  you, and the most widespread tracker, with Show More for the full list.
- Each section can be switched on or off in Settings › Appearance.

**Also new**
- A slim "Make Hush your default browser?" banner under the bookmarks bar replaces the pop-up.
  Closing it hides it for two weeks.

**Fixed**
- The address bar could show the previous tab's address after switching tabs (or opening a new
  tab). Toolbar items now follow the selected tab directly.
- A new tab's icon in the tab bar was a stray red square.
- Site icons are fetched once per site, even when many parts of the page ask at once.
- Clear History now also clears Recently Closed Tabs and the Privacy Report.

**Tested** in all six theme combinations (Twilight, Aurora, Plain × light, dark): address bar
position, clicks, typing an address, switching tabs, clean quit.

## 0.3.2

**Fixed**
- Imported filter lists (such as EasyList) could block entire websites, including Google, YouTube
  and X: rules that hide page elements on a site were misread as "block this site". Lists converted
  by the faulty version are re-downloaded and converted again automatically on launch.
- The Aurora start-page background could push the address bar out of the toolbar and swallow
  clicks, so typing an address or clicking bookmarks did nothing. Aurora is now drawn without
  animations that can affect the rest of the window, can't catch clicks, and pauses when the
  window isn't in use.

**New**
- A styled installer: drag the Hush icon onto Applications over a custom background.
- Install instructions (including macOS's "Open Anyway" step) on every GitHub release.

**Tested** in Twilight, Aurora and Plain, each in light and dark mode: the address bar stays put,
clicks reach it, and typing an address opens the right site. EasyList, EasyPrivacy and hosts lists
were checked so that no whole site is blocked.

## 0.3.1

**Fixed**
- On first launch the welcome screen could appear off-screen, leaving the browser window dimmed
  and ignoring every click and keystroke. The welcome screen and the default-browser question are
  now shown inside the window, so they can't go missing.
- If Hush was last quit with no windows open, it could reopen as just a menu bar. It now always
  opens a browser window, and clicking its Dock icon brings one back.

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
