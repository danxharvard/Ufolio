# Changelog

## 0.52.0-beta.11: name your bookmarks (beta)

- **Name your bookmarks:** when you save a bookmark, you can give it any name first.
- **Lighter on your Mac:** pictures around the browser are now still, so they no longer keep your Mac busy.
- Fixed saved passwords being filled in by themselves into hidden boxes on a page.
- Bug fixes and stability improvements.

## 0.52.0-beta.10: smoother YouTube, faster launch (beta)

- **Smoother YouTube:** on Macs that can't decode VP9 video in hardware, YouTube now plays in a format the graphics chip decodes, so it uses less power and runs cooler.
- **Faster launch:** with lots of tabs from last time, Ufolio opens much sooner and uses less memory.
- Fixed tabs in a minimised window going missing after a restart.
- Bug fixes and stability improvements.

## 0.52.0-beta.9: Link preview, Compact mode and Docked sites (beta)

- **Link preview:** ⌥-click a link to peek at it in a floating card, without leaving your page.
- **Compact mode:** ⌃⌘C hides the tabs and toolbar so the page fills the window.
- **Docked sites:** keep chat or music open in a panel beside every page.
- **Update reminders:** very old versions of Ufolio are asked to update.
- Bug fixes and stability improvements.

## 0.52.0-beta.8: no more YouTube ads (beta)

- YouTube ads are blocked. They come from YouTube's own servers, so blocking ad servers never
  caught them: Ufolio now mutes and skips a video ad the moment it starts, and hides YouTube's ad
  boxes and sponsored results. You may see a second or two of dark player while an ad is skipped.
  YouTube changes its ads often, so this updates itself (checked daily, and only used if it's
  signed by Ufolio) without waiting for a new version of Ufolio.
- Closing a window with a camera, microphone or location question still waiting no longer
  blocks that site for good: the question is answered Don't Allow for now, not remembered.
- What's New shows the notes for every version since the one you last used, and no longer lists
  a beta's closing note as a change.
- The safe-files setting no longer says archives open by themselves.

## 0.52.0-beta.7: safer passwords, steadier tabs (beta)

- Your saved passwords are safer: if the password vault's key couldn't be read for a moment,
  Ufolio could make a new key over it, leaving every saved password unreadable for good. It now
  waits until the key reads again.
- Restoring your tabs after a restart no longer drops everything past the 200th tab.
- The cookie auto-cleaner no longer signs you out of YouTube, Gmail and "Sign in with Google /
  Apple / Microsoft" sites.
- Putting lots of tabs to sleep at once no longer freezes the window for a moment, and switching
  tabs does a little less work.
- In Split View, the other half now pauses with its pair when you switch to another tab, and
  plays again when you come back.
- A tab closed just before quitting stays in Recently Closed.

Everything in 0.51.7 is in this beta too.

## 0.52.0-beta.6: a smoother Stealth Mode (beta)

- Stealth windows no longer lag as you move the pointer over links, buttons and bookmarks. The
  window's dark glass was being drawn the slow way on every hover; it now costs your Mac the same
  as a normal window. Pages inside Stealth keep following your Mac's Day or Night look.
- Websites can no longer tell you use Ufolio: a small bridge only hushlist.online needs was
  visible to every site. It now exists only on hushlist.online.
- The setup guide moves between steps without stutter: it no longer asks macOS for each browser's
  icon on every hover and click.
- A tab or bookmark dragged out of the sidebar (onto a page, say) no longer stays faded.
- Dropping a bookmark onto one in another folder moves it into that folder.

Everything in 0.51.6 is in this beta too.

## 0.52.0-beta.5: everything frosted, less clutter (beta)

**Frosted everywhere**
- The Force Field animation no longer sits in a solid tile: it melts into the panel through a soft
  night haze (a dusk-violet one in Day appearance). The animation itself is unchanged.
- The start page, error pages and the history list's headers are frosted glass too. No solid
  surfaces anywhere.

**Less clutter**
- Galaxy ranks, the saucer pet, the planet of the week, and the animated aliens and flying saucer
  in Settings are gone, along with the code that ran them. Their old settings are tidied away.

**Fixes**
- Checking for updates no longer fails with "error 403" on busy or shared networks: when GitHub's
  API limit is used up, Ufolio reads the latest version from github.com itself. Every update still
  has to carry Ufolio's own signature before it installs.
- Stopping a download now really stops it (the row used to stay on "downloading" for ever) and
  removes the half-finished file instead of leaving it in Downloads under the real name.
- After a password import that didn't work, Ufolio no longer offers to bin the exported file
  (it could be your only copy). Files with old Mac line endings now import too.
- With search suggestions turned off, a pause while typing a search no longer loads the results
  early.
- AutoFill no longer shows the previous site's logins if you move on while they're looked up.
- The cookie auto-cleaner rechecks your open tabs as it cleans, so a site you just opened keeps
  its cookies.
- A page waiting to translate no longer spins for ever when you translate another.
- Close Other Tabs in the Command Palette keeps pinned tabs.

Everything in 0.51.5 is in this beta too.

## 0.52.0-beta.4: a flat, native Force Field (beta)

**Force Field, redesigned** (the animation is unchanged)
- A flat, native look in the style of hushlist.online, following your Mac's Day or Night
  appearance with macOS's own colours, instead of the glass look.
- The animation sits in a flat, night-blue tile with "Force Field Active" and this page's count.
- Underneath: a plain site row with the standard switch, the Ads, Trackers and Fingerprint
  readings in one strip with hairline dividers, this site's settings as a System Settings-style
  group with flat icon tiles, simple buttons and a footer with today's and this week's totals.

Everything in 0.51.4 is in this beta too.

## 0.52.0-beta.3: lighter, safer, fewer surprises (beta)

**Lighter on memory**
- Instant pages keeps just one page ready each way for Back and Forward, instead of up to six
  whole pages per tab (50 to 200 MB apiece). Pages further back are restored from WebKit's own
  record of them: still where you left off, in a fraction of a second.
- When memory runs short, a tab sleeps, or a tab sits unused for five minutes, Back and Forward
  now keep working afterwards (they used to lose those pages).

**Smoother**
- The menu bar no longer rebuilds itself every time something changes in your window (a tab
  opening, closing or switching), work your Mac did while you browsed.
- The privacy report saves once every few seconds, not on a timer for every blocked request.
- Sign-in pages are only watched for a login form on sites you have a saved login for.

**Safer and more private**
- Look-alike warnings no longer stop real sites that are one letter from a site you use
  (games.com is not a fake names.co.uk). Real typo-squats like amazom.com and gooogle.com are
  still caught.
- Removing all website data, or Forget This Site, also lets go of pages kept in memory, so Back
  can't show a page still signed in.
- Closing your last Stealth window now forgets everything decided in it (Force Field switched off
  for a site, hidden elements, permissions, "visit anyway" answers) instead of keeping it until
  Ufolio quits.

