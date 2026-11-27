// Ufolio: YouTube ad blocking. Version: 2026112702
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
  function skip() {
    const player = document.querySelector('#movie_player, .html5-video-player');
    if (!player || !player.classList.contains('ad-showing')) return;
    const video = player.querySelector('video');
    if (video) {
      video.muted = true;
      if (isFinite(video.duration) && video.duration > 0) video.currentTime = video.duration;
    }
    document.querySelectorAll(SKIP).forEach(b => b.click());
  }
  // Watches just the player's class (YouTube adds "ad-showing" while an ad plays), not the page.
  let watchedPlayer = null;
  const playerWatch = new MutationObserver(skip);
  function findPlayer() {
    const player = document.querySelector('#movie_player, .html5-video-player');
    if (!player || player === watchedPlayer) return !!player;
    watchedPlayer = player;
    playerWatch.disconnect();
    playerWatch.observe(player, { attributes: true, attributeFilter: ['class'] });
    skip();
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
