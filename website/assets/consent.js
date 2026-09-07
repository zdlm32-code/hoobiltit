/* hoobiltit.com — Google Consent Mode v2.
 *
 * Loaded synchronously *before* gtag.js so the consent defaults are in the
 * dataLayer before the Google tag initialises. Lives in its own file rather
 * than inline so the page CSP can stay on 'self' with no script hashes.
 *
 * Behaviour:
 *   - Advertising signals are denied everywhere, always. This site runs no ads.
 *   - In the EEA, the UK and Switzerland, analytics storage is denied until the
 *     visitor agrees. Google enforces this by IP-derived region, independently
 *     of the banner below.
 *   - Everywhere else analytics storage defaults to granted, and the "Cookie
 *     settings" footer link lets anyone turn it off.
 */
(function () {
  'use strict';

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  window.gtag = gtag;

  var STORE_KEY = 'hoobiltit-consent';      // 'granted' | 'denied'
  var CONSENT_REGIONS = [
    'AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT',
    'LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE',   // EU
    'IS','LI','NO',                                                 // rest of EEA
    'GB','CH'                                                       // UK, Switzerland
  ];

  // Consent Mode stops Google *using* cookies, but any already set by an earlier
  // visit would linger. Declining should actually remove them.
  function clearGaCookies() {
    var host = location.hostname;
    var domains = ['', host, '.' + host];
    var parts = host.split('.');
    if (parts.length > 2) domains.push('.' + parts.slice(-2).join('.'));
    document.cookie.split('; ').forEach(function (c) {
      var name = c.split('=')[0];
      if (!/^_ga/.test(name)) return;
      domains.forEach(function (d) {
        document.cookie = name + '=; Max-Age=0; path=/' + (d ? '; domain=' + d : '');
      });
    });
  }

  function readChoice() {
    try { return localStorage.getItem(STORE_KEY); } catch (e) { return null; }
  }
  function writeChoice(v) {
    try { localStorage.setItem(STORE_KEY, v); } catch (e) { /* private mode */ }
  }

  /* --- defaults, before the tag loads ------------------------------------ */

  gtag('consent', 'default', {
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    analytics_storage: 'granted'
  });

  // Region-scoped defaults take precedence over the global one above.
  gtag('consent', 'default', {
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    analytics_storage: 'denied',
    region: CONSENT_REGIONS,
    wait_for_update: 500
  });

  var choice = readChoice();
  if (choice === 'granted' || choice === 'denied') {
    gtag('consent', 'update', { analytics_storage: choice });
    if (choice === 'denied') clearGaCookies();
  }

  gtag('js', new Date());
  gtag('config', 'G-L46G8VYPYH');

  /* --- the notice -------------------------------------------------------- */

  // Rough check for "probably somewhere that requires an opt-in". Google still
  // enforces the real region rule by IP, so a miss here means the visitor is
  // not tracked rather than tracked without asking.
  function likelyConsentRegion() {
    try {
      var tz = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
      return /^(Europe\/|Atlantic\/(Azores|Madeira|Canary|Faroe|Reykjavik)|Africa\/Ceuta|Asia\/(Nicosia|Famagusta))/.test(tz);
    } catch (e) {
      return false;
    }
  }

  function applyChoice(value) {
    writeChoice(value);
    gtag('consent', 'update', { analytics_storage: value });
    if (value === 'denied') clearGaCookies();
  }

  function buildBanner() {
    var wrap = document.createElement('div');
    wrap.className = 'consent';
    wrap.setAttribute('role', 'dialog');
    wrap.setAttribute('aria-label', 'Analytics cookies');

    var text = document.createElement('p');
    text.className = 'consent-text';
    text.innerHTML = 'This site counts page views with Google Analytics, which uses cookies. ' +
      'The app itself has no analytics. <a href="/privacy">Privacy policy</a>.';

    var actions = document.createElement('div');
    actions.className = 'consent-actions';

    var decline = document.createElement('button');
    decline.type = 'button';
    decline.className = 'consent-btn consent-btn-ghost';
    decline.textContent = 'Decline';

    var accept = document.createElement('button');
    accept.type = 'button';
    accept.className = 'consent-btn consent-btn-primary';
    accept.textContent = 'Accept';

    function close(value) {
      applyChoice(value);
      wrap.parentNode && wrap.parentNode.removeChild(wrap);
    }
    decline.addEventListener('click', function () { close('denied'); });
    accept.addEventListener('click', function () { close('granted'); });

    actions.appendChild(decline);
    actions.appendChild(accept);
    wrap.appendChild(text);
    wrap.appendChild(actions);
    return wrap;
  }

  function showBanner() {
    if (document.querySelector('.consent')) return;
    document.body.appendChild(buildBanner());
  }

  // A way for anyone, in any country, to change their mind. Needs the <nav> in
  // the footer to exist — without it this is a silent no-op and non-EEA visitors
  // get no opt-out at all.
  function addFooterLink() {
    var nav = document.querySelector('footer .foot nav');
    if (!nav) return;
    var a = document.createElement('a');
    a.href = '#';
    a.textContent = 'Cookie settings';
    a.addEventListener('click', function (e) {
      e.preventDefault();
      showBanner();
    });
    nav.appendChild(a);
  }

  function init() {
    addFooterLink();
    var forced = /[?&]consent=show(&|$)/.test(location.search);
    if (forced || (!readChoice() && likelyConsentRegion())) showBanner();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