**Handier**
- ⌘-Return (or ⌥-Return) in the address bar opens what you typed in a new tab.
- Saved logins also fill in on sign-in pages that mark their email box for passkeys.

Under the hood: unused code removed.

## 0.52.0-beta.2: a premium Force Field, and logins waiting for you (beta)

Everything in 0.51.3 (lighter when you're not using it), plus:

**Force Field animation, redrawn**
- A detailed saucer: brushed-metal hull with panel seams, a ring of running lights chasing round
  its rim, and a glowing engine ring underneath.
- A little green alien pilot sitting in the glass canopy, with big glossy eyes, glowing
  antennae, a gentle sway and the odd blink.
- The Force Field itself: a violet energy bubble round the saucer with a bright arc sweeping
  round its edge. It's gone when the shield is down.
- Two layers of drifting stars with glints, a tapered tractor beam, and ads bursting into a
  flash, a shock ring, sparks and fragments.
- The status reads "Force Field Active".

**Saved logins, typed in and waiting**
- On a sign-in page, your saved login is filled in as the page loads, ready for you to press
  Sign In. Two-step sign-ins get your email first, then your password.
- Only on secure pages, only into visible empty boxes (never over what you've typed), and the
  most recently used login if you have several. If you've chosen to be asked before filling
  (Settings › Passwords › Security), Ufolio asks as before.

## 0.51.3: lighter when you're not using it

- Ufolio left open with nobody at the Mac now uses next to no processor time: about 0.02
  seconds a minute, down from 2.4. The start page's little moves (the saucer pet, shooting
  stars) only play while you're using the mouse or keyboard, so a new tab sitting open no longer
  keeps your Mac working.
- When news can't load (offline, say), the start page shows a still note with Try Again,
  instead of a shimmering placeholder that ran for as long as the page was open.
- The check that the tab you're looking at never stays with its video held paused now happens
  when you click in the page, instead of every second and a half (which kept waking the page).
- Tabs opened in the background keep their sound and video waiting until you switch to them.
- A few lists kept during a long session (sites with no icon, recent visits) now tidy themselves.
- Settings › Privacy & Security says correctly when Auto-play changes apply.

## 0.52.0-beta.1: a new look for Force Field (beta)

Everything in 0.51.2 (YouTube videos start straight away), plus:

**Force Field, redesigned** (the animation is unchanged)
- Its own deep-space look, in Day and Night alike: violet light from above, a faint green beam
  behind the count, and frosted glass cards with light-catching edges.
- A status pill above the count ("Shield up · Standard"), and a bigger, glowing count.
- Ads, Trackers and Fingerprint in one instrument strip, each with a slim gauge showing its
  share of what was blocked.
- The site in a glowing orb with a clear "Protected by Force Field" or "Off for this site".
- This site's settings with coloured icon tiles, and the actions as glass pills.
- The footer adds what was blocked today and this week.

## 0.51.2: YouTube videos start straight away

- A video you open yourself (a YouTube link, from a bookmark or the address bar) now starts
  playing by itself, as in Safari and other browsers. Ufolio made you click play again, so
  videos seemed slow to start. With Auto-play set to "Stop media with sound" (the default),
  pages that open by themselves still can't play sound. Measured on a YouTube video: it never
  started by itself before; now it plays in about 3 seconds on a first visit, and under 2 with
  Instant pages.
- A video that sometimes wouldn't play at all until Ufolio restarted: a page paused from the
  heavy page warning stayed frozen for the next page in that tab, and could even be reused
  frozen for the next visit to that site. It's now unfrozen whenever you move on, close it or
  it sleeps, and the tab you're looking at is never left with its video held paused.
- A floating Picture in Picture video closes properly when its tab closes.
- Settings › Keyboard warns if a shortcut you choose is already ⌘1–⌘9 (tabs) or ⌃1–⌃9 (Orbits).

## 0.51.1: twenty improvements

**Tabs**
- ⌘1 to ⌘8 go to that tab and ⌘9 to the last one; ⌃Tab and ⌃⇧Tab go to the next and previous
  tab, as in other browsers.
- Middle-click a tab (press the scroll wheel) to close it.
- Closing tabs one after another with their close buttons: the tabs keep their widths while the
  pointer stays in the tab bar, so the next close button is right under it.
- After a restart, Ufolio reopens on the tab you were using, not the first one.
- ⌘W on a pinned tab keeps it, and moves to a normal tab, as in Safari (its menu still closes it).
- Tab previews appear in a small window that never takes the keyboard away from the address bar
  or the page you're typing in.
- Tab previews off in Settings now really costs nothing: no picture is taken as you switch tabs.

**Links and the mouse**
- Right-click a link for Open Link in New Tab and Open Link in Background Tab.
- Your mouse's Back and Forward buttons work anywhere in the window, not only over the page.

**Speed and memory**
- The History window and the sidebar's History list search and sort away from the main thread:
  with the sidebar open, all of history used to be sorted again on every page you visited.
- When Ufolio is over its memory limit, the pages kept for an instant Back go before any tab is
  put to sleep.
- In Battery Saver and Eco, the Instant pages switch shows that it's off (it was already paused
  there) and comes back as you set it when you leave.

**Privacy and safety**
- Ufolio never connects ahead to an ad or tracking server (pointing at an ad link used to, which
  told it your IP address), and never loads one ahead as an instant page.
- Clear History also clears the cookie auto-cleaner's record of when you last used each site.
- A site can't stack up "Connect Hushlist?" questions by asking over and over.

**Fixed**
- "After 15 minutes away" (Settings › Passwords › Security) now means 15 minutes since you last
  used it: it asked again every 15 minutes even while you were signing in to things.
- Memory Saver no longer puts a tab with a floating Picture in Picture video to sleep.
- International addresses written in Latin letters show as written (münchen.de, not
  xn--mnchen-3ya.de) in the address bar and tab titles. Names mixing alphabets to look like
  another site still show in their raw form.

## 0.51.0: Instant pages, no more password prompts, Send to iPhone

Everything from the 0.51 betas, now for everyone.

**Instant pages** (Settings › Performance › Speed, on by default)
- Ufolio starts loading the page you're about to open, so it's already there when you get to it:
  the address you're typing (after a short pause), the suggestion you arrow to, the favourite,
  suggestion or bookmark you rest the pointer on, and the link you press. A page loaded this way
  shows in 1 to 10 milliseconds instead of 80 to 550.
- Back to the page you came from is instant, at the same scroll position, and so is Forward.
- Safe by design: one page at a time, muted, with Force Field on; no pop-ups, downloads or
  dialogs from a page loading in the background; never for look-alike sites, sign-out links or
  sites you've never visited; never in Stealth windows or Power Saver.
- Sites like YouTube and Twitch, which switch videos with their own code, aren't loaded twice.

