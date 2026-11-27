// Ufolio: YouTube ad blocking. Version: 2026112801
// Runs on youtube.com only, in Ufolio's own script world (YouTube can't see or change it). Updated weekly and signed;
// Ufolio refuses a copy that isn't signed with its own key, or that is older than the one it has.
(() => {
  'use strict';
  if (window.__ufolioYT) return;
  window.__ufolioYT = true;

  // 1. An ad that starts is muted, jumped to its end and Skip pressed, so the video comes straight on.
  // (Taking the ad slots out of the video's details, as some blockers do, now leaves YouTube's
  // player waiting on a black screen.)
  const SKIP = '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-overlay-close-button';
  // The ad's over: the video goes back to the speed and sound it had.
  function restore(player) {
    const video = player && player.querySelector('video');
    if (video && video.__ufolioRate !== undefined) {
      video.playbackRate = video.__ufolioRate;
      delete video.__ufolioRate;
    }
    // And its sound, if it had it (an ad built into the stream left the video itself muted).
    if (video && video.__ufolioMuted !== undefined) {
      video.muted = video.__ufolioMuted;
      delete video.__ufolioMuted;
    }
  }
  function skip() {
    const player = document.querySelector('#movie_player, .html5-video-player');
    if (player && !player.classList.contains('ad-showing')) restore(player);
    if (!player || !player.classList.contains('ad-showing')) return;
    const video = player.querySelector('video');
    if (video) {
      if (video.__ufolioMuted === undefined) video.__ufolioMuted = video.muted;
      video.muted = true;
      if (isFinite(video.duration) && video.duration > 0) video.currentTime = video.duration;
      // Ads built into the video stream can't be jumped past (and YouTube ignores a Skip
      // pressed by a script): those are played at 16x, so they're over in a second or so.
      if (video.playbackRate < 16) {
        if (video.__ufolioRate === undefined) video.__ufolioRate = video.playbackRate;
        video.playbackRate = 16;
      }
    }
    document.querySelectorAll(SKIP).forEach(b => b.click());
  }
  // While an ad is on, it keeps trying: switching videos inside YouTube, the ad often starts
  // before its length is known (so jumping to its end did nothing) and the Skip button appears
  // later, so a single try left the ad playing for its full length. Only while "ad-showing" is
  // on, and every quarter second at most; nothing runs otherwise.
  let retry = null;
  function watchAd() {
    skip();
    const player = document.querySelector('#movie_player, .html5-video-player');
    const showing = player && player.classList.contains('ad-showing');
    if (showing && !retry) {
      retry = setInterval(() => {
        const p = document.querySelector('#movie_player, .html5-video-player');
        if (!p || !p.classList.contains('ad-showing')) { clearInterval(retry); retry = null; restore(p); return; }
        skip();
      }, 250);
    }
  }
  // As soon as the ad's length is known, jump to its end.
  document.addEventListener('durationchange', e => {
    const p = e.target && e.target.closest && e.target.closest('.ad-showing');
    if (p) skip();
  }, true);
  // Watches just the player's class (YouTube adds "ad-showing" while an ad plays), not the page.
  let watchedPlayer = null;
  const playerWatch = new MutationObserver(watchAd);
  function findPlayer() {
    const player = document.querySelector('#movie_player, .html5-video-player');
    if (!player || player === watchedPlayer) return !!player;
    watchedPlayer = player;
    playerWatch.disconnect();
    playerWatch.observe(player, { attributes: true, attributeFilter: ['class'] });
    watchAd();
    return true;
  }
  // Until the player exists, look for it as the page builds; after that, only on page changes.
  const pageWatch = new MutationObserver(() => { if (findPlayer()) pageWatch.disconnect(); });
  const start = () => { if (!findPlayer()) pageWatch.observe(document.documentElement, { childList: true, subtree: true }); };
  if (document.documentElement) start(); else document.addEventListener('DOMContentLoaded', start);
  document.addEventListener('yt-navigate-finish', findPlayer);

  // 2. Hide ad boxes, sponsored results and the ad-blocker message.
  const css = `
    ytd-ad-slot-renderer, ytd-rich-item-renderer:has(> #content > ytd-ad-slot-renderer),
    ytd-in-feed-ad-layout-renderer, ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer,
    ytd-display-ad-renderer, ytd-compact-promoted-video-renderer, ytd-banner-promo-renderer,
    ytd-statement-banner-renderer, ytd-companion-slot-renderer, ytd-action-companion-ad-renderer,
    ytd-player-legacy-desktop-watch-ads-renderer, ytd-merch-shelf-renderer, ytd-search-pyv-renderer,
    #masthead-ad, #player-ads, #panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],
    .ytp-ad-overlay-container, .ytp-ad-module .ytp-ad-image-overlay, ytm-promoted-sparkles-web-renderer,
    ad-slot-renderer, ytm-companion-ad-renderer, ytd-enforcement-message-view-model,
    tp-yt-paper-dialog:has(> ytd-enforcement-message-view-model) { display: none !important; }`;
  const addStyle = () => {
    const style = document.createElement('style');
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  };
  if (document.documentElement) addStyle(); else document.addEventListener('DOMContentLoaded', addStyle);
})();
