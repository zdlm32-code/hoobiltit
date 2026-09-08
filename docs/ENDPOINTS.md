# Endpoint Findings — "Who built this road?"

Maricopa County, Arizona in §§1-6 and 8-9; the national and state tiers in §7 and §§10-12.

Probed live on 2026-09-06. Every URL here was actually called; sample payloads are real
responses, trimmed but not edited. Anything I did not personally hit is marked *unverified*.

**No API key exists for any v1 source.** Every endpoint below is anonymous. There is nothing
to keep out of the repo, which is a nice property but also means there is no rate-limit
allowance to lean on — be polite and cache.

---

## 0. The three-legged question, and which legs actually stand

| Leg | Status | Where it comes from |
|---|---|---|
| **Owning jurisdiction** | Solid | MCDOT Road Information Tool, point-in-polygon + maintained-set membership |
| **When** | Solid for county roads, partial elsewhere | County road declarations (§2.4); ADOT layers 2/3 for state routes; NBI for structures (§7.1) |
| **Project that funded/built it** | Partial | County TIP/MIP + ProjectStatus; ADOT ATIS for state routes |
| **What it cost** | Partial, state routes only | ADOT programmed funding (§3.2) |
| **Contractor + award** | **No API exists** | Deferred to v2 — see §6 |

Read §6 before planning any contractor work. The absence there is structural, not a gap in
the search.

---

## 1. Primary source — MCDOT Road Information Tool

```
https://gis.maricopa.gov/dot/rest/services/Maintenance/RoadInformationTool/MapServer
```

One on-prem ArcGIS Server (`currentVersion 11.5`) publishing the data behind the county's own
public Road Information Tool. It carries nearly everything v1 needs. `maxRecordCount: 2000`,
`Query` supported on all layers, `f=geojson` supported.

| Layer | Name | Why it matters |
|---|---|---|
| `7` | Municipalities | jurisdiction; also `Ordinance`, `OrdinanceWebLink`, `OrdinanceDate` |
| `2` | MCDOT Maintained Roads | the ownership discriminator — 10,954 segments |
| `10` | Current Road Classification | same schema as 2, used for classification/surface |
| `3` | Subdivision | `SubdivisionName`, `MCRNumber`, `MCRWebLink` (plat) — 31,811/31,860 have the link |
| `1` | Street Network | `RouteId`, `FullRouteName`, `RouteDirection` |
| `4`, `12`, `15`, `5`, `14` | Parcel, Public Land Ownership, ROW Permit, Supervisor Districts, Street Light Improvement District | supporting |

### 1.1 Jurisdiction — layer 7 (and the thing that will bite you)

**Layer 7 contains only *incorporated* municipalities. Absence of a feature means
unincorporated Maricopa County.** A query at Lone Mountain Rd (`-112.528617, 33.767648`) returns
`{"features": []}` — that empty response *is* the answer, not a failure.

At a Goodyear pin (`-112.4118, 33.4386`):

```json
{"CityName": "GOODYEAR", "FullCityName": "City of Goodyear",
 "Ordinance": "156", "OrdinanceDate": 442972800000,
 "OrdinanceWebLink": "https://mcrogisstorage.maricopa.gov/mcro-gis/AnnexationOrdinances/CitiesAndTowns/Goodyear/Goodyear_84-156.pdf"}
```

`OrdinanceWebLink` is a live PDF of the annexation ordinance — excellent provenance: you can
say *when and by which ordinance* this ground became city land.

If you want an explicitly-labelled unincorporated polygon instead of inferring from absence,
`IndividualService/City/MapServer/0` on the same host returns
`{"CityName": "UNINCORPORATED MARICOPA COUNTY"}` as a real feature. It lacks the ordinance
fields. Use layer 7 as primary; this is a useful cross-check.

### 1.2 Ownership — layer 2

Query layer 2 at the pin. **A non-empty result means the county maintains this road. An empty
result means it does not** — and combined with §1.1 that resolves to "City of X maintains
this" or "not a county-maintained road."

Real feature at Lone Mountain Rd:

```json
{"SegmentID": "1065", "OnRoad": "Lone Mountain Rd", "FromRoad": "Crozier Rd", "ToRoad": "215th Ave",
 "Classification": "01 - Local", "SurfaceType": "Dirt Native", "SurfaceDepth": 0.0,
 "RoadWidth": 30, "LaneCount": 2, "LengthInFeet": 2618.99,
 "MaintenanceDistrict": "Northwest", "BoardOfSupervisorDistrict": 4,
 "RouteID": "12173", "FromDate": 1537747200000}
```

Full field list: `OBJECTID, SegmentID, FromMeasure, ToMeasure, SubdivisionName, RouteID,
SurfaceType, SurfaceDepth, BaseType, BaseDepth, SubBaseType, SubBaseDepth, SubgradeType,
SubgradeDepth, TreatedSubgradeType, TreatedSubgradeDepth, RoadWidth, LaneCount, LengthInFeet,
OnRoad, FromRoad, ToRoad, FromOffset, ToOffset, Classification, FromDate, CreatedBy,
CreateDate, EditedBy, LastEditDate, Street, ToDate, InvertedCrown, EstimatedOci, EstimatedOcr,
CourtesyMaintained, CourtesyMaintainedNote, BoardOfSupervisorDistrict, MaintenanceSide,
MaintenanceDistrict, Primative`

`EstimatedOci` is a pavement condition index (0–100), e.g. `70.35` in Sun City, `19.74` on a
neighbouring industrial street. It is *condition*, not age — see §5.1. `EstimatedOcr` carries
the county's own plain-English rating for the same thing ("Very Poor" … "Very Good") on 10,001
of 10,954 rows, and is the better one to show a person.

**`CourtesyMaintained` changes the ownership answer for 616 segments.** Its domain is
`Yes` / `No` / null — *not* `Y`, so `WHERE CourtesyMaintained='Y'` returns zero and reads as
"this never happens". 616 of 10,954 rows are `Yes`: the county maintains the road but has not
accepted it into its system, which usually means a developer built it. Reporting those as
county-owned overstates what the county holds, and for them the recorded plat is the real
answer to who built the road. `Primative` (sic) flags 45 further segments.

### 1.3 Plat / developer-built streets — layer 3

This is the answer for most residential streets, and it is a **first-class queryable source,
not a manual fallback.**

```json
{"SubdivisionName": "SUN CITY UNIT 4C", "SubdivisionLevel": 1, "MCRNumber": "185-38",
 "MCRWebLink": "https://recorder.maricopa.gov/recording/document-search-results.html?mode=book&docketBook=185&pageMap=38"}
```

`MCRNumber` is a County Recorder book-page. `MCRWebLink` deep-links the recorded plat.
Populated on 31,811 of 31,860 rows (99.8%).

**The layer carries no recording date.** Its full field list is `OBJECTID, SHAPE,
SubdivisionName, SubdivisionLevel, MCRNumber, MCRWebLink, SHAPE_Length, SHAPE_Area` — so a
`plattedDate` is not derivable here, and the app must send the user to `MCRWebLink` for it
rather than implying a year. (Goodyear's ROW Dedication layer *does* carry `RECORD_DATE` /
`RECORD_YEAR`, which is one reason to want the city sources later.)

**Join spatially, never by name.** At the same point, layer 2 reports the subdivision as
`SUN CITY UNIT 4-C` while layer 3 reports `SUN CITY UNIT 4C`. The hyphen differs. Use the
polygon that contains the pin.

---

## 2. County projects

### 2.1 TIP / MIP — `BOS/Transportation/MapServer`

```
https://gis.maricopa.gov/arcgis/rest/services/BOS/Transportation/MapServer
```

| Layer | Name | Rows |
|---|---|---|
| `770` | Linear Improvement (TIP) | 1,054 |
| `790` | Linear Improvement (MIP) | 3,940 |
| `760` | Spot Improvement (TIP) | 87 |
| `780` | Spot Improvement (MIP) | 111 |
| `810` | MCDOT Maintained Roads | 10,954 |
| `800` | MCDOT Right-Of-Way | 13,193 |

Real TIP hit at Deer Valley Rd & 109th Ave (`-112.2905, 33.6836`):

```json
{"ProjNum": "TT0248", "Title": "Deer Valley Road: El Mirage Rd to 109th Ave",
 "Description": "Widen and extend Deer Valley Road and Wi...", "Phase": "Project Closeout",
 "ProjectType": "Construction", "OnRoadName": "Deer Valley Rd                          01",
 "FromRefName": "109th Ave                               01", "ToRefName": "107th Ave ...",
 "RouteID": "14993", "FromMeasure": 86264.3985, "ToMeasure": 87607.8528}
```

**Spot layers 760 (TIP) and 780 (MIP) are point geometry**, and they catch work a line query
structurally cannot see — bridges, signals, drainage, cattle guards. Layer 760's fields are a
superset of 770's, swapping the from/to linear-referencing pair for `RefLocation`, `RefOffset`,
`Measure` and `RefName`. Layer 780 is much thinner and, importantly, **carries no road name at
all**, so it can only ever be accepted when the pin is inside the tight radius.

They matter more than 198 rows suggests. On McDowell Rd at `-111.667181, 33.466228`, project
`TT0408` appears in *both* layers: the linear record is 401 m away and named
`"78th St                                 01 Mesa"`, while the spot record sits on the pin and
is named `McDowell Rd`. Querying only the linear layers finds a project on the wrong street.

MIP (layer 790) is maintenance work — `ProjNum`, `Title` ("Slurry Seal II"), `WorkOrder`,
`ProjectType` ("Pavement Preservation"), `MIPType`, `ProjectManager`, `Inspector`.

Layer `800` (ROW) is worth knowing: it carries `RecorderNumber`, `RecorderUrl`, and
`aquisition_type` (`Plat`, `Road Easement`) — a second, independent path to the recorded
document. Note the field is misspelled `aquisition_type` in the schema.

### 2.2 Project status — `Planning/ProjectStatus/MapServer`

```
https://gis.maricopa.gov/dot/rest/services/Planning/ProjectStatus/MapServer/1
```

`ProjectNumber, ProjectTitle, ProjectDescription, CurrentStatus, Phase, PhaseDesc, TimeLine,
District, ProjectType, Location, ProjectUpdates, route_cd, from_desc, to_desc, begin_measure,
end_measure`

```json
{"ProjectTitle": "Sun Lakes Pavement Rehabilitation Units 1-10 and 41",
 "ProjectDescription": "<p>The Maricopa County Department of Transportation (MCDOT) will be conducting a pavement rehabilitation project in Sun Lakes beginning early April and will run through July 2022.&nbsp;&nbsp;</p>\r\n<p>Pavement rehabilitation includes ..."}
```

`ProjectDescription` is raw HTML with `\r\n` and `&nbsp;`. Strip before display.

**`ProjectNumber` shares TIP's `TTxxxx` numbering** — 342 rows match `ProjectNumber LIKE 'TT%'`,
and `TT0248` resolves in both. So once a spatial query on layer 770 has established the
project number, the status record is a **typed join**, not another guess at geometry. Its
write-up is public-facing prose and is the better one to show; its `CurrentStatus`
("Completed", "Design") is more current than the programme layer's `Phase`.

### 2.3 Project geometry does not sit on the centerline

Projects are stored against a linear referencing system, so a project line can be a couple of
hundred metres from the road it describes. The Deer Valley Road TIP line measures **206 m**
from a pin on that road — outside a 150 m envelope. A radius tight enough to identify *which
street you are on* will therefore miss the project that built it, and one wide enough to catch
it will also catch the next street over.

What works: search a wider corridor (~400 m), accept the nearest match inside the tight
radius outright, and beyond that accept a project **only when its `OnRoadName` matches the
segment already identified**. That requires the resolver to hand each source what earlier
sources concluded.

Sibling service `Planning/TransportationProject/MapServer` (layers 0 Spot / 1 Linear) also
exists. Other MCDOT folders on `gis.maricopa.gov/dot/rest/services`: `AssetIntegration`,
`Basemap`, `Maintenance`, `Planning`, `Property`, `RED`, `RoadLocationTool`, `Survey`,
`Traffic`, `Utilities`.

### 2.3b Countywide street centreline — the only source that names a city street

```
https://gis.maricopa.gov/arcgis/rest/services/IndividualService/Street/MapServer
  layer 1 Highway · layer 2 Arterial · layer 3 Local
```

`FullStreetName` plus `Classification` ("Arterial", "Residential", "Collector-Like"). There is
no combined layer and a group layer cannot be queried, so all three are queried concurrently
and the nearest wins.

**This is the only source that covers streets inside incorporated cities.** MCDOT's
maintained-roads layer stops at the city line and ADOT's covers state routes, so without this
the app resolved *City of Goodyear maintains this* while being unable to name the street — the
literal on-screen result was "No road identified here" on an ordinary named road. Verified
naming streets in Goodyear (`S 159th Dr`), Phoenix (`W Washington St`) and Tempe (`S Rural Rd`).

Coverage is not uniformly tight: at 60 m it misses points that resolve fine at 150 m, so query
it at the same radius the rest of the pipeline uses.

### 2.4 County road declarations — the date county roads actually have

```
https://gis.maricopa.gov/dot/rest/services/Property/RightOfWay/MapServer/1
```

"Open And Declared (Verified)", 3,283 polygons, **`EffectiveDate` populated on 3,222 (98%)**,
spanning 1900–2026. This is the legal moment a road became a public county road, and it is the
single most valuable field found in the county stack. Fields: `RoadName, RoadFileNumber,
RoadFileRecordingNumber, RoadFileRecordingNumberURL, RoadFileMapNumber, RoadFileMapNumberURL,
EffectiveDate, Township, Range, Section`.

At the app's own 150 m envelope, each test pin returns a handful and the right one is
identifiable:

| Pin | Features | The match |
|---|---|---|
| Lone Mountain Rd | 1 | `LONE MOUNTAIN RD`, RF A518, **2014-09-24** — matches the segment name |
| Sun City (Santa Fe Dr) | 2 | `SANTA FE DR`, RF 2941, **1982-12-10** — matches the segment name |
| Williams Dr | 3 | `CROSSRIVER UNIT 8`, RF 5819, **2009-05-20** — matches the *plat*, not the street |

**`RoadName` holds either a street name or a subdivision name**, depending on how the road came
to exist — which is exactly the two things earlier sources have already resolved. Match against
the segment name first, then the subdivision; matching neither means saying nothing. A tight
point-in-polygon envelope is *not* enough: at 1 m and 30 m Lone Mountain returns 0, because the
declaration polygon does not cover the pin.

### 2.5 How the county acquired the road

`Property/RightOfWay/MapServer/0` (also served as `BOS/Transportation/MapServer/800`) —
13,193 polygons, **no date field**, but a clean `aquisition_type` domain (note the misspelling
in the schema):