**Passwords without the prompts**
- Save a password once and it simply fills in from then on. Passwords and cards now live in
  Ufolio's own vault, encrypted with AES-256, instead of the macOS keychain (which asked for your
  Mac password again after every update).
- Passwords already in your keychain move into the vault one at a time, the first time each is
  used: macOS asks once for that password, then never again.
- Ufolio offers to save on many more sign-ins, including two-step ones.
- Settings › Passwords › Security: choose whether filling asks first (never, by default).
- Importing passwords from another browser no longer asks for your Mac password for each one.

**New**
- **Send to iPhone** (⋯ menu, or File › Send to iPhone…): AirDrop, the Share menu or a QR code.
  No account, no server.
- **Split View**: drag a link from one side to open it on the other (⌥ for a new tab), or switch
  on "Open links in the other pane".
- **Tab previews**: rest the pointer on a tab to see its page, without waking it.
- **Picture in Picture on tab switch**: a playing video floats when you switch tabs and goes
  back when you return. Turn it off per site from the tab's menu.
- **Downloads**: sort into folders by type, and Open Folder.
- **Cookie auto-cleaner** (Settings › Privacy & Security, off by default): clears sites you
  haven't used for 30 days, never ones you're signed in to or have open.
- **Heavy page warning**: a quiet bar when a page keeps your Mac busy, with Pause Page.
- **Crash and hang log**, kept on your Mac only. After a crash, the next launch says so.
- **Your mouse's side buttons** go Back and Forward, as do three-finger swipes.

**Fixed**
- Routers, printers and other devices on your network (192.168.1.1, http://router…) open again:
  HTTPS upgrade forced them to https, which most don't have.
- A site with no secure version at all (an old site, or a hotel or café Wi-Fi sign-in page) now
  offers "Open Insecure Version" on its error page, instead of being impossible to open.
- The address bar opens example.com?q=1 and example.com#section (it searched for them),
  searches for email addresses instead of opening them, and opens IPv6 addresses like [::1].
- A video you popped out into Picture in Picture keeps playing when you switch tabs (a silent
  one froze), and its tab isn't put to sleep.
- Element Zapper: zapping a plain wrapper on a page could hide every element of that kind on the
  site, leaving it blank.
- Plus every fix from 0.50.1 to 0.50.5, and dozens more from the betas: Back and Forward
  through several instant pages, history, Reader and translation on instantly opened pages, the
  Force Field counter, the hang log, tooltip crashes and more.

Smoother animations throughout (how things move, not what they do), all still off with Reduce
Motion.

## 0.51.0-beta.10: quicker on YouTube and other video sites (beta)

- Clicking a video on YouTube or Twitch no longer loads a whole second copy of the site in the
  background. Instant pages starts loading a link the moment you press it, but these sites
  switch videos with their own code, so that copy was never used: it only competed with the
  video you'd clicked (about 80–90 ms slower on every click, plus its memory and data). Ufolio
  now learns which sites work this way and stops loading their own links ahead.
- Video pages no longer bring up the "this page is slowing down your Mac" warning just for
  playing a silent or muted video (Twitch's autoplay, for example).

Measured on this Mac against plain WebKit (the engine on its own, as Safari uses it), Ufolio
loads YouTube and Twitch as fast or faster: a YouTube video is ready in about 2.9 s on a first
visit against WebKit's 4.6 s, because the ads never download.

## 0.51.0-beta.9: twenty fixes, faster Instant pages (beta)

Everything in 0.50.5 (four fixes), plus:
- Instant pages:
  - Back reaches every page after several instant pages in a row (after two, it lost the first);
  - a page opened partway through loading now gets added to history, and offers Reader and
    translation, which it used to skip;
  - visits aren't counted twice;
  - the Force Field counter shows what was blocked on the new page, not the old page's number;
  - going Back to a kept page updates Reader and translation for that page, and clears a paused
    heavy page, look-alike warning or floating video that belonged to the page you left;
  - preloaded pages are laid out at your window's size, so they appear without reflowing;
  - links that do something rather than show something (sign out, unsubscribe, delete) are
    never loaded early;
  - typing an address only preloads it if you've been to that site before (a pause partway
    through "google.com" used to load google.co);
  - pages kept for Back in a background tab are let go after five minutes, to save memory;
  - a preload is thrown away when its tab closes, and never used if the tab's Orbit has moved
    to another profile since;
  - links that sites open with a script just after your click use the preloaded page too.
- The cookie auto-cleaner: Clean Now updates "Last cleaned", and the Keep box only accepts real
  site names.

## 0.51.0-beta.8: twenty more fixes (beta)

Everything in 0.50.4 (ten fixes), plus:
- Instant pages:
  - a page loading in the background no longer plays its videos;
  - the page you swapped away from stops playing, instead of carrying on out of sight;
  - preloaded pages follow your JavaScript settings (a tab with JavaScript off, and sites set to
    block all scripts in Force Field), which they used to ignore.
- Send to iPhone: the AirDrop button greys out when AirDrop is off or unavailable, and the File
  menu item is never wrongly greyed out.
- Tab previews no longer pop up while you're dragging tabs, and checking for one no longer
  decodes its picture.
- Split View: the drop highlight always clears, even if you cancel a drag over the other side.
- The hang log only watches while Ufolio is in front: in the background macOS slows apps on
  purpose, which isn't a hang.
- A page you paused from the heavy page warning, then put to sleep, no longer shows as paused
  after it wakes.

## 0.51.0-beta.7: twenty fixes (beta)

Everything in 0.50.3 (seventeen fixes to downloads, bookmarks, Reader, translation, Find, the
Command Palette, Orbits, Settings, the torrent app list, galaxy rank and offline back-off), plus:
- Send to iPhone: a very long address (too long for a QR code) now says so, instead of spinning.
- Picture in Picture on tab switch: switching straight back no longer pauses the tab you've
  returned to.
- Forget This Site also removes the cookie auto-cleaner's note of when you last used the site.

## 0.51.0-beta.6: Send to iPhone, steadier, smoother (beta)

**Send to iPhone** (⋯ menu, or File › Send to iPhone…)
- Send the page you're on to your iPhone by AirDrop, through the Mac's Share menu (Messages,
  Mail, Notes…), or with a QR code your iPhone's camera can read. No account, no server: the
  QR code is made on your Mac only when you ask, and nothing runs in the background.

**Steadier**
- Removed hover tooltips from things that disappear under the mouse (address-bar suggestions,
  start-page favourites and suggestions, bookmark bar items, password rows, Orbit buttons and
  more). macOS could try to show a tooltip for something already gone and crash Ufolio.

**Smoother** (how things move, not what they do)
- Hover highlights settle with a crisp, quick spring instead of a plain fade.
- Panels, bars and cards appear and disappear with a smooth spring: a soft start and stop,
  and fluid if you change your mind halfway.
- Dialogs settle in with the faintest scale as they fade in.
- The start page's sections rise in more smoothly, with a slightly tighter stagger.
- All of it still switches off with Reduce Motion.

**Look**
- The heavy page and torrent site bars now match Ufolio's other bars: a hairline above, an icon
  tile, and they slide in.

## 0.51.0-beta.5: six new features (beta)

**Tab previews**
- Rest the pointer on a tab (along the top or down the side) for a small picture of its page.
  It's the picture taken when you last left that tab, or the one from when it went to sleep:
  the page is never woken or kept running for it. Switch off in Settings › Appearance.

**Downloads**
- New in the downloads panel: sort into folders by type (Images, Documents, Videos, Music,
  Archives, Installers, Torrents), off by default, and Open Folder. Pause, resume and Show in
  Finder are there as before.

**Cookie auto-cleaner** (Settings › Privacy & Security, off by default)
- Deletes the cookies and data of sites you haven't used for 30 days. Never sites open in a
  tab, sites you have a saved password for (so you stay signed in), or sites you choose to keep.
- Runs quietly at most once a day, only after a couple of quiet minutes, never while you're
  browsing. Settings shows what it cleaned, with "Keep in Future" next to each.
- When you switch it on, every site you already have starts its 30 days from then, so nothing
  is wiped all at once.

**Heavy page warning**
- When a page keeps the processor busy for a while (about a minute and a half), a quiet bar
  says "This page is using a lot of energy", with Pause Page (freezes it completely), Reload
  and Put to Sleep. Short bursts never set it off, and pages playing sound are left alone.

**Crash and hang log** (kept on your Mac only, never sent anywhere)
- If Ufolio quits unexpectedly, the next launch says so and offers the details.
- If Ufolio stops responding for more than two seconds, that's noted too.
- It costs nothing while Ufolio runs. Measured idle: the same processor time and memory with it
  on or off. A crash is written using only what was prepared at launch, and the hang check is
  one cheap ping a second that does nothing unless Ufolio is stuck.
- Logs: ~/Library/Logs/Ufolio Browser.

**Picture in Picture on tab switch** (Settings › Appearance, on by default)
- A video playing in the tab you leave pops out into a floating window, and goes back into its
  tab when you return. Turn it off for any site from the tab's right-click menu.

## 0.51.0-beta.4: password moving fixed, and more fixes (beta)

**Passwords**
- Older passwords still in your keychain no longer have to be moved all at once (macOS asked for
  your Mac password once for every single one). They're listed as normal, and each moves into
  Ufolio's vault the first time it's used: macOS asks once for that password, then never
  again. No more popup at launch. Settings › Passwords › Move All is still there if you want
  it, with a clear warning.
- Ufolio offers to save your password on many more sign-ins: web apps that never send a normal
  form, and the password step of two-step sign-ins (with the email from the step before).
- Offering to save never makes macOS ask for your Mac password.
- "Later" on moving keychain passwords waits a week instead of asking at every launch.

**Look**
- Settings opens in the middle of your Ufolio window, not at the far right.
- The Force Field shield is the same size as the Stealth alien and the ⋯ menu.

**Instant pages and Split View**
- Back from a page opened instantly in a new tab no longer leads to an empty start page.
- Pressing on a link a web app handles itself no longer keeps a hidden copy of the page loading
  for 30 seconds: it's let go after 2.
- Holding an arrow key through address-bar suggestions no longer starts and discards a page for
  each one.
- Two addresses differing only in capitals (like /wiki/Apple and /wiki/APPLE) are no longer
  treated as the same page.
- A crash or error screen from the previous page no longer stays over an instantly opened page.
- Dragging a link between Split View panes recognises more ways WebKit starts a drag.

**Also in 0.50.1**: eight fixes (tooltip crashes, the arrival sound, history clearing at
launch, the saucer pet and planet following Effects, the rollback question, the update log, big
torrent files).

## 0.51.0-beta.3: no more password prompts (beta)

**Passwords and cards, kept by Ufolio itself**
- Save a password once and it simply fills in from then on: no Mac password, no Touch ID.
- Saved passwords and cards now live in Ufolio's own vault, encrypted with AES-256, with its key
  in a file only your Mac account can read (and FileVault protecting both while your Mac is
  locked or off). macOS no longer asks for your Mac password to let Ufolio into the keychain,
  which it did again after every update.
- Passwords already in your keychain: Ufolio offers once to move them in. macOS asks one last
  time, and the keychain copies are left as they are. You can also do it later from
  Settings › Passwords.
- Settings › Passwords › Security: choose whether filling asks first. Never ask (the default),
  once each time Ufolio opens, after 15 minutes away, or every time. Seeing or copying a
  password in Settings always asks.

Also includes everything in 0.51.0-beta.1 and beta.2 (Instant pages, Split View link dragging).

## 0.51.0-beta.2: drag links between Split View panes (beta)

**Split View**
- Drag a link from one side and drop it on the other: it opens there, replacing that side's
  page. It works both ways, and with dragged pictures and web addresses too.
- Hold ⌥ as you drop to open it in a new tab instead.
- The side you're dragging over gets a soft highlight (it simply appears, without fading, with
  Reduce Motion or Effects off).
