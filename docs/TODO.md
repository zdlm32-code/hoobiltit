# Website to-do

hoobiltit 1.0 is live on the App Store
(https://apps.apple.com/us/app/hoobiltit-us-road-information/id6809232030), and the site
links to it. The deploy that fixed the price, feature list and privacy policy is done, and
`/terms` and `/terms.html` both return 200.

## Bump the asset cache-busting token

`site.css` and `consent.js` are both linked as `?v=20260908a` from all three pages. Commit
`a2a43d1`: *"Cloudflare caches /assets/ for 7 days and has served a stale stylesheet as a HIT
before."*

Nothing in `assets/` changed this round, so this is only needed if you touch `site.css` or
`consent.js`. If you do, bump the token on **all three** pages together — `index.html`,
`privacy.html`, `terms.html`.

## What is already done, and must not be undone

- `terms.html` is new: matches `privacy.html`'s structure exactly and needs **no CSS changes**
  (`site.css` already has a `main.doc` block written for document pages).
- The footer's **empty `<nav></nav>`** on every page is load-bearing — `consent.js` injects the
  "Cookie settings" opt-out link into it, and without it that link silently disappears.
- `consent.js` must keep loading **synchronously before** the async `gtag.js`, so consent
  defaults reach the dataLayer before the Google tag initialises.
- Every `mailto:` is wrapped in `<!--email_off-->` markers (Cloudflare email obfuscation opt-out).
- No inline `<style>` or `<script>` on any page — a CSP is enforced at the edge, so inline blocks
  work locally and get blocked in production.
- `privacy.html`'s **"This website"** analytics section was restored. It had been deleted while
  `gtag.js` kept loading on every page, so the published policy described disclosure it no longer
  made. The page's own lede promises it, so it has to stay.
- Nav is `Coverage · Terms · Privacy` on all three pages, with `data-opt` marking the item that
  drops below 600px.

## Nice to have, not blocking

- The site has no `sitemap.xml`. `robots.txt` is `User-agent: * / Allow: /` with no sitemap
  directive. Three pages hardly need one.