| value | rows | | value | rows |
|---|---|---|---|---|
| Road Easement | 5,617 | | Quit-Claim Deed | 439 |
| Subdivision | 3,012 | | Final Order of Condemnation | 381 |
| Warranty Deed | 1,467 | | Federal Patent Easement not recorded | 222 |
| Other | 724 | | ADOT Resolution | 96 |
| Plat | 547 | | Drainage Easement | 33 |
| State Lease | 465 | | Slope Easement | 21 |

`RecorderUrl` is populated on 98.8% of rows, alongside `RightOfWayWidth` and `RecorderNumber`.
Live results: Lone Mountain Rd → *Road Easement*, recorded 1977; Sun City → *Subdivision*;
MC 85 → *ADOT Resolution*. The acquisition document and the declaration are different records
with different dates and must not be conflated.

---

### 2.6 County Assessor parcels — who owns the land the road runs through

```
https://gis.mcassessor.maricopa.gov/arcgis/rest/services/MaricopaDynamicQueryService/MapServer/3
```

Polygon layer, `maxRecordCount: 1000`, anonymous. Ported from the cellsurveys operator
dashboard, which queries the same service for GPS points. Note the host: `mcassessor.maricopa.gov`
(the public site) is Cloudflare-fronted and serves HTML, but **`gis.mcassessor.maricopa.gov` is a
plain ArcGIS server and answers fine**.

Fields worth having: `APN`, `APN_DASH` (punctuated), `OWNER_NAME`, `PHYSICAL_ADDRESS`,
`LAND_SIZE` (square feet), `CONST_YEAR`, `SUBNAME`, **`MCRNUM`**, `LOT_NUM`, `DEED_DATE`,
`SALE_DATE`, `SALE_PRICE`, `STR`. There is **no `SUBDIVISION` field** — it is `SUBNAME`, and
asking for the wrong name fails the whole query with a bare `Failed to execute query`.

**A road pin is normally in the right-of-way, between parcels, so point-in-polygon returns
nothing.** At Williams Dr a pin-sized box finds zero parcels; an 80 m box finds ten. So:
containment first (`.direct`), frontage second (`.spatial`), and the two must be labelled
differently — the owner of a parcel beside a road is not the owner of the road.

What this adds that nothing else has:

| | |
|---|---|
| `OWNER_NAME` | for a street the county has not accepted, often who is actually responsible |
| `CONST_YEAR` | when the buildings went up, which brackets when a developer street was laid out |
| `SUBNAME` + `MCRNUM` | the same plat identifiers MCDOT returns, from an unrelated agency |

The corroboration is real. At Williams Dr the frontage reads `CROSSRIVER UNIT 8 / 706-34`,
built **2008–2009** — and the county declared that road public on **2009-05-20**. At Sun City
and Goodyear the Assessor's `SUBNAME`/`MCRNUM` match MCDOT's plat exactly. Two agencies
agreeing is worth surfacing, because most answers in this app rest on one source.

`CONST_YEAR` is a *string* and vacant land carries `"0"`, not null.

**Drawing boundaries from this layer** needs two things. `maxAllowableOffset` roughly halves the
payload for lines that are pixel-identical at phone zoom (200 m radius: 44 KB → 19 KB; 500 m:
318 KB → 151 KB). And the layer caps a response at **1,000 features without saying so** — a
1 km radius already hits it, returning a partial cadastre indistinguishable from a complete
one. A 500 m radius returns 678, so the overlay refuses to draw above ~0.009° of span.

Note also that MapKit inflates a requested span to the view's aspect ratio: asking for 0.004°
yields 0.0058–0.0063° in practice, so a threshold has to clear the app's own default zoom or
the overlay flickers on and off.

---

## 3. State routes — ADOT

**Corrections to assumptions worth recording:** `gis.azdot.gov/arcgis/rest/services` does not
exist (404, IIS — ADOT has no public on-prem ArcGIS Server; everything is ArcGIS Online). And
`services.arcgis.com/ZzrwjTRez6FJiOq4` is **Utah DNR**, not ADOT — it is a plausible-looking
decoy with 2,146 services and zero Arizona content.

The real org:

```
https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/ATIS_prod_gdb/FeatureServer
```

52 layers — ADOT's ATIS linear referencing system published whole. Four matter:

| Layer | Name | Fields of interest |
|---|---|---|
| `29` | LRSE_OwnerMaint | `County`, `Ownership`, `Maintenance`, `Owner` |
| `1` | LRSN_ATIS_Routes | `RouteNameShort`, `RouteType`, `RouteSubtype`, `NCCountyCode` |
| `3` | **LRSE_YearLastConstruction** | `YearLastConstruction`, `YearBuiltComment`, `SourceYear` |
| `24` | LRSE_ProjectSegment | `TracsNumber`, `InServiceYear`, `InServiceDate` |
| `2` | LRSE_YearLastImprovement | `YearLastImprovement`, `YearBuiltComment` |

**Layer 3 is the only genuine construction-date field found in any source, anywhere.** On I-10
at `-112.3756, 33.4602`:

```json
{"RouteId": "  I 010                         ",
 "YearLastConstruction": "20110130", "YearBuiltComment": "Per H729601C"}
```

`YearBuiltComment` embeds a TRACS number in free text; `[A-Z]{1,2}[0-9]{5,6}[A-Z]` extracts it.

### 3.1 ATIS stores every road twice, and it changes how you select a route

`RouteId` is a fixed-width composite, and its leading characters are a namespace:

| `RouteId` | `RouteNameShort` | `RouteType` |
|---|---|---|
| `"  I 010                         "` | I-10 | I - Interstate |
| `"07  I 10                        "` | *null* | L - Local (Non-ADOT) |
| `"  I 010                       0 "` | I-10 nonCard | I - Interstate |
| `"  I 010127G                     "` | I-10 Exit 127 G-Ramp | I - Interstate |
| `"07  BULLARD             AVE     "` | *null* | L - Local (Non-ADOT) |

Every ADOT route has a **local mirror with identical geometry**. Measured from a pin on I-10
at Exit 127, the pairs are exactly coincident and the next distinct road is 22 m further out:

```
   1.7 m  [ADOT ]  '  I 010                         '  I-10                   70-Interstate
   1.7 m  [local]  '07  I 10                        '  —                      98-Non-ADOT Rte
  24.1 m  [ADOT ]  '  I 010127E                     '  I-10 Exit 127 Crossing 75-Minor Ramps
  24.1 m  [local]  '07  BULLARD             AVE     '  —                      98-Non-ADOT Rte
  31.3 m  [ADOT ]  '  I 010                       0 '  I-10 nonCard           70-Interstate
```

Two naive rules both fail. Taking the **nearest feature** is a coin flip between a route and
its own mirror, and silences ADOT on the interstate itself. Taking the **nearest ADOT
feature** lets a freeway 100 m away claim a residential pin. What works: find what is
nearest, then prefer the ADOT record among the features sitting at that same spot — a
tolerance of a couple of metres separates "same road, other namespace" from "different road".

The `"...0 "` suffix is the non-cardinal carriageway (`RouteNameShort: "I-10 nonCard"`), a
second record for the same highway. Both carry the same construction date, so matching one
exactly is sufficient.

Layer 29 at the same point returns `"Ownership": "DOT-Arizona Department of Transportation"`.
**Caveat, tested:** layer 29 returned **zero features** at my unincorporated county point
(`-112.528617, 33.767648`), so despite carrying some non-state values it is *not* a general
jurisdiction resolver. MCDOT layer 7 stays primary for that.

**And do not trust layer 29's fields on roads ADOT does not own.** Its row for MC 85 — a
Maricopa County road — reads:

```json
{"RouteId": "00  MC 85                     0 ", "County": "001-Apache",
 "Ownership": "MMA-Maricopa County DOT (2)", "Owner": "MMA"}
```

`001-Apache` is a county four hundred kilometres away. The `Owner` code is the gate: read
ownership and county from this layer **only** when `Owner == "DOT"`, and leave everything else
to the agency that actually maintains the road. Owner codes seen in Maricopa: `DOT` (ADOT),
`MMA` (Maricopa County DOT), `GDY` (Goodyear).

### 3.2 Programmed cost — the money leg

Two services on the same ADOT org, both keyless, both spatially queryable, joined on TRACS:

```
.../mapped_route_export_July7/FeatureServer/0     3,294 rows — dollars, lead agency, fiscal year
.../RCI_Tracker/FeatureServer/0                   TRACS + exact in-service date (epoch ms)
```

At the I-10 pin, `mapped_route_export_July7` returns 4 features; TRACS `H881901C` resolves to
**$4,160,000, FFY2018, lead agency ADOT, MPO/COG MAG**, project title "PERRYVILLE ROAD -
BULLARD AVENUE". `RCI_Tracker` gives that project's exact opening: **2019-03-26**, where ATIS
layer 24 has only the year.

Three things to get right:
- **Dollars sit on whichever project is currently in the STIP**, which is usually *not* the one
  credited with construction. `H729601C` (construction) has no funding row; `H881901C` (most
  recent work) has the money. Try both project numbers.
- `TRACS_NUM` is sometimes a comma-separated list (`"T037001D, T037001X"`), so match by
  containment, not equality.
- `ROUTE_ID` here is trimmed (`"I 010"`) unlike ATIS's fixed-width padded form. Normalize
  before joining.
- Amounts are spread across `PRG_PRIOR` and `PRG_2023`…`PRG_2027`/`PRG_FUTURE`; the programmed
  total is their sum.

Superseded: `ADOT_eSTIP_ShapefileExport_3142023` is the same schema with 590 rows and returns
nothing at Goodyear. `5YRPlan2023_2024_gdb` is 14 statewide HSIP rows with no Maricopa
geometry. Neither is worth wiring.

Curated AZGeo mirrors (org `services6.arcgis.com/clPWQMwZfdWn4MQZ`) are cleaner and properly
typed but carry less detail: `ADOT_OwnershipAndMaintenance_2024`,
`ADOT_StateHighwaySystem_SHS_view`, `ADOT_AllRoadsNetwork_2024`, `SHS_Route_Network_View`
(filter `ReportYear` or you get 2021/2022/2024 duplicates), `HPMS_*_Data`.

ADOT program data is weak: `ADOTProjects_AZGEO` is a 26-feature draft with no TRACS or cost;
`ADOT_eSTIP_ShapefileExport_3142023` has `TRACS_NUM` + programmed dollars by FY but is frozen
at 2023-03-14; `5YRPlan2023_2024_gdb` has route + mileposts + FY but no TRACS, also frozen.
`azdot.gov/jsonapi` (Drupal JSON:API) serves `node--project` but the payload is narrative
prose only — no TRACS, route, milepost, cost, or contractor. Pass `filter[status]=1` or you
get an empty `data` array with a `meta.omitted` block.

---

## 4. The query form that actually works

**`distance` + `units` silently returns zero features on on-prem ArcGIS Server.** No error, no
warning — just `{"features": []}`. Verified on `gis.maricopa.gov` at a point where an envelope
returns a feature, in both `inSR=4326` and `inSR=102100`:

```
point + distance=100 units=esriSRUnit_Meter   -> 0 features
envelope ±0.0015°, inSR=4326                  -> 1 feature (Lone Mountain Rd)
```

Independently reproduced on `maps.goodyearaz.gov`. It *does* work on ArcGIS **Online**
(`services*.arcgis.com`) — verified on ADOT ATIS, where point+distance and envelope return
byte-identical 7-feature results.

**Rule: always build an `esriGeometryEnvelope` in `inSR=4326`.** It works on every host and
eliminates a whole class of silent-empty bug. Canonical query:

```
{layer}/query
  ?geometry={xmin},{ymin},{xmax},{ymax}
  &geometryType=esriGeometryEnvelope
  &inSR=4326
  &spatialRel=esriSpatialRelIntersects
  &outFields=*
  &returnGeometry=true
  &outSR=4326
  &f=json
```

An envelope returns every feature crossing the box, so **nearest-segment selection is
client-side**: request geometry and pick the true nearest by point-to-polyline distance.

Other server quirks confirmed:
- `LIKE` is case-sensitive (SQL Server). `FullStreetName LIKE '%ESTRELLA%'` matched nothing
  against stored `"W Yuma Rd"`-style mixed case. Use `UPPER()`.
- `f=geojson` is supported and decodes without an Esri SDK.
- TLS is clean, HTTP/1.1, no ATS exemption needed.

---

## 5. Where the data model has to bend

### 5.1 There is no construction year, and the obvious field is a trap

`FromDate` on the maintained-roads layer looks like a build date. It is **ArcGIS temporal
versioning** — the "record valid from" half of a `FromDate`/`ToDate` pair. Sorted descending,
its top values are dated within the last few days:

```
{"OnRoad": "Lower Buckeye Rd", "FromDate": 1788307200000}   -> 2026-09-02
{"OnRoad": "Granada Dr",       "FromDate": 1787011200000}   -> 2026-08-18
```

`-2208988800000` (1900-01-01) is the null sentinel; 10,689 of 10,954 rows carry a non-sentinel
value, all of them edit dates.

**Do not model a `constructionYear`.** Model independent, separately-sourced, nullable
fields, each with its own provenance:
- `declaration` — the county road-file declaration date (§2.4). **This is the closest thing to
  a build date a county road has, and it reaches back past 1970.**
- `plattedDate` — from the subdivision plat (§1.3). *Not fillable* — see the closed note below.
- `lastKnownImprovement` — from an overlapping project record (§2)
- `yearLastConstruction` / `yearLastImprovement` — state routes only, ADOT layers 3 and 2 (§3)
- `bridge.yearBuilt` / `yearReconstructed` — structures only (§7.1), and the only years that
  survive from before the 1960s.

A road can be declared, constructed, resurfaced and rebuilt in four different years. The UI
shows whichever exist as separate labelled rows and never fuses them.

**`plattedDate` is closed, not pending.** The plat layer carries no date; the Recorder is
behind Cloudflare `cf-mitigated: challenge`, so `URLSession` will never fetch it (the same
block that makes all of `*.azmag.gov` unusable); and the Assessor's `/api/` path returns HTML
and is token-gated. The plat and declaration links work in a browser and stay links.

### 5.2 Jurisdiction is not an attribute of a centerline

No county centerline layer has an owner column —
`IndividualService/Street/MapServer/2` has exactly `FullStreetName, PrefixDirection,
StreetName, StreetType, PostDirection, Classification` and nothing else. Ownership is
*derived*: municipality polygon → maintained-set membership → ADOT route. `RoadRecord.owner`
is a computed conclusion and its provenance must cite the polygon layer, not the centerline.