- Only web addresses are accepted: never javascript:, file: or data: ones. Dropping files or
  text onto a page (uploads, search boxes) works as before, since only drags from the other
  pane are taken.
- New: "Open links in the other pane" (the arrow button at the top of either side, off by
  default). A normal click on a link opens it on the other side: a list on one side, reading
  on the other. Switches itself off when you leave Split View.

Also includes everything in 0.51.0-beta.1 (Instant pages).

## 0.51.0-beta.1: Instant pages (beta)

**Instant pages** (Settings › Performance › Speed, on by default)
Ufolio now loads the page you're about to open in the background, so when you open it, it's
already there. Measured on Google, a Google search, Apple, Wikipedia, Amazon, the New York Times
and Stack Overflow: a preloaded page shows in 1 to 10 milliseconds, instead of 80 to 550.
- In the address bar, after a short pause in typing, Ufolio loads what Return would open: the
  search results for what you've typed (only if you already let Ufolio send your typing to
  your search engine for suggestions), or the address you've typed.
- Arrow onto a suggestion and it starts loading straight away.
- Rest the pointer on a favourite, a start-page suggestion or a bookmark, and it starts loading.
- Press on a link and it starts loading a moment before the click lands.
- Back from a page opened this way swaps the page you came from straight back in (in about a
  millisecond, at the same scroll position), and Forward the other way.
- Safe by design:
  - one page at a time, muted, with Force Field and every protection on;
  - no pop-ups, downloads, dialogs or password prompts from a page loading in the background;
  - never for look-alike sites or tracking redirects;
  - never in Stealth windows or Power Saver;
  - unused pages are thrown away after 30 seconds, and kept pages are let go when a tab
    sleeps or memory runs short.

