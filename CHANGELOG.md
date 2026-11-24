# Changelog

## 0.43.3: ten more fixes

**Ad blocking**
- Built-in blocking rules now update with Ufolio. Before, WebKit kept the copy compiled the
  first time you ran Ufolio, so improved rules from later updates never took effect.

**Fixes**
- What's New appears again after updating (it couldn't find notes for recent versions).
- History now includes pages that change without reloading, such as YouTube videos and web apps.
- Highlighting an address bar suggestion and pressing Return opens that suggestion, even if
  more suggestions arrive just before.
- Tabs you opened just before quitting are kept for next time.
- Pinned tabs stay pinned when the Orbit they were in is deleted.
- Fixed a possible crash on the look-alike site warning's "go to the real site" button.
- Site icons that couldn't load (for example while offline) are tried again later.

**Smoother**
- Fast downloads no longer flood the window with progress updates.
- Downloading an update no longer redraws Settings many times a second.

## 0.43.2: security and stability fixes

**Security**
- Extensions can now only open or load web and extension pages. Before, an extension could
  load a javascript: address into a tab and so run code on sites it had no access to, or open
  files on your Mac.
- Deleting an Orbit profile now always wipes its cookies and logins, even if you hadn't used it
  since Ufolio started.

**Stability**
- Sleeping tabs now really free their memory: the page's web process ends straight away.
- An extension loading an address into a sleeping tab now wakes it properly first, so the
  page gets ad blocking and works normally.
- A tab opened in Split View plays its video again (it stayed paused from when you left it).

## 0.43.1: more stability

**Smoother**
- Fixed occasional freezes of a few seconds: checking a page against look-alike sites, and
  offering saved logins or cards, read your passwords from the keychain on the main thread,
  which can stall. They now happen in the background.
- Find on Page waits for a pause in typing, and Next/Previous no longer re-read the whole page.
- Bookmarks: checking whether a page is bookmarked is now instant however many you have, and
  importing thousands of bookmarks no longer freezes the window.
- Reader mode lays out long articles as you scroll, so changing the text size is instant.
- The Force Field settings pane no longer redraws itself as ads are blocked in other windows.