**Source order is part of the correctness of that conclusion.** A pin on I-10 at
`-112.3756, 33.4602` sits inside Goodyear's municipal boundary, so county-only resolution
reports "City of Goodyear" — the interstate is ADOT's. Municipality containment is a valid
*jurisdiction* answer and a wrong *ownership* answer for state routes. When the ADOT source
lands it must run **before** the county source in the resolver, so its unambiguous
`LRSE_OwnerMaint` verdict claims `owner` first.

### 5.3 String padding and type abuse

- MCDOT **project** layers (`BOS/Transportation` 760/770/780/790) pad `OnRoadName`,
  `FromRefName` and `ToRefName` with a trailing route-segment ordinal:
  `"Williams Dr                             01"`. **The ordinal is not always `01`** — 02, 03,
  04, 10, 14, 15, 19, 22, 31 and 1001–1004 all occur — and the padding is not fixed width
  (observed raw lengths 15, 16, 42, 44, 47, 52). Identify it by the padding, not by value.
- **The ordinal is often followed by a jurisdiction**: `"52nd Pl        01 Mesa"`,
  `"Buttonwood Dr        01 Maricopa County"`, also `Sun Lakes`, `Chandler`, `Scottsdale`,
  `Peoria`, `Phoenix`, `Buckeye` — 68 of 438 distinct values in layer 770. A rule anchored to
  end-of-string (`\s{2,}\d{1,4}$`) leaves these untouched and the name gate then fails to
  match a segment plainly called "52nd Pl". Strip from the padded ordinal onward
  (`\s{2,}\d{1,4}\b.*$`); nothing but a jurisdiction or a repeated ordinal was ever observed
  after it, and jurisdiction is resolved authoritatively from the municipality polygon anyway.
- **Do not apply that stripping globally.** The maintained-roads layer (RIT layer 2) has *no*
  padded suffixes and *does* carry genuine road names ending in numbers: **`MC 85`,
  `Old US 80`, `Old SR 87`, `FR 206`**. A naive "strip trailing two digits" rule renders the
  county's own highway as `MC`. Requiring two or more spaces is what keeps them intact.
  One row in layer 770 is stored as `"Lower Buckeye Rd 01"` with a single space — a duplicate
  of the correctly-padded value — and is the one case this rule deliberately misses.
- ADOT: `"  I 010                        "`, and **every measure and date is
  `esriFieldTypeString`** (`"20110130"`, `"-4e-7"`). Numeric SQL `where` clauses on these are
  unreliable; parse in the client.
- Avondale's `PavementMain` domain contains both `YES` and `Yes`. Normalize on decode.

### 5.3b A source must not name a road it is merely near

Every naming source finds the *nearest* road it holds, and none of them originally asked whether
that road was plausibly the one under the pin. With partial coverage the two are different
questions, and the failure is silent.

Verified at `-111.726021, 33.276976` — 2950 E Athena Ave, Gilbert:

| Source | Nearest road it can see |
|---|---|
| `IndividualService/Street` (countywide centreline) | **E Germann Rd, 76 m** |
| Census TIGER/Line | **E Athena Ave, 5.9 m** |

The county centreline **does not contain E Athena Ave at all** — the subdivision is newer than
the layer — so it answered with the arterial a block away, and being earlier in the pipeline it
won. TIGER, which has the street, was then skipped because the road had "already been named".
The symptom reads as a calibration fault: the crosshair is on one street and the card names
another.

`RoadProximity.onRoadMeters` (60 m) now gates every namer. A source beyond it contributes
nothing and says so in its note, and the next source gets its turn.

**This also means test pins must sit on their road.** The original Lone Mountain pin
(`-112.5251, 33.7686`) was eyeballed and sat **104 m** from Lone Mountain Rd's centreline — far
enough that the gate correctly refuses it. It has been moved onto the centreline, derived from
the layer's own geometry, as §9 says the later pins were.

### 5.3c `outSR` is not optional when you measure anything

`maxAllowableOffset` is interpreted in the units of the *output* spatial reference (§10.4), and
so is every coordinate you get back. Omit `outSR` and geometry arrives in **Web Mercator** while
looking perfectly well-formed. A distance computed against it as if it were degrees comes out
around 1.09 × 10¹² metres — large enough to be obviously wrong if you print it, and completely
invisible if you only ever take a minimum, because every candidate is wrong by the same factor.

`ArcGISClient` always sends `outSR=4326`, so the app is safe. Captured fixtures are not: two of
them were recorded without it and silently made a nearest-feature test meaningless.

### 5.4 No shared segment ID across sources

MCDOT `SegmentID`, ADOT `RouteId`+measures, and MAG `dbo_vwTIPMapData_SegmentID` are disjoint
namespaces. Cross-source joins are fuzzy name + geometry proximity only. `RoadRecord`
therefore keys on **the pin**, not on a road ID, and every non-primary field carries a
match confidence.

### 5.5 Project geometry is linear-referenced

TIP/MIP records are `RouteID` + `FromMeasure`/`ToMeasure` + offsets, not centerline shapes.
Project → segment is proximity-and-name matching. Label it that way in the UI.

### 5.6 Subdivision names differ between layers

`SUN CITY UNIT 4-C` (layer 2) vs `SUN CITY UNIT 4C` (layer 3), same location. Join spatially.

---

## 6. Contractor and award — one state has it, the rest do not

**Corrected 2026-09-07.** This section previously read "no API exists" and concluded that leg 3
was unobtainable anywhere. That was wrong, and the app repeated it to users in print. **TxDOT
publishes both**: `ProjectTracker_AGO` names the construction company on 7,542 projects under
way, and the DCIS register carries an estimated construction cost on 73,085 of 73,306 projects
(§10.2c). What follows remains true of the other thirteen states probed, and of Maricopa County.

TxDOT also publishes a **spending ledger** — `ProjectTracker_AGO` layer 2, 76,617 rows keyed on
the CSJ and split by category. Filtering to `SPENDING_CAT = 'CNST'` gives what has actually been
paid out on construction as opposed to estimated: $9,839,558 spent against a $36,728,295 estimate
on CSJ 025809147, with `ORION CONSTRUCTION, LLC` named as the builder. `PE` and `ROW` rows are
design and land and are deliberately not summed into it.

Note the limits even where it works. The Texas figure is the *estimate*, not the awarded amount,
and the contractor is published only while a job is live — a road built in 1988 still has no
company against it. So the records request below is still the route to an awarded figure, and
the app says so wherever it shows a cost.

This is the honest state of leg 3 elsewhere, and why it is deferred.

**ADOT** publishes bid results as server-rendered HTML with no JSON/CSV API:
- As-read: `https://cnsads.azdot.gov/as-read` → 13 rows, columns
  `Route County Milepost | TRACS # | Project # | Bid Opening`. Detail pages
  `/as-read/details/{id}` carry the actual bid table. The `DEPARTMENT` row is ADOT's own
  engineer's estimate, not a bidder — filter it out; low bidder is the min of the rest.
- Tabulations: `https://apps.azdot.gov/cnsaws/tabulations` → 29 rows with `Board Award Date`,
  linking to per-letting PDFs on S3.

**The killer is retention: ADOT keeps bid tabulations only four months past the award date.**
You cannot look up who paved a road in 2011. Older records need a formal public-records
request. TRACS format is `[A-Z]{1,2}[0-9]{5,6}[A-Z]` and *does* join cleanly to
`LRSE_ProjectSegment.TracsNumber`, so a slowly-accumulated TRACS→contractor table is viable
over time — but it cannot be backfilled.

**Maricopa County** Board of Supervisors uses CivicPlus AgendaCenter
(`https://www.maricopa.gov/AgendaCenter`). Search returns 186 KB of HTML wrapping PDF agendas.
No API.

**Legistar**, for the west valley, is mostly a dead end:
- `webapi.legistar.com/v1/goodyear` responds, but coverage is **2013-01-28 → 2021-02-02 and
  stops dead**. Goodyear migrated off Legistar in early 2021. Useful as a historical archive
  only.
- Goodyear now uses `goodyearaz.open.media` — Drupal 7 + React, WAF-blocks plain `curl`,
  session lists rendered client-side, and `/api/*`, `/graphql`, `/sitemap.xml` all 404.
  Headless scraping + PDF extraction only.
- Avondale, Buckeye, Surprise, Peoria, Glendale are **not** Legistar cities.
- Phoenix and Mesa *are*, fully current, with working OData (`$filter`, `$top`, `$orderby`,
  `$select`, and `substringof('x',Field) eq true` — the older OData dialect, not `contains()`).

**Two traps worth writing down:**
1. Legistar client code `maricopa` is the **City of Maricopa in Pinal County**, not Maricopa
   County. Its `/bodies` returns a 7-member City Council. Easy to mistake for the county.
2. `https://{anything}.legistar.com/Calendar.aspx` returns **HTTP 200 for every subdomain**,
   including nonsense ones. It is a wildcard — testing the InSite subdomain proves nothing.
   Only `webapi.legistar.com/v1/{client}/bodies` is a real existence test.

### USAspending: drop it, do not defer it

`https://api.usaspending.gov/api/v2/search/spending_by_award/` is live, keyless, and pleasant
(`limit` max 100; data floor 2007-10-01). It is also the wrong tool, in a way that is actively
dangerous for this app:

- **Geography bottoms out at ZIP+4.** `place_of_performance` returns county, city,
  congressional district, zip5/zip4 — `address_line1` is null. No lat/long, no route, no
  milepost. You cannot tie an award to a segment geometrically.
- **81% of Maricopa NAICS 237310 dollars are DoD** — Luke AFB taxiways behind a fence. FHWA
  appears as $8.6M of $195M.
- **The keyword filter produces confident false positives.** Searching `"Litchfield Road"`
  returns four Lockheed Martin airborne-radar contracts totalling $58.9M — because the keyword
  index searches a legacy FPDS blob that embeds the *recipient's mailing address*, and
  Lockheed's office is at 1300 S Litchfield Rd. Searching `"Yuma Road"` returns Yuma, Arizona.
  `"Estrella Parkway"` returns nothing.
- **Sub-award coverage is negligible**: one sub-award against 436 primes.

The structural reason: FHWA money moves as **formula grants** to ADOT, which sub-allocates to
MAG and to cities, which procure their own paving contractors. That contract never enters
FPDS. For a normal public street in Maricopa County, USAspending will not tell you who built
it. At most it is an optional "federal contracts nearby" panel with an explicit disclaimer.

---

## 7. National sources

### 7.1 National Bridge Inventory — the oldest build years anywhere

```
https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/NTAD_National_Bridge_Inventory/FeatureServer/0
```

USDOT/BTS, keyless, 128 fields, point geometry. **2,854 structures in Maricopa County**
(`STATE_CODE_001 = '04' AND COUNTY_CODE_003 = '013'` — the code columns are zero-padded
*strings*, so `= 4` and `= 13` silently match nothing).

The fields that matter: `YEAR_BUILT_027`, `YEAR_RECONSTRUCTED_106`, `OWNER_022`,
`FACILITY_CARRIED_007`, `FEATURES_DESC_006A`, `STRUCTURE_NUMBER_008`, `ADT_029`,
`YEAR_ADT_030`. `YEAR_RECONSTRUCTED_106` uses **0**, not null, for "never rebuilt".

This is the only source that separates original construction from reconstruction. At I-10
Exit 127: *I 10 over Bullard Ave OP, **built 1978, reconstructed 2011**, owner 01, ADT 151,675
(2019)* — and ADOT's `YearLastConstruction` for that stretch is 2011-01-30. Reporting only the
later date would erase a third of a century. The oldest county-owned structures go back
further still: `Old US 80 over Gila River, built 1927, reconstructed 2012`.

`OWNER_022` is an independent ownership cross-check: `01` State highway agency · `02` County ·
`03` Town/township · `04` City · `26` Private · `27` Railroad · `62` Bureau of Indian Affairs.

**It is a sometimes-source and must be gated.** It hit 1 of 6 test pins at 150 m and 3 of 6 at
400 m. Match on `FACILITY_CARRIED_007` against the segment already identified: at the Sun City
pin two structures fall inside 400 m carrying *Royal Oak Rd* and *99th Ave*, and reporting
either to someone standing on Santa Fe Dr would be exactly the confident false positive that
got USAspending dropped.

Not useful on the same org: `Bridges_Funding` is state-level aggregate, `NBI Element Data` is
component condition, and the HPMS services cover only the National Highway System. ADOT's own
`ATIS` layer 17 `LRSE_Structure` has `YearBuilt` on just 9.5% of rows and carries no NBI
number — NBI is the better source.

---

### 7.2 Jurisdiction — which county am I in?

```
https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer/1
https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/Places_CouSub_ConCity_SubMCD/MapServer/4
```

Keyless, ~0.3-0.6 s. Returns `{"GEOID":"48201","NAME":"Harris County","STATE":"48"}` and, where
the pin is inside an incorporated place, `{"GEOID":"4835000","NAME":"Houston city"}`. An empty
place response is a real answer — unincorporated county — not a failure; verified at Lone
Mountain.

`State_County` publishes 71 layers, repeated state/county pairs one per vintage. **Layer 1 is
the current one.** It rejects the `x,y` comma shorthand with HTTP 400 but **accepts
`esriGeometryEnvelope`**, so a 2 m envelope answers a point query through the existing client.

**`NAME` is rendered verbatim and never suffixed.** Louisiana returns `"East Baton Rouge
Parish"`, Alaska returns boroughs and census areas, Virginia has independent cities that are
county equivalents. Appending "County" is wrong in four states and Puerto Rico.

The county polygon is fetched once with `maxAllowableOffset=0.001` **and `outSR=4326`** (§10.4)
and then reused: containment is answered locally by ray casting, so a drive stays in one county
for one request rather than one per GPS fix. Measured sizes at that offset:

| County | Vertices | Size |
|---|---|---|
| Philadelphia PA | 109 | 2.3 KB |
| Suffolk MA | 128 | 2.8 KB |
| Maricopa AZ | 219 | 4.7 KB |
| East Baton Rouge LA | 269 | 5.8 KB |
| King WA | 388 | 8.3 KB |

### 7.3 Census TIGER/Line — the name, anywhere

```
https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/Transportation/MapServer
```

Layers are split by road class and a query does **not** fall through between them, so all three
are asked at once: **2** primary (17,678), **6** secondary (248,117), **8** local
(**16,098,190** — everything else). Fields `NAME, MTFCC, RTTYP`.

**There is no ownership, no maintainer and no construction date. It is a gazetteer.** `RTTYP`
is how a route is *signed*, not who maintains it — Williams Dr, a county arterial, is plain
`S1400`/`M`.