**How it was found**
- Timed against a bare copy of WebKit (Safari's engine) on the same sites, Ufolio already
  paints pages as fast or faster, and its protections cost no time: Force Field makes heavy
  pages faster, and Ufolio's page scripts make no measurable difference.
- The rest of the gap to Firefox-based browsers like Zen is the engine itself. Loading the page
  before you open it is how Ufolio closes it.

## 0.50.0: safer updates, and an optional beta channel

**Going back if an update won't start**
- When Ufolio updates, it now keeps the version it replaced, instead of deleting it.
- Straight after updating, Ufolio checks the new version really starts. If it closes by itself
  twice as it opens, you're asked whether to go back to the version that worked.
- If a version later fails to start twice in a row, Ufolio offers to go back the next time
  it's opened, before anything else.
- After going back, that version is skipped until a newer one comes out.
- Your bookmarks, history, passwords and settings stay where they are either way.

**Beta versions** (Settings › Software Update, off by default)
- Switch on "Get beta versions" to try new versions early.
- Betas are checked exactly like regular updates: signed with Ufolio's key, fingerprint
  checked, and verified as a real copy of Ufolio before anything is installed.
- Version order now understands betas: 0.51.0-beta.2 comes after 0.50.x and before 0.51.0, so
  beta testers move on to the finished version when it's out.

## 0.49.2: memory comes back when you close tabs

Checked with a test that opens 30 tabs of busy sites (BBC, YouTube, Reddit, Amazon and more),
then closes them:
- every closed tab and its web page is freed: nothing is kept alive by mistake;
- memory falls from about 5.4 GB with 30 tabs open to about 330 MB once they're closed,
  close to where Ufolio started.

**Fixed**
- 0.49.0's speed-up keeps recently used page processes ready for reuse, and after closing tabs
  it held on to up to ten of them, about 2 GB. They're now let go 30 seconds after you close
  tabs (so Reopen Closed Tab is still instant just after), and straight away whenever Ufolio
  goes over its memory limit or your Mac runs short of memory.

## 0.49.1: heavy work moved off the main thread

Ufolio's windows stay responsive while it reads, writes and searches: that work now happens
in the background, and the main thread only draws and responds to you.

- History is read from disk in the background as Ufolio opens. With thousands of pages it used
  to hold up the first window. Pages you visit meanwhile are kept, and history is never written
  over before it has been read.
- Typing in the address bar searches your history in the background, so a big history can't
  make typing stutter. Earlier matches stay in the list while the new search runs.
- Saving a password after you sign in, filling a password, and opening Settings › Passwords
  now read and write the keychain in the background. Each could freeze the window, especially
  when macOS asks for permission.
- If WebKit's compiled copies of Force Field's lists go missing (after a cleaner app, say),
  their rules are now read in the background before being rebuilt. A big list like Hushlist
  is tens of megabytes and used to freeze Ufolio as it opened.
- As Force Field's lists finish loading at launch, they're applied to your tabs once, instead
  of once per list (about ten times in a row).

## 0.49.0: much faster browsing

Measured on a test copy of Ufolio, loading eight busy sites three times each, before and after:
- Back and Forward: about 2 seconds down to about 0.3 seconds (84% faster).
- Returning to a site: it appears 22% sooner and finishes loading 26% sooner.
- A site you've never visited appears 15% sooner.

**What changed**
- Safari's engine settings, which WebKit switches off for every app except Safari, are now on:
  - a fresh page process is kept ready, so a new tab or site doesn't wait for one to start;
  - recent sites' processes are kept and reused;
  - the addresses of links on a page are looked up before you click.
- Back and Forward show the page straight from memory. Memory Saver used to switch this off,
  so Back reloaded the whole page. WebKit still lets these pages go when memory runs short.
- Ufolio gets the connection to a site ready before you get there, so pages start sooner:
  - when you point at a link (or press on it);
  - when you point at a favourite, a suggestion on the start page, or a bookmark;
  - while you type in the address bar, to the site you're most likely heading for;
  - to your search engine as soon as you click into the address bar.
  Only the connection is opened. Nothing is downloaded until you choose.
- Pages that say what you're likely to open next can have it fetched ahead of time.
- The look-alike site check no longer rebuilds its list of your sites in the middle of
  opening a page.
- All of these step back in Power Saver mode, and cached page processes are given back when
  your Mac runs short of memory.

**Fixes**
- After Back or Forward showed a page from memory, the title in History, the Reader button
  and translation weren't updated. They now are.

## 0.48.2: Ufolio opens again

- Fixed: Ufolio 0.48.0 and 0.48.1 closed straight away when opened, if you had any bookmarks.
  Setting up the bookmarks list asked for itself while it was still being created. Sorry!

## 0.48.1: one family of toolbar icons

**Toolbar**
- Every toolbar icon now has the same size, the same line weight and the same grey, so none
  stands out more than another. Colour only ever means "on".
- Force Field is now a shield, which everyone reads as protection: ticked and in colour while
  it's blocking, crossed out and grey when it's off for the site.
- The Stealth alien is drawn as an outline to match the other icons. It's lavender inside a
  Stealth window.
- The ⋯ menu is now a circled ⋯, the same shape and weight as the Downloads icon.
- With tabs down the side, Downloads and extension buttons now sit at the top right with the
  other icons, instead of in the tab column.
- Clearer tooltips: "Force Field: blocking ads and trackers on this site", "New Stealth
  Window: browse without saving history".

## 0.48.0: torrent tools (off unless you switch them on)

**Torrent tools** (Settings › Privacy & Security › Torrent tools)
- Off by default. With the switch off, Ufolio behaves exactly as before. Ufolio never downloads
  or shares torrents itself: it shows you what's there and hands the link to your torrent app.
- Smart magnet links: clicking a magnet link shows a card with its name, size, file count and
  trackers when the link includes them, with Open in your torrent app and Copy Link. Choose
  the app in Settings (Transmission, qBittorrent and so on, or the Mac's default). A broken
  link says so, and with no torrent app installed you can still copy it.
- .torrent preview: when a .torrent file finishes downloading, Ufolio reads it on your Mac
  (no network, strict size and nesting limits, so a booby-trapped file can't harm it) and lists
  its files and sizes before anything opens it. It warns about:
  - programs inside a video or music download;
  - double endings such as movie.mp4.exe;
  - Windows shortcuts (.lnk);
  - hidden characters that disguise a file's ending;
  - paths that try to escape their folder;
  - the "password in a text file" archive scam;
  - "videos" with no video inside.
- Torrent site mode: on torrent sites, scripts can't open pop-ups or pop-unders, links to
  pop-under ad networks are stopped, and the page can't be swapped for another site behind
  your back. Links you click still work. A slim bar says what was stopped.
- Fake download buttons: on torrent sites, the real magnet and .torrent links get a green
  outline. Fake "Download" and "Play now" ads, and programs disguised as videos, are marked in
  red. Invisible layers that turn every click into a pop-under lose their grip.

**Smaller on disk**
- Ufolio now clears its page cache as it quits, so between sessions it takes almost no disk
  space. Your sign-ins, cookies and site settings are kept. Switch it off in Settings ›
  Performance › Disk if you'd rather sites load from the cache after a relaunch.
- While Ufolio is open, the page cache is kept under 100 MB (it was 300 MB), and sites' own
  offline caches under 400 MB (it was 1 GB). The disk is checked every half hour, not only
  just after launch.

**Fixes**
- Fixed a crash when the mouse was over a button as it disappeared: Reader's close and text
  buttons, Split View's Close This Side, the Find bar after pressing Esc, sidebar bookmarks
  deleted from their menu, and the Force Field panel's buttons that close it.
- Camera, microphone and location answers given "until Ufolio quits" in a Stealth window no
  longer apply in normal windows, and normal windows' answers no longer carry into Stealth.
- The Bookmarks menu now lists the window's own profile's bookmarks, and updates when you add
  one there. It used to decide from the default profile's bookmarks whether to show any.

## 0.47.1: ten fixes

**Profiles**
- Fixed: recently closed tabs were shared by every profile. A tab closed in your work profile
  showed on your personal start page, and Reopen Closed Tab brought it back there without
  that profile's sign-ins. Each profile now sees and reopens only its own closed tabs, and
  deleting a profile clears them.

**Restoring tabs**
- Fixed: with two or more windows open, Restore last session brought back only the window
  that changed last. Every open window's tabs now come back.

**Address bar**
- Typing a number like 3.14 or 10.50 now searches for it. It used to open it as an IP address.
- "Localhost:3000" and other capitalised local addresses now open over plain http like
  "localhost" does.

**Clean Links**
- Google redirect links and AMP pages are now skipped on Google's regional sites too
  (google.co.uk, google.de, google.com.au and so on), not only google.com.

**Downloads**
- Two files with the same name downloaded at the same moment no longer get the same name
  (one overwrote or failed the other).
- Very long file names in Japanese, Chinese or with emoji are now shortened to fit macOS's
  limit. Those downloads used to fail.

**Bookmarks, news and imports**
- Imported bookmark titles now show apostrophes, quotes and dashes properly, not codes like
  "&#8217;". Text like "&amp;lt;" is no longer sometimes decoded twice.
- The same fix for News headlines.
- Importing passwords from a CSV saved by Excel (UTF-16 or Windows text) now works instead
  of failing with a text encoding error.

**Galaxy rank**
- Days now count when you open a window, not only when the start page shows, so people
  whose new tabs open a website rank up too.

## 0.47.0: a saucer pet, warp speed, galaxy ranks and a planet of the week

**Saucer pet**
- A little hand-drawn saucer with big friendly eyes hovers in a corner of the start page. Now
  and then it bobs, blinks, chases its rim lights round or does a little spin, then rests.
  Click it to make it spin.
- It levels up as you go: an antenna for your first achievement, a glow underneath for the
  second, a tiny moon of its own for the third, and a gold rim when you reach Comet Chaser.
- It only appears where there's clear space, so it never sits on anything. Right-click it, or
  use Settings › Appearance, to hide it.

**Warp speed**
- Switching Orbits gives a quick streak of stars, over in under half a second. It's drawn on
  top of the window, so it never slows the switch down.

**Galaxy rank**
- Eight ranks, from Cadet to Galactic Admiral, earned slowly by the days you use Ufolio, each
  with its own badge. The first time, days already in your history count, so you don't
  start from scratch.
- Shown quietly on the weekly report card, with all eight in Settings › Appearance. No pop-ups.

**Planet of the week**
- A painted planet turns slowly in the corner of the start page, a different one every
  Monday (all eight planets, and Pluto). Click it for a card of facts from NASA.
- It turns on macOS's animation engine, not by redrawing the page, and pauses while the window
  isn't in front. Right-click it, or use Settings › Appearance, to hide it.

All of these stay still with Reduce Motion or Effects off.

## 0.46.2: Stealth Mode is smooth again, and a new Stealth icon

**Stealth Mode**
- Fixed: Stealth windows lagged when hovering over buttons, opening tabs and so on. The saucer
  on the Stealth start page shimmered non-stop, which redrew the frosted window behind it on
  every frame. It now shimmers a couple of times as the page opens, then rests.
- Fixed: the cloaking field round a Stealth window's edge stayed as a window-sized layer over
  the page (sweeping again every 15 seconds), slowing every redraw. It now sweeps once as the
  window opens and is then removed.
- New Stealth icon: an alien in dark glasses, travelling incognito, so it no longer looks like
  the Force Field saucer beside it.

**Privacy**
- Fixed: the Abduction log, the start page's tracker list and the Force Field panel fetched
  each blocked tracker's icon from the tracker's own server, contacting the very trackers
  Ufolio had just blocked. They now only use icons already saved, or a letter.

**Fixes**
- Fixed a crash when the mouse was over a tab's close, mute or other small button as it
  disappeared (closing tabs quickly, side tabs, History, Downloads, the start page, banners
  and tips). Those buttons no longer use hover tooltips, which caused it.
- Fixed the same crash in Settings rows (Reset, Delete) and on Remove Orbit.
- Deleting a saved password or card in Settings › Passwords now asks first. One stray click
  used to delete it for good.
- The little saucer on the start page bobs a few times as it arrives, then rests, instead of
  bobbing (and keeping the Mac working) the whole time.
- The daily tip, daily photo and the count of days you've used Stealth Mode now change at your
  own midnight, not at midnight in London (1 am in a UK summer, the evening in America).
- Clicking Connect again while Hushlist is still downloading no longer queues a second full
  download and rebuild of its 240,000 rules.

## 0.46.1: a new look for Stealth Mode

**Stealth Mode**
- The whole Stealth window is now one dark frosted glass with a single purple tint, like a
  normal Ufolio window: the toolbar, tab column and start page all match, instead of separate
  solid purples and a grey top row.
- The glasses are gone: Stealth Mode's emblem is now a saucer shimmering in and out of its
  cloaking field, and the Stealth button is a little cloaked saucer. (Still with Reduce Motion
  or Effects off.)

## 0.46.0: profiles with their own history and bookmarks

**Profiles, fully separate**
- Each profile now has its own history and bookmarks, as well as its own cookies and sign-ins.
  A window shows the history and bookmarks of its current Orbit's profile: the bookmarks bar,
  start page, sidebar, address bar suggestions, Command Palette and the star all follow it.
- Everything you had before is the Default profile, exactly where it was.
- The History window opens on the profile you're using, with a switcher at the top when you
  have more than one.
- Clear History and Forget This Site cover every profile. Deleting a profile also deletes its
  history and bookmarks.

## 0.45.0: close encounters

**New: Area 51 theme 👽**
- One complete alien look: radioactive-green accents, green-tinted glass on the window, sidebar
  and tab column, a green aurora on the start page and a green saucer, in light and dark mode.
  Settings › Appearance › Theme.
- On 2 July, World UFO Day, Ufolio wears it for the day and says hello.

**New on the start page**
- Abducted counter: how many ads and trackers the saucer abducted today. Click it for the
  abduction log of today's trackers and the companies behind them.
- Weekly report card: "This week the saucer zapped N ads and trackers and saved you X MB."
- Achievements (opt-in, never any pop-ups): First Contact at 1,000 blocked, Area 51 for
  Stealth Mode on 30 days, Lightyear at a million. Turn them on in Settings › Appearance.
- Signal from space: one small tip a day about something you haven't tried yet. Close it for the day.
- Live Sky background: the start page follows the real time of day, from dawn to a starry
  night with the odd shooting star.
- Ufolio's birthday: a little saucer in a party hat on the anniversary of the day you started using it.

**New little touches**
- Stealth windows have a faint cloaking-field shimmer round their edge.
- Finished downloads are beamed up into the Downloads button with a soft glow.
- Try typing "take me to your leader" in the address bar.
- All of these follow Reduce Motion, and Settings › Appearance › Effects turns them off.

**Fixes**
- Nothing gets through a dialog, the setup guide, the palette, Reader, the sidebar or the address
  suggestions to the page underneath: no clicks, scrolling, hover effects or link cursor.
- Automatic cookie-banner rejection only ever clicks inside real consent pop-ups (it could press
  "Decline" in other dialogs, such as a meeting invitation).
- A filter-list update that suddenly shrinks a big list (a hotel wifi login page, say) is
  ignored, and the current list is kept.
- A site asking for a username and password several times at once shows one sign-in box.
- An address guessed from what you typed is forgotten once it has loaded.

## 0.44.0: the arrival sound, and a lighter footprint

**New: the arrival sound 🛸**
- Ufolio plays a short, retro sci-fi "ooo-weee-ooo" as it opens. Made from scratch in code,
  so it adds almost nothing to Ufolio's size. Turn it off (or play it again) in
  Settings › Appearance.

**Much less disk space**
- Website caches are kept in check, as other browsers do: past 300 MB (or 1 GB of site data)
  they're cleared at launch. Sign-ins and site settings stay. Before, they could grow to gigabytes.
- Compiled filter lists, rule files and extension files that no longer belong to anything are
  removed at launch (Hushlist alone is tens of megabytes, and old copies were never cleaned up).
- Update downloads that were never installed are cleaned up.

**Fixes**
- Clean Links can no longer get stuck in a loop on a site that keeps redirecting back to its
  tracking address.
- Windows last used on a display that's no longer connected open on screen.
- Release notes on GitHub (and in the updater) show "What's new" again.
- Cancelling the Orbit editor removes a profile you made in it.
- "Add Orbit" is greyed out at the 12-Orbit limit instead of doing nothing.
- The start page's town search can't end up handling keys twice.

## 0.43.15: ten more fixes

**Settings reach open tabs**
- Changing the power mode (or unplugging into Battery Saver), pop-up blocking or fraudulent
  website warnings now applies to tabs already open, not only new ones. Sleeping tabs pick up
  the current settings when they wake.
- Changing the default page zoom updates open pages still at the old default.

**Tabs**
- Muted tabs stay muted from the start when they wake from sleep.
- Actual Size (⌘0) also resets trackpad pinch-zoom.
- In a Stealth window, Reopen Closed Tab brings back that window's own closed tabs (kept in
  memory only), not one closed in a normal window.
- Dropping a file from Finder onto a page opens it again.

**Fixes**
- Updating or reinstalling an extension that's running no longer breaks it until a restart.
- Plain http websites can always load (Ufolio now has the standard browser exemption from
  Apple's App Transport Security for web pages).
- Old site icons are deleted after two weeks, instead of collecting for every site ever visited.
- History is trimmed in memory as well as on disk, so very long sessions don't keep growing it.

## 0.43.14: ten more fixes

**Smoother**
- Typing in the address bar no longer redraws the whole window for every letter; only the
  suggestions update.
- With Magic Theme off, moving between sites no longer redraws the whole window.
- The ⋯ menu button no longer redraws whenever anything in the window changes.

**Keyboard**
- Pressing Esc in the address bar hands the keyboard back to the page, so Space and the arrow
  keys scroll it again.
- After switching or closing tabs, the keyboard goes to the page you're now looking at.

**Fixes**
- Pinned tabs come back when you close the window and open it again (they were missing until
  Ufolio restarted).
- Extensions are told when windows open and close, so they see a reopened window's tabs, and
  closed windows are let go.
- The address bar shows an open padlock when a secure page loads parts of itself insecurely.
- A local file open in a tab shows its name rather than "New Tab".
- Release notes on GitHub include each version's "What's new" again.

## 0.43.13: ten more fixes

**Fixes**
- Links opened in the background with ⌘-click line up in the order you opened them (they came
  out backwards).
- A zoomed page keeps its zoom when its tab sleeps and wakes, or when an extension is added.
- The Command Palette's top result stays selected while you type, even if the pointer is
  resting over the list (Return could run whichever row was under the pointer).
- The look-alike site warning and Reader mode can't be clicked through to the page underneath.
- Save Page As on a PDF saves the PDF itself.
- Recording a shortcut with Shift and a symbol key (like ⇧⌘[) now works properly.
- The window buttons stay lined up with the tabs after switching between Light and Dark.

**Smoother**
- The list of Safari extensions in Settings no longer looks up every app's icon on every update.

## 0.43.12: ten more fixes

**Pages that couldn't load**
- When a page can't load (no connection, no such website, a bad security certificate, or
  blocked by Force Field), Ufolio now says why, with a Try Again button. Before, nothing happened.
- Sites that ask for a username and password the old way (routers, NAS boxes, staging sites)
  now show a sign-in box instead of just failing.
- A site's Download button for a PDF or picture now downloads it, rather than opening it in the tab.

**Security**
- Only a page you can see may ask for your camera, microphone or location. A background tab's
  request used to pop up over whatever page was in front.

**Fixes**
- Changing Light/Dark appearance in Settings (or the View menu) applies straight away, even with
  the browser window closed.
- Password files exported by some password managers or saved from Excel now import (an
  invisible marker at the start made them look like the wrong kind of file).
- A filter list removed while it was updating stays removed, and switching a list off during
  an update is kept.
- News stories without a date, or dated in the future, no longer sit at the top.

## 0.43.11: ten more fixes

**Stealth Mode leaves no trace**
- Turning Force Field off for a site, changing a site's settings, or hiding elements from a
  Stealth window now lasts until Ufolio quits, instead of being saved (which recorded the site).
- Stealth windows don't offer to save passwords you type, except a strong password Ufolio
  made for you there.

**Tabs down the side**
- The tab list only builds the rows you can see, so lots of tabs stay quick.
- Switching to a tab further down the list scrolls it into view.

**Fixes**
- Menu items for the sidebar, Reader, muting and pinning have labels that are always right
  (they could show the opposite of what they'd do).
- Sites that update the "#section" part of their address as you scroll no longer count each
  change as a new visit in history.

**Smoother**
- The downloads list no longer asks macOS for every file's icon on every update.

## 0.43.10: ten more fixes

**Tabs**
- With lots of tabs along the top, the row now shows the tabs around the one you're on and a
  "+N" button listing the rest. Before, extra tabs (and the + button) ran off the edge, out of reach.
- A tab whose page macOS closed to free memory reloads by itself when you switch to it, as in
  Safari, instead of showing the crashed page.
- A tab that crashed and then went to sleep no longer shows the crashed page after waking.

**Fixes**
- Opening a page from the History window works even when the browser window was closed.
- Changing "Remove history items" to a shorter time takes effect straight away.
- Downloads you've moved or deleted say so in the list.
- Switching on a news topic while news is refreshing no longer leaves that topic empty.
- After connecting Hushlist from hushlist.online, the page reloads once it's really connected.

**Smoother**
- Settings › General no longer rescans for other browsers on every redraw.
- Settings no longer leaks a little memory each time it's released and rebuilt.

## 0.43.9: ten more fixes

**Security and privacy**
- Pressing Return in a website's form or search box can no longer trigger "Add to Favourites"
  or "Add to Ufolio" in the bars above the page.
- Reader mode loads its pictures privately (no cookies, nothing saved to disk), so reading in a
  Stealth window leaves nothing behind. They're also shrunk to the size shown.

**Fixes**
- Open All in Tabs loads the first page straight away and the rest when you click them, instead
  of starting every page in a big folder at once.
- Close Other Tabs and Close Tabs to the Right keep your pinned tabs.
- Move to Folder › New Folder… now moves the bookmark into the new folder.
- Turning on automatic update checks takes effect straight away, not after a restart.
- Card numbers keep only the digits 0–9 (full-width digits from some keyboards were accepted
  but rejected by checkout pages).

**Smoother**
- Folders of bookmarks are worked out once per change, so the sidebar and bookmarks bar stay
  quick with lots of folders.
- Save Page As writes big pages in the background.

## 0.43.8: ten more fixes

**Privacy**
- Forget This Site now also removes the site from your Privacy Report and deletes its saved icon.
- A pop-up window on a site where you've turned Force Field off no longer switches blocking off
  for the page that opened it.
- Local addresses like 192.168.1.1 are treated as their own sites. They were lumped together
  with every other address ending in .1.1, sharing settings and being forgotten together.

**Fixes**
- Choosing a start page photo no longer freezes the window while it copies, and your old photo
  is only removed once the new one is safely in place.
- Adding a news feed twice quickly no longer adds it twice.
- Split View in a narrow window keeps both pages on screen.

**Smoother**
- Bookmarks are saved in the background a moment after a change, so dragging to reorder a big
  collection no longer stutters.
- Mail and chat sites that keep changing their title no longer make history redraw and save
  every few seconds.
- The flying saucer in Settings › Orbits only flies while Settings is the window you're using.

## 0.43.7: ten more fixes

**Fixes**
- Quitting while files are still downloading now asks first, instead of cancelling them.
- The updater never replaces Ufolio while it's still open (for example if you choose not to
  quit after all), and offers the update again.
- Saving changes to a payment card can no longer lose the card if the save fails.
- Clicking "Add" twice on an extension no longer installs it twice at once.
- Filter lists from the web now wait their turn rather than being refused while another is
  being set up, and a mistyped address no longer confuses that.
- Filter list files are checked for size before they're read.
- Settings › Privacy: sites with both camera and microphone answers list correctly, and each
  menu changes the right one.
- Your own news feeds are limited to a sensible size and number (30), so the start page stays quick.

**Smoother**
- The setup guide's flying saucer pauses when you switch to another app.

## 0.43.6: ten more fixes

**Privacy**
- Fingerprinting protection now varies by the site in the address bar, so a tracker hidden
  inside many different sites can no longer recognise you from one to the next.

**Fixes**
- Searching for "c++" or "1+1" now searches for exactly that (the "+" used to become a space).
- Typing something like "node.js" that isn't a real website now searches for it, instead of
  doing nothing.
- ⌘W in Settings or History closes that window, not a tab in the browser behind it.
- The Bookmarks menu lists up to 40 bookmarks, so a big collection no longer slows the menu bar.

**Smoother**
- Settings › Passwords no longer looks up your contact card every time Settings redraws.
- The setup guide no longer rescans for other browsers every time the window redraws.
- The menu bar no longer re-reads your keyboard shortcuts on every refresh.
- Working out a page's language reads a sample of its text, not the whole page.
- Settings › General checks whether Ufolio is your default browser once, when you open it.

## 0.43.5: ten more fixes

**Stealth Mode leaves no trace**
- Choosing "Always Allow" or "Don't Allow" for a camera, microphone or location prompt in a
  Stealth window now lasts only until Ufolio quits, instead of saving the site to your
  permissions list.
- Choosing to visit a look-alike site anyway from a Stealth window is no longer written down.

**Start page and bookmarks**
- The start page shows up to 16 Favourites (bookmarks not in a folder). With lots of
  bookmarks, Favourites used to vanish because they didn't fit, and every bookmark's icon was
  fetched each time a new tab opened.
- The bookmarks bar only builds the bookmarks in view, so it stays quick however many you have.

**Fixes**
- "Remove history after…" now also applies while Ufolio stays open, not only when it starts.
- If your chosen download folder is gone (an unplugged drive, say), downloads go to your
  Downloads folder instead of failing.
- The downloads list is kept to the newest 300, so it can't grow forever.
- In the setup guide, going back during an import no longer jumps you forward when it finishes.

**Smoother**
- Searching in History and in the sidebar is much faster as you type.
- The start page's suggestions no longer do extra work for every bookmark you have.

## 0.43.4: ten more fixes

**Security and privacy**
- Dialogs ignore a key press in their first moment, so a site can't open a camera, microphone
  or location prompt just as you press Return and get "Always Allow" without you seeing it.
- Extensions never see a Stealth window's tab, even when a Stealth window is in front.
- Extension pop-ups never open over a Stealth window.
- A Stealth download is only resumed through a Stealth window, and a normal one never is.
- The weather is looked up for your area (to about a kilometre), not your exact spot.

**Fixes**
- Fixed a crash when a page showed the AutoFill menu while its tab wasn't on screen.
- Fixed a possible crash if the weather service sent back an impossible temperature.
- A middle-click on a link opens it in a new tab, as in other browsers.
- Ufolio recognises that it's your default browser even when run from another copy.

**Smoother**
- Switching to a sleeping tab no longer decodes its picture again on every redraw while it wakes.

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
