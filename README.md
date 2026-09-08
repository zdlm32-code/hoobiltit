# roadapp

Answers "who built this road?" for a dropped pin: the owning jurisdiction, the project that
built or last improved the segment, and — eventually — the contractor who won the bid.

Coverage is **tiered, and the app says which tier answered**, because there is no national
road-ownership dataset and pretending otherwise would be a promise the data cannot keep.

| Tier | Where | What you get |
|---|---|---|
| County | Maricopa County, AZ | Everything: owner, project, plat, declaration, pavement, parcels |
| City | Dallas, San Antonio, and the Rio Grande Valley — Arlington, Brownsville, Edinburg, Irving, Laredo, McAllen, Pharr, Weslaco | The city's own street record: who maintains it, what was last done to it and when, pavement and condition. Edinburg names the contractor and what it spent |
| State | Arizona (statewide, every road named), Pennsylvania, Louisiana, Texas | Name, owner, construction and improvement year where the state publishes one. In Texas, the full construction register on the state system: every project back to 1970 with cost, and the contractor on live work |
| National | Everywhere in the US | Street name from Census TIGER/Line, ownership if the road is on the National Highway System, a build year if you are on a bridge |

Adding a state is an edit to `Sources/RoadCore/Resources/coverage.json`, not a code change — so
long as it fits an adapter that already exists. Texas needed one new mechanism (a second layer
joined on a key, because TxDOT publishes 133 fields and not one of them is a street name); the
next state shaped like it will not.

## Start here

**[`docs/ENDPOINTS.md`](docs/ENDPOINTS.md)** is the load-bearing document. It records every
public endpoint probed, which are genuinely queryable, the query form that actually works, and
where the data model has to bend. Read §4 and §5 before writing a source; they are the
difference between a working query and a silent empty result.

## Layout

```
docs/ENDPOINTS.md        endpoint findings — the reason the code is short
Sources/RoadCore/Coverage/  jurisdiction lookup, coverage catalog, code tables, field mapping
Sources/RoadCore/Resources/coverage.json  which jurisdictions this build can read, and how
scripts/probe.sh         re-runs the reconnaissance; named test pins; regression guard
Sources/RoadCore/        model, provenance, resolver, ArcGIS client, geometry
Sources/RoadSources/     one type per data provider
Sources/RoadStore/       SwiftData cache of per-source answers
Sources/RoadUI/          map screen and controls, location, lookup model, result screen
Sources/roadlookup/      CLI: resolve a pin against the live services
App/                     iOS app entry point
project.yml              xcodegen spec; RoadApp.xcodeproj is generated, not committed
Tests/                   fixtures captured from the live services, plus unit tests
```

## Try it

```sh
swift test                                                  # 96 tests, no network
swift build && .build/debug/roadlookup -112.5251 33.7686    # resolve a pin, live
.build/debug/roadlookup -112.5251 33.7686 --cache           # again, served from the store
.build/debug/roadlookup -112.5251 33.7686 --request         # the public-records draft
./scripts/probe.sh                                          # all pins, all layers
```

The iOS app:

```sh
xcodegen generate
xcodebuild -project RoadApp.xcodeproj -scheme RoadApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Pan the map so the crosshair is over the road, then press **Identify this road**. Or press the
location button to centre on yourself and identify in one go. The **Examples** menu jumps to the test pins
below and opens a source log showing what every source said, including the ones that found
nothing. `-pin williams` drops a pin at startup, `-report` opens the full report and `-rate` the rating
sheet — both are development
affordances and are safe to delete.

Test pins, each exercising a different path:

| Coordinate | Path |
|---|---|
| `-112.5251 33.7686` | unincorporated, county-maintained dirt road |
| `-112.4118 33.4386` | inside Goodyear — county returns nothing, which is the answer |
| `-112.3756 33.4602` | I-10 — ADOT owns it *inside* Goodyear's city limits |
| `-112.317668 33.689441` | Williams Dr — the full answer: owner, segment, project, plat |
| `-112.2749 33.5988` | Sun City — declared a public road in 1982; nearby bridges carry *other* roads |
| `-112.4448 33.3939` | MC 85 — a road whose name ends in digits; acquired by ADOT resolution |
| `-111.667181 33.466228` | McDowell Rd — a point-located project the corridor query cannot see |

## Sources

The pipeline is chosen by where the pin is. `JurisdictionLocator` turns a coordinate into a
state and county FIPS, `PipelineFactory` reads `coverage.json` and assembles the sources, and
`RoadResolver` runs them unchanged. Tiers run **state, then county, then national**, and the
order is load-bearing throughout.

### Generic adapters, driven by the catalog

| Source | Answers |
|---|---|
| `FlatInventorySource` | a state DOT publishing one denormalised inventory layer — PennDOT and TxDOT today, the latter joined to a second layer for its street names |
| `LRSEventSource` | a state DOT publishing linear-referenced event tables, joined on route id and measure — Louisiana today |

### National, running everywhere

| Source | Answers |
|---|---|
| `TIGERNameSource` | names the street anywhere in the US. No ownership, no dates — it is a gazetteer |
| `NHSOwnershipSource` | ownership, class and traffic on the 498,226 National Highway System segments |
| `NBIBridgeSource` | structures: build year and reconstruction year, back to 1927 |

### Hand-written, because configuration cannot express them

| Source | Answers |
|---|---|
| `ADOTStateRouteSource` | state routes: owner, route, construction date, TRACS project |
| `ADOTFundingSource` | what an ADOT project was programmed to cost, and when it opened |
| `MCDOTRoadInfoSource` | jurisdiction, county maintenance, classification, pavement, plat |
| `MaricopaStreetNameSource` | names the street from the countywide centreline — the only source covering city streets |
| `MaricopaRoadDeclarationSource` | **when a county road was declared public**, and how the right of way was acquired |
| `MaricopaCountyProjectSource` | county capital (TIP) and maintenance (MIP) projects, corridor and point |
| `MaricopaParcelSource` | the land beside the road: APN, owner, when the buildings alongside were built |

ADOT runs first because a pin on I-10 sits inside Goodyear's city limits: county-only
resolution would call an interstate a city road. ADOT stays silent unless the pin is genuinely
on one of its routes, so it costs nothing elsewhere.

These stay in Swift because each encodes judgement a config schema should not try to express:
concluding ownership from a layer's *silence*, telling two coincident route namespaces 2 m
apart from each other, recovering a project number from free text. `adapter: "bespoke"` in the
catalog is how a profile says "this one needs code".

Later sources use what earlier ones concluded, which is what makes the name gates possible:
the declaration source needs the segment name or the plat to tell one road file from its
neighbours', the bridge source needs the road name so a canal bridge four hundred metres away
cannot claim a residential pin, and the funding source needs the TRACS number.

**Contractor and cost: Texas only.** This was previously recorded here, and shown to users in
the app, as flatly impossible — of fourteen state DOTs probed, none published construction cost.
That was wrong. **TxDOT publishes both**: an estimated construction cost on 73,085 of 73,306
projects going back to 1970, and the construction company on work currently under way. The other
thirteen states and Maricopa County still publish neither, and even in Texas the figure is the
estimate rather than the awarded amount. See
[§6](docs/ENDPOINTS.md#6-contractor-and-award--one-state-has-it-the-rest-do-not) and §10.2c. That section
also explains why USAspending was dropped rather than deferred: it can only resolve to ZIP+4,
and its keyword search returns Lockheed Martin radar contracts for "Litchfield Road" because
the recipient's mailing address is on that street.

## Map

Aiming, not tapping. A fixed crosshair marks the map centre and nothing is looked up until you
press Identify — tap-to-drop meant every stray tap started six network requests. Controls:
map style (standard / hybrid / satellite), zoom, locate-and-identify, plus MapKit's compass,
scale bar and 3D pitch toggle.

Satellite earns its place here rather than being decoration: you can see the pavement, count
the lanes, and tell whether a street was cut as one piece of a subdivision — the same story the
plat and road-declaration records tell in text.

The crosshair and the map share one frame. The map ignores the bottom safe area, so a reticle
laid out in the safe area sits about 17pt above the camera centre and would mark a different
spot than the one identified.

Parcel boundaries draw live as you pan, above a zoom threshold, with the reported parcel
highlighted and labelled. Two brakes keep it from spending data continuously: the zoom gate,
and a containment cache that makes panning within an already-fetched block free.

## Drive mode

**Drive and stationary switch themselves.** Speed off the location fix decides, with
hysteresis — about 11 mph in, under 2 mph sustained for 45 s out — so a stop light does not
flip modes and a brisk walk does not start one. Core Motion would classify more accurately but
needs the Motion & Fitness permission and a second prompt; speed from a fix the app already
receives is enough to tell a car from a parked phone.

Following and identifying are separate concerns. The camera follows the device **whether or
not you are moving** — a parked phone should still be centred on itself — and motion only
decides whether the app keeps *re*-identifying. On opening it names the road once either way.

The location arrow is a **toggle**, not a one-shot recentre: on means the camera stays on the
device, off means it stays where you left it. It fills and tints when on. Starting to drive
turns it on, since that is plainly what you want when the car pulls away. Panning away also
turns it off, because the camera has already stopped following.

Zooming while following keeps following. `positionedByUser` cannot tell a pinch from a pan, so
the decision is made on where the camera ended up: still over the device is a zoom (and it
becomes the new follow distance), moved away is a pan and ends the follow.

Tapping a drawn parcel opens its Assessor record. The hit test runs against the polygons
already on screen rather than asking the server what is under the finger.

**This is what the app does on launch.** It finds the device, zooms to street level, follows it,
and names the road under it — no button press. Panning breaks the follow; the arrow button
restores it. Without location access it falls back to the county view and the aim-and-identify
flow, and says why.

The camera is driven explicitly rather than with `.userLocation(followsHeading:)`: that
position resolves to its fallback until MapKit has its own fix, which left the map at the
county overview on launch even though the app already had a location and had identified the
road.

Two things that made it hang on "Looking…" in real use, both fixed: the reverse geocode that
fills the address subtitle was awaited *alongside* the resolve, so a throttled `CLGeocoder` —
and Apple throttles hard when you call it repeatedly, which driving does — held the screen on
"Looking…" with a finished answer behind it. And the cheap probe could veto the lookup
entirely, so any road the county centreline does not know never got resolved at all. The probe
now only decides *when* to re-resolve, never *whether* to.

An indefinite "Looking…" is indistinguishable from a crash, so the summary now separates
"still working" from "finished, found nothing".

The car button toggles it off and on. It streams location and identifies each road
automatically, with a large glanceable card instead of the result screen: road name, the years,
who maintains it, which block you are on, and a line of detail. The type ramp descends
monotonically and the **year is second**, because that is the answer to the question the app
asks. It is the only coloured thing on the card.

**A missing year is explained, never left as a hole.** No agency publishes a construction date
for a Phoenix city street, and a blank row reads as a broken app — so the card says
*No construction date published*, or in Pennsylvania the state's own reason.

**Tapping the card opens everything.** At speed the card shows six lines; the detail behind it
shows every fact the app resolved — the structure you are crossing in full, the right-of-way
width, the project's own description of its extent, the paper trail, the records request — and,
for each source, when it was asked and a link to the exact query, so any claim on the screen can
be re-run. It is **frozen on the road it was opened for**: drive on and it stays put rather than
rewriting itself while you read, and the card behind it is current again when you close it.

Every road identified is kept in a drive log, reachable from the road counter on the card or
from the ⋯ menu. Consecutive lookups on one road collapse to a single entry, so the counter
reports roads rather than lookups — without that, a five-mile arterial reads as thirty-two.

It re-resolves when the road name changes, when the county changes, or after 250 m — and
**the refresh is invisible**. That was not always true: the lookup used to blank the card
first, so on one road the display spent most of its time reading "Looking…". A drive refresh
now updates in place and never clears what is on screen; "Looking…" is reachable only before
the first answer of a drive. A refresh that comes back thinner because one endpoint timed out
is discarded rather than adopted, so the card cannot lose information to a blip — but a
*different* road always wins, however little is known about it. A full lookup
asks six sources across fifteen-odd requests and takes ~20 s cold; at 45 mph that is 400 m of
road, and the 11 m cache key never hits while moving. So each fix runs a cheap probe against the
county centreline (three layers, concurrent, name only) and the full pipeline runs only when
that name actually changes.

Background location is requested so identification survives the screen locking, which needs
`UIBackgroundModes: location` in the plist — without it `allowsBackgroundLocationUpdates`
traps at runtime rather than failing gracefully.

**Night mode follows the sun, not the system appearance.** Most people leave iOS on Light
permanently, so keying off it leaves the map blinding at 9 pm — which is the thing a night mode
is for. `SolarPosition` computes the sun's altitude at the device's own coordinate, with
hysteresis so dusk cannot flap; Day and Night can also be forced from the map-style menu, and
the choice persists. At night the card goes to a dark, warm, low-glare palette with no pure
white, because white-on-black halates badly on OLED.

While driving, the map strips back: flat elevation, muted labels, no points of interest, no
parcel overlay. Aiming chrome goes too — the crosshair, the pin, the search field, the map
controls and the ⋯ menu — since none of it is for driving. **The screen is kept awake**, which
is what a dash-mounted phone actually needs.

**A Live Activity** puts the current road on the lock screen and in the Dynamic Island. Note
what it does and does not do: an iPhone 15 has no Always-On Display, so with the screen asleep
it is not visible — it is there when the screen wakes, and in the Dynamic Island whenever the
phone is unlocked and this app is not frontmost. Updates are skipped when the rendered text has
not changed, so the 250 m re-resolve cadence costs it nothing on a long road.

## What the app does not do

It records nothing about you. There is no account, no history, no profile, and no server of ours
for any of it to go to. It once let you rate roads, and briefly let you pool those ratings on a
shared map; both were removed, and the first launch after that change deletes anything a previous
version stored.

The CSV escaping from that feature survived it, in `CSVWriter`. Carrying its tests across turned
up a bug the original had shipped with: it tested for newlines over `Character`s, and Swift treats
CRLF as a **single** `Character` — so a value containing a Windows line ending matched neither
`"\n"` nor `"\r"` and went out unquoted, splitting the row and shifting every column after it.
The file still opens, which is why nobody noticed. It now tests unicode scalars.

## Sharing

Everything the app finds is shareable, and nothing about you is recorded to share.

| From | What you get |
|---|---|
| The full report's toolbar | A rendered card, or the whole report as a text file |
| The records request | The drafted letter, straight to Mail |
| The drive log | The roads you drove, as a CSV |

**A shared artefact carries no coordinate**, and that is enforced by tests rather than by care.
Every field on a `RoadRecord` carries a `Provenance` whose URL is the exact ArcGIS query —
geometry parameter included — so the pin is recoverable from it and `fetchedAt` says when
somebody was standing there. `RoadRecord` is therefore deliberately left non-`Codable`, and
`Coverage` carries a comment explaining why: adding the conformance is a one-word change that
looks like a tidy-up and would silently remove the guarantee.

The drive-log export is road names, not positions. It is an ordered trace of where somebody
drove, which is useful to look at yourself and is a movement record the moment it is one tap from
a group chat.

The one deliberate exception is the **public-records request**, which cites the coordinate to six
decimal places because the agency needs it to identify the segment — and unlike a card handed to
a group chat, that letter is addressed to a named public office. The share sheet says so.

## Design## Design

- **`RoadSource`** — one swappable provider. Each contributes only the fields it knows, and
  receives what earlier sources concluded, so a project source can tell "a project on this
  road" from "a project on the next street over".
- **`RoadResolver`** — runs sources in priority order, merges fragments, never throws. A
  partial answer is the normal outcome; a failing source costs only its own fields.
- **`Attributed<T>`** — every user-visible value carries its source, the exact query URL, a
  fetch date, and a `MatchConfidence`. Nothing reaches the UI without a receipt.
- **No API keys.** Every v1 source is anonymous, so there is nothing to keep out of the repo.
- **Caching is per source, not per record.** Keyed by the coordinate rounded to ~11 m, so two
  taps in the same spot are one question. A cached value keeps the `fetchedAt` it was
  originally fetched with, so provenance still reports when the agency was actually asked, and
  the source log says the network was skipped. Answers that found *nothing* are cached too —
  "MCDOT does not maintain this road" costs three requests to re-derive and is the outcome
  every city pin produces. Failures are never cached; the endpoint may just have been down.

Dates are never fused. A plat, a county road declaration, an ADOT construction record and a
bridge's build year are four different facts; the result screen shows whichever exist as
separate labelled rows rather than inventing one "built in YYYY".

Four rules the code enforces structurally, because each is a silent failure:

- `ArcGISClient` can only build **envelope** queries — point + `distance` returns zero
  features with no error on the county's server.
- `FromDate` is **never** read as a build date. It is temporal versioning, and its newest
  values are days old.
- Road-name suffix stripping lives in a **separate accessor** from the general one, because
  the maintained-roads layer carries genuine names ending in digits (`MC 85`, `Old US 80`).
- Dates from records are formatted as **calendar dates in UTC**. Agencies store them as UTC
  midnight, so local-time rendering reports a document recorded on the 24th as the 23rd.
- A source that cannot tie its find to the identified road **says nothing** rather than
  reporting the nearest thing. That rule is why the app does not repeat USAspending's mistake
  of answering "Litchfield Road" with a Lockheed Martin radar contract.