**The radius floor is real.** A 60 m envelope in downtown Boston returns **nothing on all nine
layers**, not because of a coverage gap but because TIGER centrelines are positionally coarse.
At 150 m — the app's own search radius — Boston returns eleven streets, Baton Rouge seven,
Philadelphia four, Houston ten. Anything below ~120 m makes this source silently useless in
exactly the dense places it is most needed.

MTFCC classes worth naming: `S1100` primary · `S1200` secondary · `S1400` local street ·
`S1500` vehicular trail · `S1630` ramp · `S1640` frontage road · `S1730` alley · `S1740`
service road. Walkways, stairways and bike paths are not roads this app answers for.

### 7.4 FHWA National Highway System — the only national ownership

```
https://geo.dot.gov/server/rest/services/National_Highway_System/MapServer/0
```

Keyless, **498,226 features**, `maxRecordCount` 1000, `supportsStatistics: false`. Fields
`LNAME, SIGN1, NHS, OWNERSHIP, FCLASS, AADT, STFIPS, CTFIPS, ROUTEID, YEAR`. Real HPMS ownership
codes. Live in Boston:

```
JOHN F FITZGERALD EXWY  SIGN1 I93  OWNERSHIP 1  FCLASS 1  AADT 111296
TREMONT ST              SIGN1 " "  OWNERSHIP 4  FCLASS 3  AADT  15848
```

That reads directly as *I-93 is state-owned, Tremont St is the city's*.

**Its limit is the point.** The NHS is interstates, principal arterials and connectors — roughly
4% of the network. Williams Dr returns empty; so does downtown Houston. Off the NHS this source
says nothing about ownership, and that is the honest edge of what is knowable nationally.

**Name-gated, like NBI in §7.1.** NHS lines sit tens of metres off a local centreline, so an
envelope beside a city street will return the expressway two blocks over. Unless `LNAME` matches
the road already identified, this source contributes nothing.

`YEAR 2018` throughout — that is the data year, not a construction date.
## 8. Second-wave sources (verified, deliberately not in v1)

### MAG regional TIP

```
https://services1.arcgis.com/MdyCMZnX1raZ7TS3/arcgis/rest/services/TIP_data_gdb/FeatureServer
```

Layers `0` Points (50), `1` Lines (291), `2` Polygons (108), `3` Multipoints (18), table
`4` TIP_phase (8,266 rows, work years 2003–2050). Keyless, CORS-open, `f=geojson`. Join key:
`dbo_vwTIPMapData_SegmentID` → `TIP_phase.SegmentID`. `TIP_phase` carries `TIPID`, `Phase`,
`WorkYear`, `FederalAmount`/`RegionalAmount`/`LocalAmount`, `ObligationDate`, and **`TRACS`**.

At Yuma Rd & Estrella Pkwy it returns the real project:

```json
{"dbo_vwTIPMapData_AgencyName": "Goodyear",
 "dbo_vwTIPMapData_ProjectName": "Yuma Road: Estrella Parkway to Litchfield Road",
 "dbo_vwTIPMapData_ProjectDescription": "Construct six lanes with landscaped median",
 "dbo_vwTIPMapData_LocalAmount": 34213675, "dbo_vwTIPMapData_STIPID": "105943",
 "dbo_vwTIPMapData_DateActiveYear": 2028, "dbo_vwTIPMapData_VersionStatus": "Approved"}
```

Held out of v1 for three reasons: it is a **forward-looking program** (work years 2028, 2030 —
not a build history), it returned **0 features** at the unincorporated test point, and every
field is prefixed `dbo_vwTIPMapData_` / `SCDATALOADER_SCORPIONS_Lines_` and needs a
normalization map.

**`*.azmag.gov` is unusable from a device.** `geo.azmag.gov`, `azmag.gov` and the TIP program
page all return HTTP 403 with `cf-mitigated: challenge` — an interactive Cloudflare challenge,
not a User-Agent sniff. A full desktop UA does not get through. `URLSession` never will. Use
the ArcGIS Online org above, which is not behind Cloudflare.

*Decoy warning:* the top ArcGIS Online search hits for "MAG TIP"
(`services2.arcgis.com/EiGeaCDLpVDPqdJ5`, owner `msilski_MAG`) are **Mountainland Association
of Governments, Orem, Utah**. Same acronym, wrong state.

### City GIS

Both city servers use `/server/rest/`, **not** `/arcgis/rest/` — the latter 404s.

**Goodyear** — `https://maps.goodyearaz.gov/server/rest/services`
- `Basemaps/Transportation/MapServer/4` "Streets" (**layer 4**): `Ownership` (`Public`/
  `Private`/`Unknown`), `MaintBy` (`Goodyear`/`MC`/`ADOT`/`Private`/`Other`), `CLASS`,
  `STATUS`, `SOURCE` (includes **`PLAT`** — flags developer-platted segments), `L_jur`/`R_jur`.
  `DateAdded` is a GIS record date, not construction. No CIP id on the centerline.
- `.../MapServer/7` "ROW Dedication": `ORD_NO`, **`MCR_NO`** (Recorder book-page), `DEED_NO`,
  `ROW` (street names), `RECORD_DATE`, `RECORD_YEAR` — the developer-dedication paper trail.
- `.../MapServer/23–27` Pavement Projects FY23–FY27: `Project_Name`, `Fiscal_Year`, `Status`,
  `Treatment`, `Start_Date`, `Completion_Date`, `Warranty_Date`, **`SPG_SUBDIVISION`**, and a
  `Material_Description` already written in consumer prose.
- AGOL org `services5.arcgis.com/89INMfS7IDCndmLF` —
  `Capital_Improvement_Projects_(CIP)_View/FeatureServer/0` has `ProjectNumber`, `Name`,
  `CurrentPhase`, `Budget`, `Manager`. `Start`/`End_` are **strings** ("November 2023").
- Gap: no queryable subdivision/plat polygon layer. `Parcels_and_Addressing/MapServer/8`
  ("Tract") returns no fields and no features — it is cartographic annotation, not data.

**Buckeye** — best schema of the group. AGOL org `services1.arcgis.com/sixrqw8b8BHDvWq2`:
`StreetOwnership_View/FeatureServer/0` has `Developmen`, **`Constructi` (real year built)**,
`SurfaceOwn`, `StreetHier`, `PaserRatin`, `LastTreatm`, `Cost`, and a `Contractor` column —
which is populated with `" "` (a single space) on every record sampled. The field exists and
is unused. `Subdivisions/FeatureServer/0` is the plat layer Goodyear lacks.

**Phoenix** — `https://maps.phoenix.gov/pub/rest/services/Public/STR_StreetCenterline/MapServer/0`.
`JURISDICTION` domain covers neighbouring cities (`Phoenix, Maricopa County, ADOT, Avondale,
Glendale, Peoria, Scottsdale, Tempe, Tolleson, …`), which makes it a **valley-wide fallback**
for towns with no server of their own. `CREATE_DATE` is a bulk-load timestamp (everything
sampled = 2020-03-12), not construction.

**Avondale** — `https://maps.avondaleaz.gov/server/rest/services/Transportation/STREET_CL/MapServer/2`.
Note **layer 2**, not 0 — layer 0 returns an empty field list and zero features, an easy false
negative. `OWNERSHIP`, `OWNER_LT`/`OWNER_RT` (carries `GOODYEAR`, `LITCHFIELD PARK`, etc.),
`ST_CLASS`, `PavementMain`.

**No public ArcGIS REST root found** for Litchfield Park, Tolleson, Surprise, Peoria, or
Glendale. Fall back to Phoenix's `JURISDICTION`-tagged centerline or to MCDOT.

### Checked this round and rejected

- **RIT layer 12, Public Land Ownership.** 1:100,000-scale SMA polygons. One 1,294-acre
  "Private Land" polygon matched both the Lone Mountain and Goodyear pins — twenty miles
  apart. Usable only as a coarse "this area is State Trust / BLM / tribal land" sentence,
  never as the ownership of a road.
- **RIT layer 15, Right-Of-Way Permits.** 29,528 points, dense and recent (2013–2026), but
  **no date field** (the year is only parseable out of `PermitID`) and `ScopeOfWork` is
  unstructured free text. It answers "who has been digging here lately", not "who built it".
- **MAG TIP, spatially.** 467 geometry features against 8,266 phase rows, and 287 of 291
  lines are `Completed = 0`. The phase table *does* hold real money — 2,907 completed pre-2020
  rows, 2,903 of them with amounts — but only reachable via `TIPID LIKE 'MMA%'` (the county
  prefix; `MAR` is the City of Maricopa in Pinal County) and never by geometry. `ObligationDate`
  is populated on 0.4% of rows and `VersionStatus` is `"Approved"` on all 8,266, so neither is
  a usable filter. The v1 deferral was right about the shapes and wrong about the table.
- **ATIS pavement stack (layers 34/13/14/43), AADT (47/48/49), functional class, NHS,
  carriageway.** All real and queryable — layer 34 even exposes a genuine 1993 overlay that
  layer 3 hides. But they describe the road's *characteristics*, not its authorship.
- **Empty or broken:** `Property/RightOfWayPermit` returns HTTP 200 with zero layers and a 404
  on `/0`; `dot/rest/services/AssetIntegration` is `{"folders":[],"services":[]}`; the four
  `Survey/*` services carry only geodetic control and land subsidence.

---

## 9. Test pins

Each reaches a different path. The last two are derived from the data rather than eyeballed —
picking coordinates by sight put an earlier "Deer Valley Rd" pin 206 m off the road, and in
Peoria rather than the county.

| Coordinate (lon, lat) | Expected path |
|---|---|
| `-112.528617, 33.767648` | Lone Mountain Rd — unincorporated, dirt; declared 2014-09-24, ROW by road easement. **Moved onto the centreline**: the original eyeballed coordinate sat 104 m off the road, which the proximity gate now correctly refuses to name |
| `-112.4118, 33.4386` | Goodyear — layer 7 hits, layer 2 **empty**; "city maintains this" |
| `-112.3756, 33.4602` | I-10 — ADOT inside Goodyear's limits; built 2011, TRACS H729601C; bridge built 1978/rebuilt 2011; $4.16M FFY2018 |
| `-112.2749, 33.5988` | Sun City — declared 1982-12-10; two NBI structures nearby carrying *other* roads |
| `-112.4448, 33.3939` | MC 85 — a road whose name genuinely ends in digits; acquired by ADOT resolution |
| `-111.6672, 33.4662` | McDowell Rd — **spot** TIP project TT0408; the linear record for the same project is 401 m away on another street. Declared 1970 |
| `-112.3177, 33.6894` | Williams Dr — county arterial, TIP project TT0248, declaration via *plat* name match |

Outside Arizona, one pin per tier. `./scripts/probe.sh <name>` runs any of them.

| Coordinate (lon, lat) | Name | Expected path |
|---|---|---|
| `-75.16558, 39.95851` | `philadelphia` | PennDOT `JURIS=1`: VINE ST, `YR_BUILT` 1959, `YR_RESURF` 2017 |
| `-75.1652, 39.9526` | `phillylocal` | Same street, `JURIS=5` stretch — `YR_BUILT` is **0** and must not reach the record |
| `-91.14597, 30.41927` | `batonrouge` | BALIS DR — name and owner, and deliberately **no year**: 1971 belongs to Perkins Rd |
| `-91.14783, 30.41862` | `perkins` | PERKINS RD — the one 1971 row in that box, reached through the measure join |
| `-95.3698, 29.7604` | `houston` | TxDOT: BAGBY ST joined from `MAP_LBL`, municipal, 1,096 AADT; NBI still dates the 1959 bridge over Buffalo Bayou |
| `-97.741957, 30.263227` | `sanjacinto` | **Derived from the layer's geometry**: 0.1 m from SAN JACINTO BLVD with state-owned Loop 343 54.7 m away, inside the gate. Must come back *municipal*, 4,335 AADT — never Loop 343's 25,046 |
| `-97.676922, 30.490050` | `i35tx` | `ADMIN=1`: TxDOT owns and classifies it, but `MAP_LBL` is the shield label `35`, so the name must come from TIGER as `I- 35` |
| `-95.667328, 31.654532` | `txcounty` | `ADMIN=2`: COUNTY ROAD 2108, county-owned, 47 AADT |
| `-95.506920, 29.564598` | `txtoll` | `ADMIN=6`: Fort Bend Parkway, toll authority, 41,183 AADT — an off-system row whose `MAP_LBL` *is* a real name |
| `-71.0589, 42.3601` | `boston` | NHS ownership; also the TIGER 60 m empty-envelope regression |


---

## 10. The state tier — what the other 49 states actually publish

Fourteen state DOTs probed on 2026-09-07. **All fourteen are keyless; not one needed a token.**
Three findings shape the design.

**They split into two structurally different shapes**, and one adapter cannot read both.

| Shape | States | Form |
|---|---|---|
| `lrsEvents` | AZ, LA, VA | One attribute per layer, joined on route id + measure range. 3-5 queries per answer. |
| `flatInventory` | PA, TX, NY, IA, OH, TN | One denormalised polyline carrying everything. TxDOT returns 133 fields in a single hit. |

**Two code spaces genuinely standardise**, because both are what FHWA requires in a state's
annual HPMS submission — Louisiana's own layers are stamped `DataSource: "2024 HPMS Submittal"`:

- **HPMS ownership**: `1` State · `2` County · `3` Town/township · `4` Municipal · `26` Private ·
  `31`/`32` Toll authority · `50`,`62` Tribal · `60`-`74` Federal. Seen across five unrelated
  states. Louisiana emits `1,2,3,4,11,21,25,26,32,63,64,66,70,72,73,74,80`; the NHS emits `1,2,4`.
- **FHWA functional class** `1`-`7`. Exactly `1..7` on Louisiana's layer 84. **New York is the
  exception** and must not use the shared table — it publishes a two-digit extended scheme
  (`"19-Urban Local"`).

**Nothing else standardises.** Not field names, not value encoding (`4` vs `"04-Municipal or
City Hwy Agency"` vs `"DOT-Arizona Department of Transportation"`), and not route id formats.
**Almost no service publishes coded-value domains.** NCDOT is the single exception found in this
whole survey (§18). Every other one — ADOT layer 29, Iowa, TxDOT, Louisiana and PennDOT
all return `domain: null`, and TxDOT says `ADMIN: NO DOMAIN` outright. The decode tables have to
ship with the app; the agency will not tell you what a `4` means.

### 10.1 Pennsylvania — the trap, and the field that actually works

```
https://gis.penndot.pa.gov/gis/rest/services/opendata/roadwaysegments/MapServer/0
```

