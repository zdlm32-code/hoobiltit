# Submitting hoobiltit 1.0

Everything the App Store Connect API can set is set. Version **1.0** is in
`PREPARE_FOR_SUBMISSION` with **build 16** attached.

Re-run the readiness audit any time with `python3 scripts/submission-status.py`.

## Done automatically

| Item | Value |
|---|---|
| Build | 16 (uploaded, VALID, attached to 1.0) |
| Name / subtitle | hoobiltit · "Who owns the road you're on" |
| Description, keywords, promo text | from `store/listing.md` |
| Support / marketing URL | https://hoobiltit.com/ |
| Privacy policy URL | https://hoobiltit.com/privacy.html |
| Categories | Reference (primary), Navigation (secondary) |
| Age rating | 4+ — every content question answered "none" |
| Copyright | 2026 hoobiltit |
| Review contact | Eli Trevino · zdlm32@gmail.com · 9568670098 |
| Review notes | no login needed, plus five test pins |
| Screenshots | 5 iPhone (1320×2868), 3 iPad (2064×2752) |
| Pricing | free |
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

The app displays factual public records fetched from government open-data services
(state DOTs, counties, cities, FHWA). Whether that counts as third-party content — and
what rights basis to assert — is a representation you make to Apple, so it is left for
you rather than guessed at.

## Then submit

App Store Connect → **1.0** → Add for Review → Submit.

Release is set to **manual after approval** (`AFTER_APPROVAL`), so nothing goes live
until you release it.
