# Submitting hoobiltit 1.0

Everything the App Store Connect API can set is set. Version **1.0** is in
`PREPARE_FOR_SUBMISSION` with **build 16** attached.

Re-run the readiness audit any time with `python3 scripts/submission-status.py`.

## Done automatically

| Item | Value |
|---|---|
| Build | 16 (uploaded, VALID, attached to 1.0) |
| Name / subtitle | hoobiltit: US Road Information · "Who built this road?" |
| Description, keywords, promo text | from `store/listing.md` |
| Support / marketing URL | https://hoobiltit.com |
| Privacy policy URL | https://hoobiltit.com/privacy |
| Categories | Reference (primary), Navigation (secondary) |
| Age rating | 4+ — every content question answered "none" |
| Copyright | 2026 hoobiltit |
| Review contact | Eli Trevino · zdlm32@gmail.com · 9568670098 |
| Review notes | no login needed, plus five test pins |
| Screenshots | 4 iPhone, 3 iPad |
| Pricing | **$5.99** (base territory USA, proceeds $4.20) |
| Export compliance | `ITSAppUsesNonExemptEncryption: false` in Info.plist |

## Two things still needed, both web-UI only

The App Store Connect API exposes neither, so they cannot be scripted.

### 1. App Privacy — required

App Store Connect → hoobiltit → **App Privacy** → Get Started.

Answer **"No, we do not collect data from this app."** That is accurate and matches
`website/privacy.html`: no account, no analytics, no advertising identifier, no
third-party SDK, no crash reporter, and no server of ours at all. Road lookups go from
the device straight to public agency map services; the cache is local, expiring, and
holds public map data rather than anything about the user.

Then **Publish**.

### 2. Content Rights — required, one dropdown

App Store Connect → hoobiltit → **App Information** → Content Rights.

**Answer: uses third-party content.** Apple asks whether the app contains, shows or
*accesses* third-party content, and this one queries government map services and
displays what they return.

Checking the accompanying rights confirmation is well founded here: the app ships no
third-party assets at all (the asset catalog holds only the app icon), embeds no
documents — the recorded-plat row is a link out to the county recorder — carries no
agency logos, and uses MapKit for every map style, which is Apple's own. What it shows
is factual public records, attributed on the card to the agency they came from.

Settable over the API as `USES_THIRD_PARTY_CONTENT` if you would rather not click it.

## Then submit

App Store Connect → **1.0** → Add for Review → Submit.

Release is set to **manual after approval** (`AFTER_APPROVAL`), so nothing goes live
until you release it.