`STREET_NAME, ST_RT_NO, SEG_NO, YR_BUILT, YR_RESURF, JURIS, MAINT_RESPON_IND, CUR_AADT`.
113,827 segments. Live at central Philadelphia: `SIXTEENTH ST YR_BUILT 1916 YR_RESURF 2004`,
`VINE ST 1959 / 2017`, `BROAD ST 1927 / 2016`.

**`MAINT_RESPON_IND` is not HPMS and must not be read as it.** Distinct values
`10,19,20,29,30,39,40,49,50,60,69,70,80` — close enough to HPMS-times-ten to look usable. Every
segment in downtown Philadelphia reads `40`, **including I-676, the Vine Street Expressway, at
64,768 AADT**. Decoded as HPMS `4` that says a state expressway is city-maintained. It is also
populated only on `JURIS = 1` rows, so it is not an ownership field at all.

**`JURIS` is the ownership field.** Distinct values are exactly `1,2,5,6`:

| Code | Meaning | Segments |
|---|---|---|
| 1 | PennDOT | 101,354 |
| 2 | Pennsylvania Turnpike Commission | 685 |
| 5 | Local government | 11,737 |
| 6 | Interstate bridge commission | 51 |

**`YR_BUILT` is a state-system fact only.** `YR_BUILT>0` returns 101,006 — but
`YR_BUILT>0 AND JURIS='5'` returns **0**. That is 99.7% of PennDOT-owned segments and none of
the locally owned ones. The earlier reading of "89% of 113,827 including local streets" was
wrong, and the UI must not imply local coverage.

**Two null sentinels, both of which parse as valid values.** `YR_BUILT = 0` and `YR_RESURF = 0`
on every `JURIS = 5` row — read naively that is "year 0", or 1970 once a date decoder touches
it. And `TRAF_RT_NO = "000"` on any road with no signed route number, which would otherwise
render as *Route 000*. Handled by `nullNumbers` and `nullStrings` in the profile.

### 10.2 Louisiana — an LRS, and the join that has to be right

```
https://gis.dotd.la.gov/road/rest/services/Roads_and_Highways_OpenData/MapServer
```

115 layers. The ones used:

| Layer | Name | Rows | Carries |
|---|---|---|---|
| 49 | Louisiana Roadways | **576,063** | `FullName`, `Ownership`, `RouteID`, measures |
| 91 | Ownership | 162,871 | HPMS `Ownership` |
| 69 | Last Construction | **3,642** | `YearLastConst` |
| 70 | Last Improvement | — | `YearLastImprove` |
| 84 | Functional System | — | `FunctionalSystem` 1-7 |

Layer 49 is the reason Louisiana is worth having: it is a statewide centreline that **does reach
residential streets**, so name and owner are answerable on ordinary local roads. Layer 3
"Local Road Names" is **empty — 0 features. Do not wire it.**

Layer 69's 3,642 rows against layer 91's 162,871 is the honest measure of date coverage: about
2% of the network, and it is the state control-section network. Live on I-10 at Baton Rouge:
`YearLastConst 1959`, `YearLastImprove 2000`, `Ownership 1`, `FunctionalSystem 3`, all on
`RouteID 013-04-1-010`.

**Layers 49 and 91 disagree, and 91 wins.** Balis Dr reads `Ownership 2` (county) on the route
layer and `4` (municipal) on the dedicated HPMS event table. The catalog lists 91 first.

**Two route-id namespaces in one service**: `013-04-1-010` for control sections and
`033900412201591020` for local roads. Arizona space-pads to 32 characters. **Compare raw, never
parse** — normalisation exists to join across services, which this app never does, and can only
manufacture false joins.

**The join is why `LRSJoin` exists.** In a 150 m box around Balis Dr the construction table
returns exactly one row: `033903558402991001`, measures 1.653-2.26, year 1971. That route is
**Perkins Rd**, which runs through the same box as three consecutive segments (1.930-1.999,
1.999-2.072, 2.072-2.203). Take the first event in the envelope and Balis Dr is dated 1971.
Filter on the pin's own route id and Balis Dr correctly gets no year at all.

The same bug was already live in Arizona. `atis_2_i10` returns five improvement events for ramp
`I 010127E` with `YearLastImprovement` of 2008, 2009 and 2011 across disjoint ranges, and
`atis_24_i10` returns **thirteen TRACS numbers** for `I 010`. `ADOTStateRouteSource` matched on
route id and then took `.first`. It now ranks by proximity, and its twelve tests are unchanged.

### 10.2b Texas — 133 fields, not one of them a name

Two services, and neither is usable alone:

```
https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_Roadway_Inventory/FeatureServer/0
https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_Roadways/FeatureServer/0
```

The inventory is 1,027,891 segments and **133 fields, of which none is a street name** —
`ADMIN`, `F_SYSTEM`, `ADT_CUR`, `ADT_YEAR`, `NUM_LANES`, `HWY`, `HSYS`, `RIA_RTE_ID`. The names
live on `TxDOT_Roadways` (574,990 rows, `MAP_LBL`), which in turn carries **no ownership**.

**`GID` joins them 1:1**, and the server coerces a quoted integer, so the existing
`field='value'` query works unchanged:

```
TxDOT_Roadways/0/query?where=GID='52353' AND SYSTEM='Off'   ->  MAP_LBL = SAN JACINTO BLVD
```

This is why `NameJoinProfile` exists, and the reason is not tidiness. Without the join the app
names a Texas road from the national tier and owns it from the state tier — and the two
routinely describe **different roads**. A mid-block pin on San Jacinto Blvd in downtown Austin
has Loop 343, a state route at 25,046 AADT, **54.7 m away — inside the 60 m proximity gate**.
TIGER would have said *San Jacinto Blvd* while TxDOT said *state highway agency*: coherent,
confident and wrong. Joined, name and owner come from one segment or from neither.

**`ADMIN` is the ownership field and is not HPMS** — the same trap as PennDOT's, made more
inviting because `ADMIN` sits beside `F_SYSTEM`, which *is* the FHWA code space. It runs
`1...16`, and HPMS defines nothing at 5-10 or 13-16. The service publishes `ADMIN: NO DOMAIN`,
so it was derived by cross-tabbing every code against `HSYS` over all 1,027,891 segments. The
partition is exact — each code maps to one family of systems, which is what an ownership field
should do and what `MAINT_RESPON_IND` conspicuously did not:

| `ADMIN` | `HSYS` | Segments | Owner |
|---|---|---|---|
| 1 | IH, US, SH, FM, RM, SL, SS, BU, BI, BS, BF, UA, UP, PR, PA, FS, RE, RS, RR | 289,274 | TxDOT |
| 2 | CR | 302,900 | County |
| 4 | LS | 427,315 | City or municipal |
| 5, 6, 16 | TL (+ tolled SH/SL) | 3,237 | Toll authority |
| 3, 7-15 | FD | 5,165 | Federal — *which* agency is unrecoverable, `HWY` is null on all of them |

Confirmed against three roads whose owner is independently known: I-35 and Loop 343 read `1`;
San Jacinto Blvd reads `4` and carries `SYSTEM = Off` on the roadways layer.

**`MAP_LBL` is a map *shield* label, not a name.** On-system rows carry `35`, `175`, `10C`;
toll rows carry `_`; some city-street rows carry a single space. Joining it naively named
Interstate 35 **"35"** and the Sam Houston Tollway **"\_"**. The join is therefore filtered to
`SYSTEM='Off'` with `_` as a null string, which leaves interstates and state highways to be
named by TIGER — which spells them out — while off-system rows keep TxDOT's own name. Toll
roads that *do* carry a real label still get it: *Fort Bend Parkway*, 41,183 AADT.

**Texas publishes no construction year at all.** `SURF_TREAT_YEAR` is populated on 109,233 of
1,027,891 rows (10.6%) with values back to 1918, and it is a last-surface-treatment date, not a
build year — so it is deliberately **not** mapped to `yearBuilt`. Texas ships with a
`dateCaveat` saying so on the card.

### 10.2c Texas — the construction register, and the answer to leg 3

```
https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_DCIS_All_Projects/FeatureServer/0
https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/ProjectTracker_AGO/FeatureServer/1
```

DCIS — the Design and Construction Information System — is published as a **spatially queryable
polyline layer of 73,306 projects**, and it is the richest source in this app. Verified live:

| Field | Coverage |
|---|---|
| `PROJ_ESTMTD_LET_D` | 73,290 — let dates from **1970-10-01 to 2050-08-01** |
| `EST_CONSTRUCTION_COST` | **73,085 (99.7%)** |
| `TYPE_OF_WORK` | 72,581, of which 1,500 are the placeholder `Legacy` |
| `PROJ_CLASS` | a **66-value controlled vocabulary** |
| `PROJ_STAT` | 51,145 Closed, 21,833 Active, 328 paused or inactive |

`ACTUAL_LET_DATE`, `DIST_LET_DATE` and `EST_CONST_COST` are all **empty on every row** — the
populated fields are `PROJ_ESTMTD_LET_D`, `COMMISSION_AWARD_OF_CONTRACT` (13,128) and
`EST_CONSTRUCTION_COST`. Reaching for the obviously-named field gets nothing.

`ProjectTracker_AGO` layer 1 joins on the nine-digit CSJ and adds **`CNSTR_CMPNY_NM`, the
construction company**, with `CNSTR_WKBG_DT` and `CNSTR_PCT_COMPLETE`. It holds 17,469 rows of
which 7,542 name a company, and **every one is live or near-term work** — 7,391 "underway or
begins soon", 151 "within 4 years". There is no contractor for history.

**`PROJ_CLASS` is what makes this usable**, because it separates building from maintaining
mechanically where free text cannot. `Seal Coat` is the largest class in the state at 26,101
projects, so a rule that let maintenance answer *who built this road* would answer it wrongly
more often than not. `CodeTables.workKind(txdot:)` buckets the vocabulary; an unrecognised class
is ancillary, never a build.

**Two traps in the money.** The largest number on a stretch is often not construction: at the
I-35 test pin the top two amounts are a **$53.5M `Preliminary Engineering`** and a **$30.1M
`Intersection & Operational Imprv`**, while the biggest actual build already let is a **$12.6M
`Widen Freeway` from 1988**. And the single largest project of all is a **$1.62bn freeway
widening let in 2037**, which has not happened. Ranking by cost alone, or failing to exclude
future let dates, produces a confident wrong answer in both directions.

**Geometry is control-section-wide, not project-wide.** A `WIDEN BRIDGE AND APPROACHES` job with
`PROJ_LENGTH` 0.001 mi is drawn across 6.44 km of highway. So a match means *this job was on this
stretch*, not *at this point* — which is why `LIMITS_FROM`/`LIMITS_TO` are carried and shown.

**The gate is 25 m, not the usual 60.** Project lines are derived from the same LRS as the
roadway, so they sit almost on the centreline: the 22 genuine projects at the I-35 pin measure
6.8-10.5 m. At the mid-block San Jacinto Blvd pin DCIS returns exactly one project — **State Loop
343's 2029 overlay, 55.0 m away** — which is inside `RoadProximity.onRoadMeters` and would credit
a city street with a state highway's history. See §5.3b; this is the third time this class of bug
has appeared.

**It is a state-system dataset.** Zero projects at Bagby St in Houston, at County Road 2108, and
at the Fort Bend Parkway pin. 812 projects carry a `CS` highway number and 573 a `CR`, so the
coverage off-system is not nil, but it is thin — and `SURF_TREAT_YEAR` is state-only too
(109,223 rows, **all `ADMIN = 1`**). Texas's 427,315 local-street and 302,900 county segments get
name, owner, class and traffic, and no dates.

### 10.3 Construction year: three states of fourteen

| State | Field | Coverage |
|---|---|---|
| Arizona | `YearLastConstruction` | 5,553 / 5,638 (98.5%) |
| Pennsylvania | `YR_BUILT` | 101,006 — state-owned only |
| Louisiana | `YearLastConst` | 3,642 rows — control sections only |
| Texas | *none* | 0 — `SURF_TREAT_YEAR` is resurfacing, on 10.6% of rows |

**Ohio's `LAST_CONST` is a trap.** 5,804 of 58,127 rows non-null (10%), and the non-null values
are `-2209161600000` — epoch for 1900-01-01, a placeholder. Ohio's official server
`gis.dot.state.ohio.gov/arcgis/rest/services` returns **404**. *(A different and much better
Ohio service was found later and is shipped — see §19. It carries no construction field at all,
which is exactly why it is safe.)* Texas `SURF_TREAT_YEAR` is last surface treatment, not
construction; a weak lower bound at best.

**Cost: one of fourteen.** Thirteen of the fourteen publish no construction cost on a road
segment, as Maricopa does not (§6). **Texas is the exception** and a substantial one:
`EST_CONSTRUCTION_COST` on 73,085 of 73,306 projects, plus a named contractor on live work
(§10.2c). The earlier "zero of fourteen" in this document was wrong.

### 10.4 The portability trap, and why the client was already immune

`distance` + `units` point-buffer queries return **zero features with HTTP 200** on Caltrans,
WSDOT and FDOT, while working on TxDOT, PennDOT, Ohio and Iowa. `esriGeometryEnvelope` works on
all of them.

This is §4's Maricopa quirk again, in three more states. `ArcGISClient` builds only envelopes,
so the app cannot express the broken form. **Never add a point-buffer query mode.**

One related sharp edge: **`maxAllowableOffset` is measured in the units of the *output* spatial
reference and silently does nothing without `outSR`.** A Harris County boundary comes back at
369 KB without it and 8 KB with it — a 45x difference, no error either way.

### 10.5 Bluntly unusable

- **California.** `caltrans-gis.dot.ca.gov/.../All_Roads/FeatureServer/0` has ten fields and
  every one is plumbing: `OBJECTID, RouteId, LRSFromDate, LRSToDate, CreatedUser, CreatedDate,
  LastEditedUser, LastEditedDate, GlobalID, Shape__Length`. No ownership, no year, no class.
  The largest DOT in the country and the thinnest endpoint probed.
- **Florida.** Fragmented into ~70 single-attribute services. Assembling one road's story means
  querying dozens.
- **Washington.** `StateRoutes/0` is route geometry only.
- **Tennessee.** 32 fields, no AADT, no year.

---

## 11. County GIS at national scale — auto-discovery does not work

Twelve counties tested against the ArcGIS Online and Hub search APIs. **The correct authoritative
county road layer was the top result for 1 of 12**, and the failures are confident rather than
empty:

| Query | Top result | Why it is wrong |
|---|---|---|
| Harris County TX | `Houston Road Centerline` | City, not county |
| King County WA | `King and Queen County Road Centerlines` | Virginia |
| Cook County IL | `Road Centerlines … Minnesota` | Minnesota |
| Miami-Dade FL | `Edge of Pavement Centerline 2001` | Right org, 25 years stale |
| Cabarrus County NC | `North Carolina Rail Road Centerline` | Owned by `cabarruscounty.us`, titled "Road Centerline" — **railroads** |
| Sedgwick County KS | *(zero results)* | Population 525,000 |

