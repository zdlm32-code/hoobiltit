# Website to-do

The repo is **ten commits ahead of what hoobiltit.com is serving**, and the live site has never
been redeployed since the shared map and road ratings were removed from the app in `0b0e18c`.
Everything in `website/` is already correct. The work is publishing it and checking two things
afterwards.

## 1. Deploy — this is the urgent one

The live site currently contradicts the App Store listing in three ways, and a reviewer opens the
privacy URL as a matter of course:

| | hoobiltit.com serves | The app actually is |
|---|---|---|
| Price | **"free"** | $5.99 |
| Features | advertises **"Shared map"** and **"Rate a road"** | both removed |
| Privacy policy | sections on stored reports, shared markers, *"Removing a shared report"*, *"Reporting a marker"* | collects nothing; App Privacy is declared **Data Not Collected** |

A privacy policy describing data collection, published next to an App Privacy declaration saying
there is none, is the kind of contradiction App Review notices. Deploying fixes all three at once
— the repo copy is already right.

Verify after deploying:

```
curl -s https://hoobiltit.com/ | grep -c "Shared map"        # want 0
curl -s https://hoobiltit.com/ | grep -o '\$5\.99'            # want $5.99
curl -s https://hoobiltit.com/privacy | grep -c "shared report"  # want 0
```

## 2. Check whether `/terms` resolves, and only then add a mapping

`website/terms.html` is new. Both `/terms` and `/terms.html` return 404 today, which proves
nothing except that the file has not been deployed.

**After deploying**, test both:

```
curl -o /dev/null -w "%{http_code}\n" https://hoobiltit.com/terms.html
curl -o /dev/null -w "%{http_code}\n" https://hoobiltit.com/terms
```

- Both 200 → nothing to do. Extensionless paths are handled automatically.
- `/terms.html` 200 but `/terms` 404 → the extensionless path needs the same per-path mapping
  `/privacy` has. Commit `a2a43d1` describes fixing exactly that for `/privacy`: *"The vhost
  mapped `/privacy` to `/privacy/index.html`, but the page is `privacy.html`. That is the URL App
  Store Connect gets and the one a reviewer opens, and it 404'd."* So this has bitten once before.

`/terms` must return 200 **before** the URL goes into App Store Connect as the licence agreement
link. `rel="canonical"` on the page already points at the extensionless form.

The hosting config is not in this repo — `server: cloudflare`, `cf-cache-status: DYNAMIC`, and no
`_redirects`, `_headers`, `wrangler.toml` or `.github/` anywhere. Whoever holds the dashboard or
origin config owns this step.

## 3. Bump the asset cache-busting token

`site.css` and `consent.js` are both linked as `?v=20260907c` from all three pages. Commit
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

- `index.html` still says **"Coming soon to the App Store"** in the badge, the meta description
  and the `og:description`. Accurate until 1.0 is approved; needs changing the day it ships.
- The site has no `sitemap.xml`. `robots.txt` is `User-agent: * / Allow: /` with no sitemap
  directive. Three pages hardly need one.