**Fixes**
- The setup guide, dialogs and the Command Palette now block clicks to the page behind them
  (you could click a website's buttons through the frosted backdrop).
- A damaged bookmarks file no longer gets replaced by the starter bookmarks. History, filter
  lists and extensions also keep a copy of a damaged file rather than losing it.
- Recording a new keyboard shortcut no longer swallows typing in browser windows.
- A Stealth tab can no longer be counted as a normal tab for a moment while its window closes.
- The photo of the day is tried again if you were offline, instead of waiting until tomorrow.

**Tabs down the side**
- Force Field and Stealth now sit at the top right, beside the ⋯ menu.

## 0.43.0: the stability release

**Buttons respond instantly**
- Fixed toolbar and tab bar buttons that could take 2–3 seconds to respond (or miss clicks).
  In the side tab layout the window-drag area covered the sidebar and back/forward buttons; now
  only empty space moves the window.
- The sidebar button no longer redraws the whole window when it opens or closes the sidebar.
- The window no longer re-lays out its title bar after every change, which was slowing down
  every click in the toolbar and in Settings.
- Tabs no longer redraw every time anything else in the window changes.
- The mute button on side tabs can be clicked around the icon, not only right on it.

**Less work while you browse**
- Page loading progress, blocked ad counts and the all-time totals now update a few times a
  second instead of for every single request, so busy pages don't redraw the window constantly.
- Page details (title, address, padlock and so on) only redraw things when they really change.
- The loading bar and dragging the Split View divider or the side tab bar's edge are smoother.
- The start page works out which sections fit without building several copies of itself.
- Address bar and Command Palette suggestions search your history much faster as you type.
- A closed Settings window stops updating in the background after half a minute.
- The hidden Bookmarks & History sidebar no longer updates while it's tucked away.
- Settings › Performance measures memory calmly every few seconds, only while Settings is in front.

**Fixes**
- A new download started just after retrying another could take its place and overwrite its file.
- Filter lists now set up one at a time, so two can't overwrite each other.
- Going back from a look-alike site warning now takes the warning away.
- The resize cursor could get stuck after closing Split View.
- Websites can no longer try to open files on your Mac (file:// addresses).
- Fixed a possible crash when adding some news feeds.

## 0.42.1

**Smoother sidebar**
- Bookmarks & History now slides in as a frosted card over the edge of the page, instead of
  squeezing the page. The page never has to rearrange itself, so the slide is silky even on big sites.

**Settings**
- The performance mode cards are now all the same size.
- Keep an eye out: a couple of little green men, and the odd saucer, are hiding around Settings. 👽

## 0.42.0

**New: automatic Power Mode ⚡**
- Ufolio now works out when a tab genuinely needs more: a big web app like Google Sheets or
  Figma, a map, a 4K video, a call. It then lets it use extra memory (up to 60% more than usual,
  never more than 45% of your Mac's), and keeps heavy tabs you've just used awake.
- A few minutes after the heavy work stops, it drops back to its light, low-memory self on its own.
- When memory does need freeing, the biggest idle tabs go to sleep first, so one sleeping web app
  frees more than five articles.
- Silent videos and animations in tabs you can't see are paused, saving memory, graphics and
  battery; they carry on when you go back. Sound keeps playing.
- Find it in Settings › Performance, where it shows when it's on and why. It's on by default.

## 0.41.1

**A start page that fits**
- The start page is now a single, static screen: no scrolling. It uses all the space in the
  window, and if the window is small it leaves out the least important sections first (News, then
  the Privacy Report, then Recently Closed), so everything you see fits.

## 0.41.0

**Pew pew 🛸**
- In the Force Field panel, the saucer now fires laser bolts at ads floating below it, and each
  one bursts into pieces.
- The setup guide opens with the saucer flying about, zapping ads with its beams.
- "Ufolio" on the start page is now in goofy alien lettering.

**Start page**
- Adult websites no longer appear in Recently Closed or Suggestions unless you turn on
  "Show adult sites in Recently Closed and Suggestions" in Settings › Appearance › Start page.

## 0.40.2

- Releases now build on machines that are far less busy, so updates reach you reliably. Includes
  everything since 0.38.0: the new Ufolio name and saucer, Force Field, Orbits and Stealth Mode,
  the ⋯ panel, and a smoother start page.

## 0.40.1

**The saucer has landed 🛸**
- Ufolio's new saucer, with its two little green men, now appears throughout the app: on the
  start page, in the setup guide and What's New, in Settings, and on blank tabs.
- The Force Field button and panel show the saucer too, with its tractor beam.

## 0.40.0

**Hush is now Ufolio Browser 🛸**
- A new name and a new icon: a flying saucer with little green men aboard.
- Hush Guard is now **Force Field**, Spaces are now **Orbits**, and private windows are now
  **Stealth Mode**.
- Nothing else changes: your settings, bookmarks, history, passwords and website sign-ins all
  come along, and Ufolio keeps updating itself as before. If you installed it before the rename,
  it may still be called Hush Browser in your Applications folder; rename it in Finder if you like.

## 0.39.1

- Hush now looks for updates, help and downloads at the project's new home on GitHub
  (danxharvard/Ufolio). Nothing changes for you.

## 0.39.0

**More beautiful**
- The ⋯ panel now sits at the top right of the window with tabs down the side too.
- The Hush Guard panel has a soft glow behind the moon, matching cards with fine edges, and a
  livelier count.
- The Bookmarks & History sidebar: a frosted highlight that slides between Bookmarks and History,
  and tidy pill buttons along the bottom.
- Dialog buttons are Hush's own: rounded, in each dialog's colours, and crisp even when the window
  isn't in front.

**Smoother start page**
- Site icons and news pictures are now fully prepared in the background, at the size they're
  shown, so nothing is decoded while you scroll. Icons also use less memory.

## 0.38.0

**New: the ⋯ panel**
- The ⋯ button (at the end of the toolbar, or in the side tab column) opens a frosted panel
  with everything you reach for most: New Tab, New Private Window, History, Bookmarks,
  Downloads, Passwords, Extensions & Themes, Print, Save Page As, Translate Page and Find in Page,
  each with its icon and keyboard shortcut.
- A live zoom control (− 100% +, with full screen) right in the panel, plus switching between tabs
  along the top and down the side, Settings, and Help.

## 0.37.1

**Smoother start page**
- Cards on the start page now move with the scroll instead of lagging behind it: each card is
  drawn once as a single picture, and news cards no longer use frosted glass that had to be
  re-blurred on every frame.

## 0.37.0

**Cooler and smoother**
- Video and busy sites no longer make Hush work harder than it should: the rounded page card was
  being redrawn with a soft shadow and clipping mask on every frame. Pages are now rounded by
  WebKit's own layer, which costs almost nothing, so fans stay quieter on sites like video
  streaming services.
- Smoother scrolling on the start page and in Settings: lighter, fixed shadows on cards, with no
  redraws as the pointer moves over them.

**Fixes**
- Opening a new tab always puts the cursor in the address bar, ready to type. (Hush now checks
  the cursor really landed there, and tries again for a moment if the new tab is still settling.)

**Extensions**
- An extension you add now runs in the tabs you already have open, not only in new ones.
- Extensions that open a window open it as tabs, and extensions asking for access to more sites
  get a proper Hush prompt.

## 0.36.0

**New: Hushlist**
- Connect Hush to Hushlist (hushlist.online) for maximum blocking: about 240,000 more ad, tracker,
  phishing and malware domains, free and with no sign-up. Find it at the top of Settings › Hush
  Guard; a short guide walks you through it, including blocking in every app on your Mac.
- Visit hushlist.online in Hush and the site can offer to connect it for you (Hush always asks first).
- Big filter lists are no longer cut off at 150,000 rules: they're split into parts, so every rule is used.

**Fixes**
- A new tab puts the cursor in the address bar, so you can start typing straight away.

## 0.35.2

**Lighter frosting**
- The frosted glass is clearer: more of your desktop shows through the toolbar, the side tab
  column and Settings.

## 0.35.1

**Fixes**
- Changing the start page background no longer changes the size of the page or pushes the tab
  column aside. Every picture now simply fills the space, whatever its size.

## 0.35.0

**New: beautiful backgrounds**
- Twilight and Aurora are gone. Choose Frosted Glass, your desktop picture, a fresh Photo of the
  Day, one of Apple's macOS wallpapers, or your own photo (Settings › Appearance › Start page).
- Pictures get a gentle shade so the start page reads well, and they're loaded at screen size to
  keep memory low.

**Faster**
- Pages load as fast as in plain WebKit, even with Hush Guard on: Hush's cookie and ad-tidying
  helpers now wait until a page has loaded, and only run where ads were actually blocked.
- Settings is now Hush's own window. It opens faster, and reopens instantly.
- When your Mac is short of memory, Hush also lets go of the Settings window and the start page
  picture.

## 0.34.1

**Fixes**
- Clicking into the address bar now really does select the whole address, and it stays selected
  when you let go of the mouse button. (macOS gives the address bar focus just before it hands
  over the click, so Hush took your click for a second one and placed a cursor.) Click again to
  place the cursor.

**Polish**
- The Bookmarks & History sidebar is now a rounded, frosted card beside the page, matching its
  corners, instead of a square panel.
- Fresh wording throughout: Hush is light, fast and powerful.

## 0.34.0

**New: setup guide**
- The first time Hush opens, a short guide walks you through it one question at a time:
  bring your bookmarks and favourite sites over from another browser, pick a search engine,
  choose how much Hush Guard blocks, put your tabs along the top or down the side, choose Day
  or Night and an accent colour, and make Hush your default browser. Every screen has a Back
  button, and each answer is saved as you go.
- Run it again any time from Settings › General › Setup guide.

**New: tabs down the side**
- Choose Tabs down the side in Settings › Appearance, the setup guide, the View menu or the
  Command Palette. A frosted column holds the window buttons, back and forward, the address
  bar, your Space, pinned tabs as icons and the tab list.
- Drag its edge to resize it, or double-click the edge for a slim, icons-only column.
- Drag tabs up and down to reorder them. Right-click for the same options as tabs along the top.

**A cleaner, more compact look**
- The page now sits as a rounded card inside the frosted window.
- A slimmer toolbar and bookmarks bar, and a new ⋯ menu with the everyday commands.
- Address suggestions line up under the address bar wherever it is.

**Speed and memory**
- Closing a tab now ends its page straight away, so its memory and web process are given back
  at once.

**Fixes**
- The tab row is dimmed along with the rest of the window behind What's New, dialogs and the
  Command Palette, instead of staying bright above a dimmed toolbar.
## 0.33.0

**Stability and security release**

**Safer updates**
- Every update is now signed with Hush's own private key, and Hush checks that signature before
  installing anything. Even someone who managed to publish a release on GitHub couldn't make
  Hush install it.

**No more freezes on some websites**
- Sites that store encryption keys (common on messaging and banking sites) could make macOS ask
  for keychain access, freezing the window until you answered, and again after every update.
  Hush now looks after that key itself, so the question never comes up.

**Privacy**
- Site icons from private windows are no longer saved to disk.
- Page titles from private windows no longer reach your history.
- Downloads from private windows are no longer kept in the downloads list after Hush quits.

**Security**
- A site trying to download lots of files in a row now has to ask first.
- Hide Elements only reacts to your own clicks, never to clicks a page fakes.
- Extensions containing links to other places on your Mac are refused before anything is unpacked.
- Filter lists are always fetched over a secure connection.
- Site icons are limited to 1 MB while downloading, not after.

**Tested**
- Stress-tested with 25 busy websites, rapid tab switching, Split View, Spaces, Tab Sleep and
  closing everything: no crashes, and every closed tab's memory is given back.
## 0.32.2

**Fixes**
- Clicking into the address bar selects the whole address and now keeps it selected until you
  type, press a key or click again. Before, it could let go after half a second.

**Frosted everywhere**
- Settings and History are now frosted glass too, like the browser window, with see-through
  cards in Settings.

## 0.32.1

**Fixes**
- Clicking into the address bar now always selects the whole address, ready to copy or type
  over. Before, the full address could arrive a moment after the click and leave just a cursor.
  Click again to place the cursor where you want it.

## 0.32.0

**Frosted all the way down**
- The toolbar and bookmarks bar are now frosted glass, like the tab row, so your desktop shows
  softly through the whole top of the window. The selected tab uses exactly the same frosted
  fill, so it always matches the toolbar.

**Menus**
- Every right-click menu has icons: tabs, bookmarks, the sidebar, history, downloads, news and
  the start page.

**Fixes**
- The selected tab sits flush on the toolbar again (since 0.29.0 it floated a few points above it).
- A window can no longer end up with no tabs and a missing address bar; it opens a new tab instead.
## 0.31.0

**A more beautiful window and toolbar**
- Address bar suggestions are redesigned: a neater panel sized to fit, site icons on soft tiles,
  the address beside each title, and a star or clock to show whether it's a bookmark or from
  your history.
- The same page no longer shows up twice in suggestions (for example with and without "www").
- With lots of tabs open, the tab you're on keeps room for its title while the others shrink to
  tidy icons, instead of every tab showing a couple of letters and "…".
- Bookmark folders in the bookmarks bar highlight when you point at them, like bookmarks do,
  and hover highlights fade in smoothly.
## 0.30.0

**A more beautiful Hush**
- Settings is redesigned in the style of macOS System Settings: every section is a rounded
  card with fine lines between rows, and on/off settings are now switches.
- The Hush Guard mode cards line up neatly at the same height.
- Spaces & Profiles settings have larger Space icons, a profile picture for each profile, and
  tidy icon buttons for editing.
- The start page has a crisper Hush title and softer tiles behind favourite icons in Night mode.
  Suggestion cards use cleaner, richer colours with a gentle sheen.
- The Hush Guard panel's Ads, Trackers and Fingerprint tiles are more polished, and their
  numbers animate as they change.
- New tabs grow in smoothly from the tab bar, and closed tabs fade away.

**Improvements**
- Rename bookmark folders: right-click a folder in the sidebar.
- Removed leftover code.
## 0.29.0

**New: Command Palette (⌘K)**
- One box to find anything: open tabs (in every Space), every command, Spaces, bookmarks and
  history. Type a few letters, use the arrow keys, press Return. Shortcuts are shown beside
  each command. It all runs on your Mac; nothing you type is sent anywhere unless you choose
  to search the web.

**New: Spaces**
- Keep sets of tabs apart, such as Work, Personal and Shopping. Each window shows one Space at a
  time. Switch with the button left of your tabs, ⌃1–⌃9, ⌃⌘[ and ⌃⌘], or the Command Palette.
- Give each Space a name, icon and colour. Right-click a tab to move it to another Space.
- Each Space remembers its tabs and pinned tabs between launches, and only the tab you're
  looking at loads.

**New: Profiles**
- A profile has its own cookies, sign-ins, site data and cache, so you can be signed in to two
  accounts on the same site at once. Give any Space its own profile.
- Manage Spaces and profiles in Settings › Spaces & Profiles. Deleting a profile erases its
  website data. Clear Website Data and Forget This Site now cover every profile.

**Fixes**
- Tabs brought back from last time no longer occasionally lose their address before you open them.
## 0.28.0

**New: bookmark folders**
- Organise bookmarks into folders. In the bookmarks bar, folders open as menus (with Open All
  in Tabs); in the sidebar, they expand and collapse.
- Right-click a bookmark to Rename it, Edit its Address or Move it to a Folder. Make a new
  folder from the sidebar's ⋯ menu.

**New: import and export bookmarks**
- From the sidebar's ⋯ menu, import the bookmarks file any browser can export (Chrome, Safari,
  Firefox, Edge, Brave…), folders included, or export yours to use anywhere. Bookmarks you
  already have are skipped.

**New in Hush Guard**
- Block annoyances (on by default): "Sign in with Google" pop-ups, push-notification prompts
  and newsletter pop-ups. Sign in with Google buttons on pages still work.
- Block chat widgets (off by default): hides the support-chat bubbles in the corner of many
  sites.
- Filter lists you've added from the web now keep themselves up to date, refreshing quietly
  once a week.

## 0.27.0

**New: Memory Saver** (on by default, Settings › Performance)
- Hush now keeps itself within a memory limit: a quarter of your Mac's memory, or a limit you
  choose. When it's over, the tabs you used least recently go to sleep. The tab you're on,
  either side of Split View, and tabs playing sound or using the camera always stay awake.
  In testing, seven busy news tabs went from 989 MB to 309 MB.
- Old pages are no longer kept alive in memory just to make Back instant. Back reloads the
  page from the cache instead, which is still quick.
- Sleeping tabs keep a small, compressed preview instead of a full-size picture, often 15 times
  less memory each.
- Site icons and news pictures held in memory now have firm limits, and are let go as soon as
  macOS says memory is tight.

**New in Hush Guard: see who was tracking you**
- The Hush Guard panel has a "What was blocked" list showing the companies behind the ads and
  trackers stopped on the page (Google, Meta, Amazon, Criteo and so on), with how many each
  tried.

**Faster**
- Fingerprinting protection leaves large canvases (maps, photo editors, games, video) alone,
  so those pages stay quick. Fingerprinting uses small ones, which are still protected.
- The hidden Bookmarks & History sidebar no longer draws anything while it's closed.

## 0.26.1

A second full review of Hush's code: tidier, faster and sturdier.

**Faster and smoother**
- The Bookmarks & History sidebar is ready the moment you ask for it. It's built quietly in the
  background, slides in and out smoothly, and the page makes room in one step instead of
  redrawing on every frame of the animation.
- The sidebar's lists open faster, and bookmarks can still be dragged into any order.
- Resizing the window no longer redraws the whole browser on every frame.
- Closed Private windows no longer leave timers running in the background.

**Fixed**
- Clicking into the address bar now selects the whole address, ready to type over (the full
  address used to replace the site's name a moment later and clear the selection).
- If a download you chose to try again never started, the next download you made could be
  filed under its name. That can't happen now.
- Half-written save files left behind when Hush is force-quit are now cleared away
  automatically.

**Tidied**
- Code left over from older features has been removed, and Hush now builds with no warnings,
  so it's ready for the next versions of Swift and macOS.

## 0.26.0

**New: Bookmarks & History sidebar**
- Click the sidebar button beside Back, or press ⇧⌘L, to keep your bookmarks and history
  beside the page while you browse.
- Switch between Bookmarks and History at the top, and search either one.
- Bookmarks: click to open (⌘-click for a new tab), drag to reorder, and right-click to rename,
  copy or remove. Bookmark the page you're on from the bottom of the sidebar.
- History: grouped by day, with Show All History and Clear at the bottom.

**Removed**
- Ask Hush. On most Macs a model running locally was too slow to be useful, so it's gone. Its
  settings and any API keys it stored in your keychain have been removed.

## 0.25.0

**New: Ask Hush, with your own AI model**
- Click the sparkles button in the toolbar (or press ⌥⌘A) to open Ask Hush beside the page.
- One click to Summarise this page, get its Key takeaways, Explain it simply, or check Is this
  trustworthy?, or ask anything. Replies stream in with headings, lists and bold text.
- Bring your own model in Settings › AI:
  - **On this Mac:** Ollama or LM Studio. Free, and nothing leaves your Mac.
  - **Claude:** with your own Anthropic API key.
  - **Any OpenAI-compatible service:** with your own key.
- Private by design:
  - A page is only shared when you ask about it, and you can untick Include this page.
  - Conversations aren't saved.
  - API keys live in your Mac's keychain and are only ever sent over https.
- Web pages are treated as information, never instructions, so text hidden in a page can't
  take over the assistant.

## 0.24.0

**New: Hush News**
- Turn it on from the start page (or Settings › Appearance) for the day's stories from the
  BBC, the Guardian, Sky News, The Verge, Ars Technica, Wired, NASA, New Scientist and more.
- A magazine-style layout: a big hero story, then picture cards, wide stories, compact cards
  and numbered "Also in the news" lists, with headlines set in an elegant serif.
- Topics along the top: For You, Top Stories, World, UK, Technology, Science, Business, Sport
  and Culture.
- Customise topics and publishers, or add any RSS or Atom feed. Right-click a story to open it
  in a new tab, copy a clean link or hide a publisher. Stories you've read are dimmed.
- Private by design: Hush fetches every feed and picture itself, straight from each
  publisher, without cookies. No news service sits in between, and nobody sees what you
  read.

## 0.23.0

**New: script blocking**
- Choose Allow, Block third-party (only the site's own scripts run) or Block all (no JavaScript)
  for every site, or for one site at a time.

**New: settings for each site**
- The Hush Guard panel has a This Site card. For the site you're on, set ads and trackers
  (Standard, Strict or Off), scripts, fingerprinting protection (Off, Standard or Strict) and
  cookies (Allow all, Block third-party or Block all). Anything left on Default follows your
  defaults, and Use Defaults resets the site.
- Settings › Hush Guard lists every site you've changed, with a Reset button for each.

**New: defaults for every site**
- Settings › Hush Guard › Defaults for every site sets the blocking level, scripts,
  fingerprinting protection and cookies everywhere. Your earlier cookie and fingerprinting
  choices carry over; those switches moved here from Privacy & Security.

**Improved**
- The Settings title is centred in the title bar.
- Upgrading connections to HTTPS now keeps working on sites where Hush Guard is off.

## 0.22.0

**New: Settings › Keyboard**
- See every Hush shortcut in one place, grouped by what it does, and change any of them: click a
  shortcut and press the keys you'd like. Press Delete to remove one, or Restore Defaults to
  start again. Hush tells you if a combination is already in use.

**New: bring your bookmarks over**
- Settings › General › Import History and Bookmarks now brings over bookmarks too (as
  Favourites) from Chrome, Brave, Edge, Arc, Vivaldi, Firefox and Safari. Ones you already
  have are skipped.

**New: import passwords**
- Settings › Passwords & AutoFill › Import: choose the passwords file you exported from
  Chrome, Safari, Firefox, Edge or Brave. Each one goes into your Mac's keychain, and Hush
  then offers to move the exported file (which holds your passwords as plain text) to the
  Trash.

## 0.21.0

**New: Split View**
- Show two tabs side by side: right-click a tab and choose Open in Split View, or press ⌃⌘S.
- Click a side to make it active; the address bar, Find and menus work on that side. Drag the
  divider to resize, or double-click it for equal halves. Swap or close a side from its header.

**New look: one design for every question**
- Every question Hush asks now uses the same card, each with its own little animation in the
  Hush Guard style:
  - website permissions, with circling beads
  - opening another app, and messages from a page, with a pulse
  - saving a password, with rising sparkles
  - adding an extension, with twinkling stars
  - Forget This Site and clearing history or data, with drifting dust

**New: downloads you can pause**
- Pause and resume downloads, and try failed ones again (they carry on where they stopped
  when the site allows).
- Drag a finished download out of the list into Finder, Mail or any app.

**New: crash recovery**
- If a page crashes, its tab shows a calm "This page stopped working" screen with a Reload
  button, instead of going blank. Your other tabs aren't affected.

**Improved**
- Cookie banners that say "Reject additional cookies" (like the BBC's) are now rejected
  automatically.

## 0.20.1

**New look**
- Forget This Site now asks with a small, animated card instead of a plain alert. The site's icon
  sits among drifting stars while bits of its data float away. One line explains what happens,
  and Forget is shown in red.

## 0.20.0

**New: fingerprinting protection**
- Sites that try to recognise your Mac by how it draws graphics, plays audio or reports its
  hardware get answers with tiny, invisible differences. These are the same on one site
  (so it keeps working) but different on every other site and every time you open Hush, so
  you can't be followed between them. Turn it off in Settings › Privacy & Security.

**New: blocking levels**
- Choose **Standard** (everyday), **Strict** or **Off** in the Hush Guard panel or Settings ›
  Hush Guard. Strict also blocks social widgets, fingerprinting services and tracking pings,
  blocks all third-party cookies and hides more about your Mac. A few sites may need
  Standard.

**New: skip tracking redirects**
- Links that bounce you through a tracker (l.facebook.com, google.com/url, out.reddit.com and
  more) now go straight to the real page, which is faster and leaves the tracker out.

**New: De-AMP**
- Google's AMP copies of articles open as the publisher's real page.

**New: JavaScript off for one tab**
- Right-click a tab, or use the Hush Guard panel, to turn JavaScript off just for that tab.

**New look: Hush Guard panel**
- The animated moon and stars stay. Below them:
  - this page's count, and the site with a clear on/off switch;
  - separate counts for ads and trackers, and your fingerprinting status;
  - the blocking level;
  - quick buttons for JavaScript, Hide Elements and Forget This Site.

## 0.19.0

**New: Private Browsing**
- Click the glasses button beside Hush Guard, or press ⇧⌘N, for a Private window. Its deep purple
  look tells you at a glance where you are.
- Nothing you do there is saved: no history, suggestions or recently closed tabs. Cookies and
  site data live in memory only and vanish when you close the window. Hush Guard keeps
  protecting you, and extensions are switched off.

**New: Forget This Site**
- Right-click a tab and choose Forget This Site to delete that site's cookies and website data
  (signing you out), its history and its permissions, and close its tabs. Bookmarks and
  saved passwords are kept.

**New: Reader**
- On articles, a Reader button appears in the address bar (or press ⇧⌘R). The story is shown
  on its own in calm, comfortable type, with no ads, menus or pop-ups.
- Choose Light, Sepia or Dark, serif or sans-serif, and the text size. Reader shows only the
  article's text and pictures, so none of the page's own code runs inside it.

**New: Picture in Picture**
- Float a video in its own window above everything else: the button in the address bar,
  right-click on the page, or ⌥⌘P.

**New: strong passwords**
- On sign-up and change-password forms, Hush suggests a strong password like
  "kipzot-4hamwe-Rybfud", fills it in and offers to save it.

**New: the basics**
- **Find on Page** (⌘F), with the number of matches and next/previous (⌘G, ⇧⌘G).
- **Print** (⌘P) and **Save Page As** (⌘S), which saves the whole page with its pictures.
- **Mute tabs:** tabs playing sound show a speaker. Click it to mute (or press ⌃⌘M).
- **Pin tabs:** right-click a tab and choose Pin Tab. Pinned tabs sit at the left as small icons
  and come back every time you open Hush.
- **History window** (⌘Y): everything you've visited, grouped by day, with search. Remove single
  pages or clear it all.

**Fixed**
- Opening a link from another app into a new window no longer leaves an empty address bar.

## 0.18.0

A full security, bug and speed review of every part of Hush.

**Security**
- Updates only download from GitHub. The test override now works only with a server on your
  own Mac, and the signature check is stricter.
- Extensions are checked before they're unpacked. Archives that try to write files outside
  their own folder, or that contain links to other files on your Mac, are refused. Oversized
  downloads are refused too.
- ⌘-clicking a link only opens web addresses in a new tab. Other kinds of links get the
  usual checks.
- Pages can no longer pile up "open another app" or permission prompts.
- Passwords and cards are only filled into secure (https) pages, checked again at the moment
  of filling.
- Downloads: invisible characters that can disguise a file's real type (making an app look
  like a photo) are removed from names. Zip and CSV files are no longer opened
  automatically.
- Saved passwords lock as soon as you switch apps, and copied passwords are hidden from
  clipboard-history apps.
- Address bar suggestions never send web addresses or pasted links to the search engine,
  and suggestion requests no longer carry the search engine's cookies.
- Site icons are fetched without cookies.

**Fixed**
- History, the privacy report and recently closed tabs could lose their latest changes if
  Hush quit right after a visit. Everything is now written out before Hush quits, in order.
- Clean Links could change other parts of an address while removing tracking tags. It now
  leaves the rest exactly as it was.
- Importing from Firefox now includes your most recent visits.
- A crash that could happen when turning extensions on and off quickly.
- Typing `localhost` or a local network address now opens it over http.

**Faster**
- Restoring "tabs from last time" now only loads the tab you're looking at. The others load
  when you click them, so launching with many tabs is much quicker.
- Installing updates and extensions no longer freezes the window while files are checked
  and unpacked.
- The privacy report adds itself up at most twice a second, instead of once for every
  blocked ad.
- Site icons are saved for two weeks, so they appear instantly after a relaunch. Clearing
  your history clears them too.
- The start page works out your suggested sites once, not on every redraw.
- The cookie-banner tool and translation detection do much less work on each page.
- The Aurora background uses less energy.

## 0.17.1

**New**
- Drag tabs to put them in any order. The other tabs slide out of the way, and the new order
  is kept for next time.

## 0.17.0

**New: redesigned tab bar**
- Tabs now sit in the title bar, right beside the window buttons. The selected tab curves down
  into the toolbar, and the other tabs are calm titles with thin dividers between them.
- The address bar now stretches across the whole toolbar.
- Tabs show a spinner while loading. Right-click a tab for Close Other Tabs and Close Tabs to
  the Right.

**New: Magic Theme**
- Turn it on in Settings › Appearance and the toolbar and tabs take on the colours of the
  website you're on, with light or dark text to suit.

**New: quick translation**
- When a page is in another language, a translate button appears in the address bar. Click it,
  or press ⇧⌘Y, to translate the page in place. Click again for the original.
- Translation happens on your Mac using Apple's Translation, so the page never leaves your
  Mac. The first time, macOS may ask to download the language.

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