King County's actual centreline is named **`TRANS_NETWORK_LINE_394`**, which no keyword search
reaches; its org exposes 1,173 services with machine-generated names. There is no authority
signal to fall back on: `contentstatus:org_authoritative road centerline` returns 1,028 items
nationally, for 3,143 counties, and `hub.arcgis.com/api/v3/sites` returns **404** — there is no
enumerable registry of county Hub sites. `catalog.data.gov`'s CKAN API returns **404** on every
path; there is currently no machine-readable national catalog.

**And even on a hit, maintenance is undecodable.** Miami-Dade `MAINTCODE` distinct values are
`CM, PC, PK, UR, U, AP, CC, CI, CO, MT, SW, IS` with `domain: None`. King County publishes
`JURIS_L = 5`, an integer with no domain. NCDOT `OwnerType` is `66, 73, 72, 13, 50, …`. Three
independent counties and a state DOT, three encodings, zero domains. This is §5.3's
`aquisition_type` problem, nationwide and structural.

Zero fields are common to all six county schemas compared. Cook County has **no maintenance
field at all** on its street layer — it lives on a separate layer with a different name field.

**Conclusion: curated per-county profiles are the only correct path. Do not build discovery.**
The one reliable programmatic surface is a county's own DCAT feed
(`<hub-domain>/api/feed/dcat-us/1.1.json`, complete and accurate) — but you must already know
the Hub domain, and nothing enumerates those.

Statewide aggregations exist in a minority of states and reduce ~3,143 integrations to ~50 where
they do: **NC** `NCDOT_RoadCharacteristicsQtr` (1,201,628 rows), **TX** `TxDOT_Roadways`
(574,990, though only 28,331 in Harris County against the City of Houston's 235,765), **ME**
MaineDOT (100,799). Florida and Wisconsin publish no statewide road layer.

---

## 12. Rejected outright, with the numbers

**OpenStreetMap / Overpass.** The tags that would answer the question are not populated.
Measured with `out count` over whole-city bounding boxes:

| Tag | Boston (11,493 drivable ways) | Maricopa (8,708) |
|---|---|---|
| `name` | 98.5% | 96.6% |
| `surface` | 86.3% | 80.5% |
| `start_date` | **2.8%** | **0.0%** |
| `operator` | **0 ways** | **0 ways** |

`operator` was present on literally zero ways in both metros. Overpass also allows 2 slots per
IP on donated hardware and returned **HTTP 504 on 3 of 8 requests** during probing; the
`overpass.kumi.systems` mirror timed out after 199 s on the same query. A shipped app polling it
is not acceptable use. Dropped, not deferred — same as USAspending in §6.

**FHWA ARNOLD and the full HPMS release.** `geo.dot.gov/server/rest/services` lists
`ARNOLD_Inventory_HPMS`, `HPMS_Public_Release`, `HPMS_Measure` and `NonPublicHPMS`. Every one
returns `{"error":{"code":499,"message":"Token Required"}}`. These are the two datasets that
would actually solve national coverage, and they are unreachable from a keyless client. The one
public ARNOLD service, `Arnold_NH_2020`, is New Hampshire only and carries no ownership.

**Ohio, California, Florida, Washington, Tennessee** — see §10.3 and §10.5.

---

## 13. The coverage catalog

`Sources/RoadCore/Resources/coverage.json` says which jurisdictions this build can read and how.
It ships in the bundle and is refreshable from static hosting, so a state whose endpoint moves
is fixable without an App Store release.

**The boundary, stated plainly: the catalog can name, order, configure and disable sources. It
cannot define one.** Adding a state on either generic adapter is a catalog edit. Adding a county
at Maricopa's depth is a build, because that depth is judgement — concluding ownership from a
layer's *silence* (§1.2), disambiguating coincident geometry 2 m apart (§3.1), gating a join on
a name (§7.1), reading a project number out of free text (§3.2). Configuration should not try to
express those, and `adapter: "bespoke"` is how a profile says so.

What a profile *can* express: one spatial query per layer, an exact-key plus measure-overlap
join, field-to-field mapping with code tables, three year encodings, null sentinels for numbers
and strings, and layer ordering. That is precisely MCDOT's field-mapping half and none of its
logic.

### Rules that are not obvious

- **Version skew is per entry, not per catalog.** Each entry carries `minSchema`; an app that
  does not understand one skips *that entry* and loads the rest. Rejecting the whole file
  because one new state uses a newer field would turn a single addition into a total outage
  everywhere.
- **Bundled wins on a tie or when newer.** A downloaded catalog with a lower `catalogVersion`
  than the bundled one is ignored, so an app update is never undone by a stale file on disk.
- **HTTPS only.** The catalog decides which hosts the app calls; an entry carrying a plaintext
  URL is a redirect primitive, not a typo, and is dropped.
- **`Provenance.isBundled` is not overloaded for this.** A catalog entry is configuration, not a
  value — PennDOT's road data still came live from PennDOT. Catalog staleness is reported
  separately through `Coverage.catalogCapturedOn`.
- **Layer order encodes precedence.** Louisiana lists layer 91 before the route layer's own copy
  of `Ownership` because the two disagree (§10.2), and `RoadRecord.merge` is first-writer-wins.
- **A joined field is filtered where its meaning changes by row.** `NameJoinProfile` takes a
  structured `filterField`/`filterValue`, not a clause fragment, so a value from a remotely
  fetched catalog is escaped exactly like the key and cannot widen the query. TxDOT needs it
  because `MAP_LBL` is a street name only on `SYSTEM='Off'` rows (§10.2b).
- **Tiers run state, then county, then national**, for the same reason: a pin on I-10 sits
  inside Goodyear's city limits, so ADOT must claim it before a county source infers a municipal
  owner (§3).

### Coverage levels

| Level | Meaning | Example |
|---|---|---|
| `county` | Somebody did the §1-§2 reconnaissance | Maricopa County |
| `state` | A state DOT publishes the road | Pennsylvania, Louisiana, Texas |
| `national` | TIGER name, NHS ownership if on it, NBI if a structure is | Suffolk County, MA |

The level is set by the pipeline factory, never by a source — only the factory can tell *no
source is mapped here* from *a source is mapped and found nothing*, and that distinction is the
entire content of the sentence the card shows.

---

## 14. The city tier — two Texas cities, and why not the other two

Off the state system TxDOT publishes nothing dated: 427,315 city-street and 302,900 county
segments carry owner, class and traffic and no year. Four Texas cities were probed for their own
street records. **Two publish something worth reading and two publish nothing.**

### Dallas — the best local-street source found anywhere

```
https://services2.arcgis.com/rwnOSbfKSwyTBcwN/arcgis/rest/services/PavementCondition/FeatureServer/0
```

38,564 "supersegments". `rehab_year` on **27,588 (71.5%) across 95 distinct years with no
dominant value** — the largest is 2024 at 8.4%, which is what a real distribution looks like and
exactly what San Antonio's is not. Also `name`, `from_name`/`to_name`, `descr`
("18400-18500 TIMBER OAKS DR"), `maint_resp`, `func_class`, `pave_type`, `width_ft`,
`blend_pci`/`blend_cond`, and `repair_cost`.

`rehab_type` is a **21-value vocabulary** and does the same job `PROJ_CLASS` does for the state:
`Street Reconstruction` (6,577) and `Panel Replace` build, `Slurry Seal` (6,549),
`Microsurfacing`, `Onyx` and `Mill/Overlay` maintain, and `None` (11,007) means no recorded work
rather than an unknown kind. Decoded by `CodeTables.workKind(dallas:)`.

`maint_resp` names a *level* — `City` on 38,471 of 38,564, plus `State`, `State Shared`,
`County Shared`, `City - Park` — so it gets its own table rather than `owner(named:)`, which
would render a Dallas freeway as "maintained by State".

### San Antonio — where the dates are almost all fake

```
https://services.arcgis.com/g1fRTDLeMgspWrYp/arcgis/rest/services/Pavements/FeatureServer/0
```

98,986 segments, and **`InstallDate` is populated on every single one** — which is the trap.
**96% of it is two placeholders**: `2000-01-01` on 49,782 rows (50.3%) and `1980-01-01` on
45,272 (45.7%), leaving **3,932 real dates**. Mapped at face value the app would invent a
construction year for nearly every street in the city. Both epoch values go in `nullNumbers`,
the same mechanism PennDOT's `YR_BUILT = 0` needed.

What *is* real is `Owner`, 43 values naming the body: San Antonio (51,612), Bexar County
(14,815), TxDOT (11,628), **Private (11,017)**, Ft Sam Houston, Lackland AFB, Randolph AFB,
Port Authority of San Antonio. `Surface_Type` is `TBD` on 42,576 rows, hence `nullStrings`.
Read by `CodeTables.owner(named:)`, which classifies by shape — a trailing "County", a trailing
"AFB", a leading "Camp " — because the list is a register of every municipality and installation
in a metro area and will grow.

### Houston and Austin publish nothing dated

- **Houston** `COH_RoadCenterline` — 235,765 segments with names, no construction dates. Its
  project layers hold **17** and **6** features.
- **Austin** `TRANSPORTATION_street_segment` — `CREATED_DATE` and `MODIFIED_DATE` are GIS record
  metadata, not road facts. No pavement or construction year.

The card names the covered cities for this reason, so a Houston user reads it as a gap in the
source rather than a fault in the app.

### Keyed on place, and running first

Coverage is keyed on the **seven-digit Census place GEOID** — `4819000` Dallas, `4865000` San
Antonio — which `Jurisdiction` already carried and nothing read. Not on county FIPS: **the City
of Dallas spans five counties** (Dallas, Denton, Collin, Rockwall, Kaufman) and the test pin used
here falls in Denton.

The city tier runs **before** the state tier, which is the opposite of the state-before-county
rule in §13. TxDOT files every city street for HPMS and reads them all as "city or municipal
highway agency"; San Antonio marks 11,017 of them **Private**. Running second would lose that on
every street TxDOT also carries, which is nearly all of them. The rule this imposes on a city
profile: **it must report state and county roads correctly, or not map ownership at all.** Both
shipped cities do.

A city contributes at `CoverageLevel.county`, deliberately without a level of its own:
`CoverageLevel`'s `Comparable` reads a hardcoded array through a force-unwrapped `firstIndex`, so
a case missing from that array is a crash rather than a compile error.

---

## 15. The Rio Grande Valley — six agencies, and one that had to be refused

The RGV is four counties and about 1.4 million people, and it is the first place the app went
looking where **no single source covers the region**. Every agency was probed separately.

| Source | Features | What it gives | Dates |
|---|---|---|---|
| Edinburg capital projects | 418 polygons | project, description, **contractor**, actual cost | **139 completions** |
| Pharr street inventory | 3,611 | name, owner, class, pavement, 1-10 rating, cross streets | 501 repavings, 2015-2018 |
| Cameron County roads | 3,119 | name, surface, lanes, subdivision | **none** |
| Weslaco centreline | 4,175 | name, class, jurisdiction | **none** |
| Brownsville centreline | 8,581 | name only | **none** |
| McAllen | — | nothing published | — |

### Edinburg is the best city project register found anywhere

```
https://services7.arcgis.com/z3I4HxFCWafiHSiG/arcgis/rest/services/COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0
```

`CONTRACTOR`, `CONSTRUCTION_ACTUAL`, `ACTUAL_COMPLETION` and a written `DESCRIPTION`, on 139
completed projects — *RBM Contractors, $3,324,533, 2025*. A city of 101,000 publishing what
thirteen state DOTs do not.

Two things it forced. **Polygons need containment, not distance** (`MatchMode.containsPoint`): a
project area is half a mile across, so the distance from a pin inside it to the boundary
routinely exceeds the 60 m on-road gate and nearest-line would reject the very project the pin
is standing in. And **all** containing projects are reported, not the first: a city rebuilds the
same street repeatedly and the areas overlap, so taking whichever the service returned first
picks a year at random.

It also forced `outFields` onto the profile. These rows carry about 150 fields including thirty
paragraphs of status history — **200 KB for seven features**, on what may be a phone in a car.
Naming the seven fields actually read brings that to 20 KB.

### Bare ownership levels

Pharr writes `OWNER` as `CITY` (2,461), `PRIVATE` (697), `STATE` (281), `COUNTY` (172) — a level,
true of every city in Texas and naming none of them. `FieldMapping.ownerNames` rewrites a value
before it is classified. Weslaco needs the same for the opposite reason: `JURISDICTION_LEFT` is
`WESLACO` on 2,577 segments and **`UNINCORPORATED` on 1,450**, and mapping the latter to an
empty string makes the source decline so TxDOT's own ownership answers instead. The city also
publishes `UNINCORPOARTED`, misspelled, on one segment; both spellings are mapped.

### Harlingen was probed and refused

`HARLINGEN_CAPITAL_IMPROVEMENT_PROJECTS` is **template data**, and would have been easy to ship.
Its layer is id `1`, not `0`. Its rows are named `PROJECT 1 - BUILDING & FACILITIES` and
`PROJECT 2 - DRAINAGE & STORMWATER`, every one shares the end date `2025-06-02`, and their
centroids are at **-98.147, 26.243 — in Edinburg, sixty kilometres from Harlingen**. Wired up it
would have put invented projects on real Edinburg streets.

### McAllen publishes no roads, so it is read for annexation instead

```
https://services3.arcgis.com/feieT9DHJD3rMLX7/arcgis/rest/services/Annexation_History_11_13_2024/FeatureServer/0
```

The largest RGV city publishes **no street inventory, no pavement layer and no project
register**. `Subdivision_Master` carries a `Developer` name — the most direct answer to the
app's question anywhere — but holds **40 polygons**, too few to be worth a profile.

What it does publish is 346 annexation tracts covering the city, `Year` 1927-2023, with an
ordinance number on 340 (the oldest reads `CHARTER`). **Annexation is not construction**, and
the app never shows it as such: it renders in the paper trail beside the plat and the
right-of-way, and the profile's caveat says so outright. But it bounds when the streets in a
tract could have gone in, and it is the only dated thing the city publishes.

`Annex_Date` is **negative** epoch milliseconds before 1970 — `-1354335476724` is January 1927.
Read as unsigned it would be a date in the far future.

### Two sentinels found by shipping

**A dollar is not a cost.** 429 TxDOT projects carry `EST_CONSTRUCTION_COST = 1`, and another 25
sit below a hundred dollars: `0.01`, `0.66`, `2`, `42`. A McAllen pin duly rendered *"Widen
Non-Freeway $1"*, which reads as a bug in the app rather than a gap in the register. The floor is
$100 and costs nothing real — 454 of 73,085.

**A project drawn twice is still one project.** A control section is published as several
features, so an envelope returns the same CSJ more than once and the register listed it twice,
reading as two separate jobs in the same year. Deduplicated on the control-section-job number.
Note that genuinely distinct projects *do* share a title and a year — a McAllen pin sits on four
separate `Widen Non-Freeway` CSJs let in 2040 — so the key has to be the number, not the text.

### Undated work is not work

Pharr records a `MAINTENANCE_REPAIRS` treatment on segments with no `Repave_Date`, and the first
build of this profile duly showed *"Crack Sealing, undated"*. `ProfileMapping.work` now requires
a date: the whole purpose of a work entry is to date the road, and an undated treatment tells a
reader nothing they could not see by standing on it.

---

## 16. The other Texas metros — where a construction year actually exists

Ten more cities probed. Two publish something the rest of this app almost never sees: **the year
a street was built**, not the year it was last resurfaced.

### Laredo — an actual `YEAR_BUILT`

```
https://services3.arcgis.com/h9QEFLHkUI1SIRs7/arcgis/rest/services/Pavement_Condition_Index/FeatureServer/0
```

10,627 segments with `YEAR_BUILT`, `OWNER`, `SURFTYPE`, `PCI_2019`, `PAVE_WIDTH`, `LANES` and
`FROM_STRT`/`TO_STRT`. **1980 is a placeholder on 5,405 of them — 50.9%**, against a smooth ~2%
per year across the other 53 values, so it is filtered exactly as San Antonio's `InstallDate` is.
That leaves about 5,200 genuine construction years, and *Albany Dr, built 1993, City of Laredo,
asphalt, PCI 55* is the kind of answer this app exists to give.

`BRANCHNM` carries the assembled name (`ALBANY DR`); `FENAME` and `FETYPE` hold the parts
separately and would need joining.

### Arlington — installed *and* replaced, in the fields you would not pick

```
https://services.arcgis.com/jXi5GuMZwfCYtZP9/arcgis/rest/services/COA_Street_Custodian/FeatureServer/0
```

17,359 segments carrying **two** dates, which almost nothing does. The trap is the field names.
`Built` and `Reconstructed` exist on every row and are **null on every row**; reading them gives
a city-wide source that silently answers nothing. The populated fields are **`Installed`**
(13,125) and **`Replaced`** (13,321).

Each carries one bulk-loaded default: **`1908-06-09` on 2,209 `Installed` rows** and
**`2008-06-12` on 1,370 `Replaced` rows** — single *exact dates*, against roughly 1,280 distinct
values spread under 1% each. That exactness is the tell; a real distribution does not put a
sixth of a city on one June day.

`Custodian` names the responsible body — Arlington 12,984, State 1,264, and slivers of Pantego,
Kennedale, Dalworthington Gardens, Mansfield and Grand Prairie.

Arlington also records a street rebuilt in one go as installed *and* replaced on the same day, so
`ProfileMapping` now drops an improvement date equal to the construction date — the rule the
drive card already followed, applied where the data is read.

### Checked and rejected

| City | Why not |
|---|---|
| Fort Worth | `EB_Street_Sections` is 624 polygons with only a document-update date |
| Lubbock | `CIP` holds 2 rows; `COL_Streets` 969 with no dates |
| Irving | 9,133 centrelines with `OWNERSHIP` and `MAINTBY` but no construction date |
| Corpus Christi, Plano, Garland, Frisco | no city street or pavement service found |
| El Paso | searches resolve to TxDOT's own org, not a city one |

Irving is the near miss and would be worth revisiting: ownership without a date still beats
TxDOT's blanket municipal code, and the layer is city-wide.

---

## 17. Finishing Arizona — one service covers the whole state

Until now Arizona meant Maricopa County in depth and ADOT's state routes. Everywhere else — Pima,
Pinal, Yavapai, Mohave, Coconino, and every city outside Maricopa — got a TIGER name and nothing
else. **Tucson, Mesa, Chandler, Gilbert, Scottsdale, Peoria and Phoenix publish no usable street
service of their own**; all were probed.

```
https://services6.arcgis.com/clPWQMwZfdWn4MQZ/arcgis/rest/services/ADOT_2025_Highway_Performance_Monitoring_System_(HPMS)_Roadway_Data/FeatureServer
```

ADOT publishes its HPMS submission as a **62-layer linear-referenced service** — the same shape
as Louisiana's, and readable by the same generic adapter with no new Swift:

| Layer | What | Events |
|---|---|---|
| 6 | `AllRoadsNetwork` (the route layer) | 132,581 routes, 126,320 of them non-ADOT |
| 33 | `OwnershipAndMaintenance` | **241,126** |
| 21 | `FunctionalSystem` | 263,393 |
| 61 | `YearLastImprovement` | 14,901 |
| 60 | `YearLastConstruction` | 7,264 |
| 0 | `AADT` | 27,894 |

### `Ownership_Value` is the best-shaped ownership field found anywhere

218 values written as `PREFIX-Name (code)` — `PHX-Phoenix (4)`, `MMA-Maricopa County DOT (2)`,
`TUC-Tucson (4)`, `PNF-Prescott NF (64)`. **The code gives the kind and the text gives the body**,
so a card names the actual city statewide without a table of Arizona municipalities.

It also carries **21,600 segments marked private** and **10,213 belonging to gated owners'
associations** — a real answer to who built a road: nobody public did. Both need the *name*
rather than the code, because ADOT files `PRI` under HPMS 80 ("Other"), which decodes to nothing.
Three values are admissions and yield no owner: `TBD-To be determined after 2013`,
`UNK-Unknown (yet Fed FC)`, and `NBY-Not Built Yet - platted roads` (468 segments platted but
never constructed).

### The statewide table belongs *below* the county, not beside the state

Wired into the state slot it worked and was wrong. ADOT names an owner for **every** road in
Arizona, so on Lone Mountain Rd it beat MCDOT and the card lost the distinction between a road
the county accepted and one it merely maintains as a courtesy (`countyCourtesy`, 616 segments).

So a state profile now contributes in two places. Its hand-written sources lead — they exclude a
route namespace, disambiguate two routes 2 m apart, and read a project number out of free text,
and a state route must be claimed before a county source infers a municipal owner for a pin
inside city limits. Its statewide table trails the county tier as a fallback. That is what
`compiledFirst` means on a profile.

### The bug this exposed, which had been shipping

`ArcGISClient.query(layer:field:equals:)` restricted values to letters, digits, `-` and `_`.
ADOT publishes **fixed-width route ids**: `"10N GRANADA             AVE     "`. Stripping the
padding turned every Arizona event join into a query matching nothing, and it failed **silently**
— an empty result is indistinguishable from a road with no recorded owner. Spaces now survive;
quotes still do not, so a value cannot close its own literal.

Note also that layer 6 holds a parent route *and* its carriageways (`US-180`, `US-180 (1)`,
`US-180 (2)`, `US-180 nonCard`) while the event tables key only on the carriageways — ADOT's
"every road stored twice" problem from §3.1, in a second service. It affects only the ~576
routes with a `RouteCardinality`, which are exactly the state routes ATIS already answers first.

### Texas, finished

Irving is the last Texas city with anything to add: 9,133 centrelines, **no construction date of
any kind**, and an `OWNERSHIP` field naming CITY (5,934), STATE (2,182), **PRIVATE (820)** and
slivers owned by DFW airport, Dallas and Coppell. TxDOT files every one of those as a bare
municipal code, so naming the body — and the 820 private streets — is the whole contribution.

---

## 18. North Carolina — the richest state inventory, and the only documented one

```
https://gis11.services.ncdot.gov/arcgis/rest/services/NCDOT_RoadCharacteristicsQtr/MapServer/0
```

**1,201,628 segments**, and the best-populated state source found anywhere:

| Field | Populated |
|---|---|
| `StreetName` | 1,166,779 (97%) |
| `SrfcType` | 918,124 (76%) |
| `AddDate` | 596,386 |
| **`ImprvDate`** + `ImprvType` | **473,065 (39%)** |
| `OwnerName` | 297,234, naming **1,049 distinct bodies** |

### NCDOT publishes its domains, which nothing else does

Every other agency in this document had its vocabulary *derived* — TxDOT's `ADMIN` by
cross-tabbing against `HSYS`, Dallas's `rehab_type` by inspection, ADOT's by parsing a string.
NCDOT ships coded-value domains on `ImprvType`, `OwnerType`, `FuncClass`, `SrfcType` and
`RouteClass`, so `CodeTables.ncdotImprovement` quotes the agency instead of guessing at it:
`NR` New Construction, `RE` Reconstruction, `MA`/`MI` Major/Minor Widening, `NL` Relocation,
`BR` Bridge Replacement, `IP` Initial Paving, `RS` Resurfacing, `SI` Surface Improvement.
`OwnerType` is plain HPMS and `FuncClass` plain FHWA, both already shipped.

### Ownership needs two rules, because it lives in three fields

`OwnerType` gives the level and `OwnerName` the body — `4` and `Charlotte` — so a card can say
**Charlotte** rather than "city or municipal highway agency". But NCDOT declares *its own*
maintenance somewhere else entirely: `RouteMaintCode = System`, on **607,062 segments that name
no owner at all**. Reading that blank as "state" would be inferring from silence where the agency
has published an answer, so `FieldMapping.ownershipRules` tries the named body first and the
maintenance declaration second. The correlation is near-total: of 607,156 `System` segments,
607,062 name no other owner.

### No sentinel, for once

`ImprvDate` is **1,872 distinct dates with the largest at 4.0%** and no future values. After San
Antonio (96% placeholder), Laredo (50.9%) and Arlington (two bulk-loaded dates), this is the
first date field in the survey that needs no filter — and the test says so, so that a filter
appearing later has to be a deliberate edit.

### The national HPMS is not public

`geo.dot.gov` carries `HPMS_Public_Release` and `ARNOLD_Inventory_HPMS`, which would give
ownership for every road in the country in one profile. Both return **`499 Token Required`**.
That settles the architecture: there is no national ownership layer to be had without a key, and
state-by-state is not a stopgap.

Also probed and rejected this round: **Florida** (`RCI_Layers` exposes a name and almost nothing
else through its MapServer), **Washington** (`HpmsSegments`, 3,176 rows), **California** (a
`CHhighway` folder with one service), and **New York and Michigan** (servers unreachable).
Ohio's server is unreachable too, but its ArcGIS Online copy is not — see §19.

---

## 19. Ohio — the same state, a different service, and no dates to get wrong

§10.3 rejected Ohio, correctly, on the evidence then available: 58,127 rows whose `LAST_CONST`
was the 1900-01-01 placeholder, on a host that 404s. ODOT's ArcGIS Online copy is a different
dataset entirely:

```
https://services1.arcgis.com/1AlElnGrgBM62OSj/arcgis/rest/services/Road_Inventory/FeatureServer/0
```

**402,947 segments**, a jurisdiction on every one, and a real street name on 379,684 (94%). Also
functional class, lanes, and `ADT_TOTAL_` on 124,285.

**It publishes no construction date, and that is the safe part.** `PERP_YEAR` is `2022` on
**100%** of rows — the dataset's own vintage, not the road's — and `RESURFACE_` covers 9,228
segments across only 2020-2022. Neither is mapped, and the profile does not even *request*
`PERP_YEAR`, so there is no plausible-looking year sitting in the response to be mistaken for a
build date later.

### The name is in three fields

`STREET_PRE` + `STREET_NAM` + `STREET_SUF` — `S`, `MAIN`, `ST`. Every other profile takes the
first field that yields a value, which here gives **"MAIN"**. `FieldMapping.nameParts` joins them.

### `JURISDICTI` is one letter, and undocumented

Derived the way TxDOT's `ADMIN` was, by cross-tabbing against `ROUTE_TYPE`, which is
self-describing. The partition is exact:

| Letter | `ROUTE_TYPE` | Segments | Owner |
|---|---|---|---|
| `M` | 100% `MR` | 139,995 | Municipal |
| `T` | 100% `TR` | 111,882 | **Township trustees** |
| `S` | `SR`, `US`, `IR`, `RA`, `NR` | 58,220 | ODOT |
| `C` | 100% `CR` | 50,087 | County engineer |
| `F` | `FR`, `NP`, `DD` | 607 | Federal |
| `P` | `MR`, `TR`, `BK` | 42,156 | **unmapped** |

Ohio still has **townships** as a road authority — 111,882 segments — which most states do not,
and which HPMS code 3 exists for. `P` is left unmapped: its rows carry blank street names and are
99.9% functional class 7, which *reads as* private, and reading-as is not evidence. Those rows
have no name to contribute either way.

`SURFACE_TY` is single undocumented letters (`G` on 64%) and is deliberately not read.

---

## 20. Massachusetts and Denver — and what the big metros actually publish

Fifteen more major metros probed. Most publish street centrelines with no ownership and no dates,
which TIGER already covers. Two were worth shipping, and one of them turned out to be a state.

### Massachusetts — the second agency that documents itself

```
https://services1.arcgis.com/hGdibHYSPO59RG1h/arcgis/rest/services/MassDOTRoads_gdb/FeatureServer/0
```

Found by accident: Boston's `City_of_Boston_Managed_Streets` is 10,861 segments carrying
MassDOT's schema, which meant a statewide version existed. It does — **409,586 segments** — and
MassGIS publishes **thirty coded-value domains**, making it the second self-documenting agency in
this survey after NCDOT (§18).

`JURISDICTN` is the most complete ownership list found anywhere: eighteen values separating the
Department of Conservation and Recreation, Massport, four branches of the military, the Army
Corps and the Bureau of Indian Affairs. Two carry real weight:

- **`H` — Private.**
- **`0` — "Unaccepted by city or town", on 120,329 segments, a fifth of the state.** Somebody may
  plough it, but no public body has taken it on. That is the same distinction Maricopa draws with
  `countyCourtesy`, and it maps to `notPubliclyMaintained`: the developer who laid the road is
  the real answer to who built it.

`SURFACE_TP` is a bare integer with a published domain — `6` on 185,085 segments is a bituminous
concrete road. No construction dates are published.

**A field name that does not exist fails the whole query.** Boston's clipped copy truncates
`STREETNAME` to `STREET_NAM`; carrying that name over to the statewide profile made the service
answer `400 Cannot perform query` and the source failed outright rather than merely missing a
name. A test now checks the requested fields against the layer.

### Denver — a year the city last touched the street

```
https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/Denver_Pavement_Treatments/FeatureServer/428
```

Note **layer 428**, not 0. 29,728 segments, and both `Jurisdiction` and `Maintenance` name the
body — `Maintenance` more finely, separating Denver International Airport, Denver Parks and
Recreation and Fairmount Cemetery from the city proper, and marking 1,054 segments private. It is
read first for that reason.

`YR_LSTWK` is on **24,458 of 29,728 (82%)** across a smooth spread with no dominant value, so no
sentinel filter. `CCD_Treatment` is mostly plain English — `Mill and Overlay`, `Chip Seal`,
`Reconstruct` — which is why the Dallas classifier was generalised to
`CodeTables.workKind(pavementTreatment:)` and now serves both cities: the same words decide the
same way. `HIPR` (3,984 segments) is expanded to "hot in-place recycling".

### Probed and not shipped

| Metro | What it publishes |
|---|---|
| New York | `Centerline_view`, 122,269 segments — but `RWJURISDICTION` is **96% null**, so names only, which TIGER already gives |
| Seattle | 1,020 services, none a centreline with ownership or dates |
| Los Angeles | cool-pavement studies, no citywide inventory |
| Chicago | search resolves to CMAP, the regional planning agency, not the city |
| Boston | superseded by the statewide MassDOT layer above |

---

## 21. Virginia — where the locality named on the road does not own it

```
https://services.arcgis.com/p5v98VHDX9Atv3l7/arcgis/rest/services/LRS_Route_Master/FeatureServer/0
```

196,896 routes with `RTE_JURIS_PROPER_NM` naming 218 localities — Fairfax County, City of Virginia
Beach, Loudoun County. Reading that as ownership is the obvious move and it is **wrong**.

Virginia is arranged unlike any other state: **VDOT maintains the secondary system in every
locality except Arlington and Henrico.** So the locality name says where a route *is*, not who
keeps it, and taking it at face value hands 64,076 VDOT-maintained secondary roads to the
counties they happen to run through.

`RTE_TYPE_NM` is the real signal, and the data confirms the arrangement independently:

| Locality | Street Route | Secondary Route |
|---|---|---|
| Arlington County | 676 | **7** |
| Henrico County | 6,420 | **4** |
| Fairfax County | 5,841 | **9,422** |

The two localities that famously maintain their own roads have almost no secondary routes; a
VDOT-maintained county is majority secondary. So `Secondary Route`, `State Route`, `U.S. Route`,
`Interstate`, `Frontage Road` and `Urban Road` are VDOT, and `Street Route` belongs to its
locality.

This needed **no new Swift**. Two `ownershipRules`: the first maps every VDOT route type through
`namedAgency` and maps `Street Route` to an empty string so it declines; the second then reads
`RTE_JURIS_PROPER_NM`, where `owner(named:)` already resolves "Fairfax County" to a county and
"City of Virginia Beach" to a municipality.

`RTE_COMMON_NM` is a label, not a name — `Patrick Henry DR (NP - Arlington County)` on a street,
`SC-682E (Accomack County)` on a secondary route — so it is not read at all. Named streets come
from the joined street parts; a secondary route with no street name falls through to TIGER, which
gives a real one (*Anns Cove Rd*). No dates are published.

---

## 22. Batch one — the six largest remaining states

California, Florida, New York, Illinois, Georgia and Michigan, worked with
`scripts/statescan.py`. Two shipped. The four rejections are as useful as the wins, and two of
them were **near misses that looked like hits**.

### Michigan — the largest network yet

```
https://services2.arcgis.com/67lKNkQ2TO1I3lhR/arcgis/rest/services/MDOTRHCenterline2025_Districts/FeatureServer/0
```

**709,036 segments.** `Ownership` is the plain HPMS code space — 1 state (62,038), 2 county
(282,098), 4 municipal (236,976) — so the table shipped for Louisiana reads it unchanged, and the
127,663 rows carrying none claim nothing. The name is in four fields (`FEDIRP`, `FENAME`,
`FETYPE`, `FEDIRS`). `NFC` is FHWA, and its `0` on 116,126 rows falls outside the published 1–7
and yields no class rather than a wrong one. No construction date: `AADTYear` dates the count.

### New York — the third agency that documents itself

```
https://gis.dot.ny.gov/hostingny/rest/services/Geocortex/HDSV/MapServer/11
```

The server this repo recorded as unreachable answers on a different path. **Layer 11,
"Maintenance Jurisdiction", is 394,175 segments** — layers 1–4 are Federal Aid Eligible subsets
of 16,677 to 54,221 each and are the wrong choice.

NYSDOT publishes **fourteen coded-value domains**, after NCDOT (§18) and MassDOT (§20).
`OWNING_JURIS` is the HPMS code space under New York's own labels — `01 NYSDOT`, `03 Town`,
`31 NYS Thruway`, `26 Private` — so the shipped table reads it, and `98`/`99` "to be
investigated" fall outside it and claim nothing.

`OWNED_BY_MUNI_NAME` names the body, and attaching it is safe because of a **total correlation**:
it is null on *all* 76,742 NYSDOT rows and present on *all* 109,379 city rows, so a state highway
can never be renamed after a borough. A Bronx street reads **"Bronx"**.

`FUNC_CLASS` is deliberately not mapped. New York uses the two-digit extended scheme this document
has warned about since §10 — values run to 19 — and the FHWA 1–7 table would decode them wrongly.

### The four rejections

| State | What was found |
|---|---|
| **Georgia** | The layer named `HPMS` carries `OWNERSHIP` *and* `YEAR_LAST_IMPROVEMENT` on 171,572 segments and looked like the best find of the batch. Its extent is lon −86.8 to −84.0, and it returns **zero features in Atlanta**: it is a Chattanooga tri-state regional extract, not Georgia. |
| **Illinois** | The org a search returns holds a layer named `HPMS_state_roads_NV` whose extent is **Nevada**. Four in-state Illinois pins returned nothing. |
| **California** | Caltrans' `CHhighway/All_Roads` is 723,692 segments carrying **only a route id** and LRS dates — no name, no owner. `RH/RestAPI` adds postmiles and odometers, not attributes. |
| **Florida** | `RCI_Layers` exposes a name and little else through its MapServer; `State_Roads_TDA` is 2,198 features with no relevant fields at all. |

**Georgia and Illinois are why every hit now gets its extent checked before it is believed.** Both
would have shipped one state's roads under another state's name.

---

## 23. Batch two — six states, none of which publishes ownership

New Jersey, Washington, Tennessee, Indiana, Maryland and Missouri. **Not one publishes a
statewide layer naming who is responsible for a road**, which is the bar. One city came out of it,
and it was not in any of the six.

| State | What it does publish |
|---|---|
| New Jersey | `NJDOT_Roadway_Network`, 106,232 segments — a straight-line-diagram label and LRS validity dates (`YEAR_ACTIVE`, `YEAR_RETIRED`), no owner. The one layer carrying `JURISDICTN` returns nothing in Newark. |
| Tennessee | `Pavement_Roughness`, 154,237 segments with a county and a collection year. No owner, no name. |
| Indiana | **29 `LRSE_*` event services** — AADT, access control, functional class, lanes, median, shoulders, speed, surface — and **not one for ownership**. |
| Maryland | iMap's twenty folders are thematic and include no transportation or roads service at all. |
| Missouri | `MO_MoDOT_Roads_Arcs` carries a name and a designation. No ownership. |
| Washington | Nothing beyond the 3,176-row `HpmsSegments` already rejected in §18. |

### Louisville, found while searching for Indiana

```
https://services1.arcgis.com/79kfd2K6fskCAkyg/arcgis/rest/services/Metro_Road_Paving_Condition_2025_PCI_View_layer/FeatureServer/0
```

The Indiana scan returned this because its organisation is unlabelled. Its owner names give it
away — `JEFFERSONTOWN`, `SHIVELY`, `MIDDLETOWN`, `OUT OF JEFFERSON` are Jefferson County
**Kentucky** suburbs — and it returns **zero features at Indianapolis against 171 in downtown
Louisville**.

That is the **third cross-state false positive in two batches**, after Georgia's Chattanooga
extract and Illinois' Nevada layer. Every candidate is now queried at a pin known to be inside
its claimed state before anything is written.

Taken on its merits it is a good city source: 24,327 streets with `OWNER_NAME` (`METRO` on
24,174, plus 111 private and a handful of independent suburbs), condition, class and cross
streets. `OUT OF JEFFERSON` maps to an empty rename so it declines rather than naming a body it
does not know. `FiscalYear` is null on 23,173 of 24,327, so almost nothing carries a paving date
and the undated-work rule drops the rest.

---

## 24. Batch three — Kentucky, and the difference between acceptance and ownership

Wisconsin, Colorado, Minnesota, South Carolina, Alabama and Kentucky. One shipped.

### Kentucky

```
https://services2.arcgis.com/CcI36Pduqd0OR4W9/arcgis/rest/services/KYTC_-_State_Road_Assets_Flattened/FeatureServer/0
```

**480,065 segments, every one named.** The field to ignore is the one that sounds right:
`Ownership_Status` reads `ACCEPTED` on **479,967 of 480,065** — it records whether the state took
a road into its system, not who keeps it, and mapping it would have told every driver in Kentucky
the same thing.

`Route_Type` is the ownership signal: `KY` 382,962, `US` 65,034, `I` 15,660 and `PKWY` 5,640 are
all the Transportation Cabinet; `CITY` 7,869 is municipal, `CNTY` 2,463 county, `PRIV` 21 private,
`FED` 13 federal. Two rules, because a city road needs its body named from `City_Name`
("Lexington") while a state route must not be renamed after the city it passes through.

`CNTY` declines deliberately: `County_Name` is `Hopkins`, without the word County, so
`owner(named:)` would read it as a municipality — and 2,463 rows of 480,065 is not worth a table
to get right.

**A rule's rename map is not a whitelist.** With only `CITY` listed in the second rule, `CNTY`
fell through, was classified raw, and produced a municipality called **"Cnty"**. Both rules now
list every route type, and a test asserts they do.

### The five rejections

| State | What it publishes |
|---|---|
| Colorado | `PavementCondition_forConditionDashboard_AllYears`, 437,195 segments — route id, surface type, functional class id and a survey year. No name, no owner. (Denver's own layer is shipped, §20.) |
| Alabama | `HPMS_Year2017_F_System_Data`, 185,150 segments carrying a record year and a route id and nothing else. |
| Wisconsin, Minnesota, South Carolina | No statewide roadway service found on ArcGIS Online or the DOT's own server. |

Wisconsin, Alabama and Tennessee searches all returned the **Chattanooga tri-state HPMS extract**
already rejected in §22. It is the single most common false positive in this survey.

---

## 25. Batch four — Iowa, Portland, and four searches that returned other states

Oregon, Oklahoma, Connecticut, Utah, Iowa and Nevada. Two shipped, neither of them where the
search was aimed in the way expected.

### Iowa — ownership statewide, naming left to TIGER

```
https://services.arcgis.com/8lRhdTsQyJpO52F1/arcgis/rest/services/Road_Network_View/FeatureServer/0
```

**359,066 segments**, and `OWNER_CODE` is the plain HPMS space — 4 municipal (152,954), 2 county
(138,861), 1 state (59,765) — so the shipped table reads it.

**It deliberately maps no name.** `COMMON_NAME_1` prefixes the owner onto the road:
`CITY OF DANA, ECKSTEIN STREET`. `SHORT_COMMON_NAME_1` drops the prefix and still trails a
direction: `S AVENUE, N`. TIGER gives *Eckstein St*, so Iowa contributes the owner and TIGER the
name — the same division of labour Texas uses on its on-system routes. `SURFACE_TYPE` is
undocumented numeric codes (65, 20, 31) and is not read.

### Portland — 33 owners and no rename table

```
https://services3.arcgis.com/q5Jezm9AgzqyE7Q6/arcgis/rest/services/TriMet_Road_Centerlines/FeatureServer/0
```

92,464 centrelines published by the transit agency for the metro. `ROADOWNER` names the body
outright — *City of Portland* 37,314, *Washington County* 8,314, *Oregon Department of
Transportation* 2,774 — and `owner(named:)` already reads every shape it uses: a trailing
"County" gives a county, "Department of Transportation" the state, a city name a municipality.
**No `ownerNames` entry was needed at all**, the first profile where that is true.

Keyed to Portland's place GEOID although the layer covers the whole metro. That under-uses it at
the edges and can never answer for a city it does not cover, which is the safer error. Oregon
publishes no statewide roadway service, so this is the state's only entry.

### Four searches, four other states

| Searched for | What came back |
|---|---|
| Oklahoma | `MA_DOT_Road_Inventory_2020` — **Massachusetts**, 627,388 segments |
| Nevada | `TxDOT_roadways` — **Texas** |
| Connecticut | the Tennessee `Pavement_Roughness` layer |
| Wisconsin, Alabama, Tennessee (§24) | the Chattanooga tri-state HPMS extract |

Oklahoma's own `Pavement_Change` layers carry a maintenance division and nothing else; Utah's
`HPMS_Report_GIS` is 24,720 segments with no ownership field. **Six cross-state false positives
in four batches** — the in-state pin check is now the single most useful step in the loop.

---

## 26. Batch five — New Mexico, and two fields that are constants

Arkansas, Mississippi, Kansas, New Mexico, Nebraska and Idaho. One shipped.

### New Mexico

```
https://services.arcgis.com/hOpd7wfnKm16p9D9/arcgis/rest/services/HPMS2026/FeatureServer/0
```

**2,898,383 rows**, which is not 2.9 million roads — it is the same roads split at every
attribute change, the shape an HPMS submission takes. Verified as New Mexico and not a national
layer: 9,274 features around Albuquerque and **zero** at Austin, Chicago and San Francisco.

`Ownership` is the plain HPMS space — 1 state (1,527,767), 4 municipal (361,599), 2 county
(145,528), 26 private (33,223), 50 tribal (9,469) — and the 804,586 rows carrying none claim
nothing. There is no name field at all, so TIGER names the road.

**The segmentation is the cost.** A 150 m envelope returns **1,840 features and about 350 KB**
even with `outFields` narrowed to three, the largest per-lookup payload of any profile shipped.
That is why nothing beyond ownership and traffic is requested, and a test asserts it.

### A field that is a constant is not a field

Two states failed on the same shape this batch, and Kentucky nearly did in §24:

- **Nebraska.** Omaha publishes 35,239 centrelines whose `MAINTBY` is the value `1` on **every
  single row**. A field with one value carries no information, however promising its name.
- **Arkansas.** `On_System_Roadway_Inventory` is 20,428 segments — the state system only, with no
  ownership field.

Mississippi, Kansas and Idaho publish no statewide roadway service. The Kansas search returned a
`Street_Centerlines` layer that answers nothing in Wichita, and the Idaho search returned the
Chattanooga extract for the fourth time.
