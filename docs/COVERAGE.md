# Coverage checklist

Every jurisdiction probed for this app, whether it shipped and why not when it did not. The
shipped half mirrors `Sources/RoadCore/Resources/coverage.json`; the rejections are the useful
part, because each one records what was actually checked so it is not re-probed from scratch.

Full findings for each are in [`ENDPOINTS.md`](ENDPOINTS.md); the section number is given.

**28 profiles shipped · 13 states · 2 counties · 13 cities**

---

## States

| ✅ | State | Source | What it gives | § |
|---|---|---|---|---|
| ✅ | **Arizona** | ADOT ATIS + statewide HPMS | Every road named and owned statewide, incl. 21,600 private and 10,213 gated; construction dates on state routes | 3, 17 |
| ✅ | **Texas** | TxDOT inventory + DCIS register | Owner, class, traffic; **73,306 projects 1970–2050 with cost**, contractor on live work | 10.2b, 10.2c |
| ✅ | **North Carolina** | NCDOT road characteristics | 1.2M segments, names on 97%, **473,065 improvement dates**, 1,049 named owners. Only agency publishing domains | 18 |
| ✅ | **Massachusetts** | MassDOT road inventory | 409,586 segments, 18 documented owners incl. private and **120,329 unaccepted**. Second agency publishing domains | 20 |
| ✅ | **New Mexico** | HPMS event table | HPMS ownership statewide incl. 33,223 private and 9,469 tribal. TIGER names. Heaviest payload shipped | 26 |
| ✅ | **Iowa** | Iowa DOT road network | 359,066 segments with HPMS ownership; TIGER names them, because Iowa's name field prefixes the owner. No dates | 25 |
| ✅ | **Kentucky** | KYTC road assets | 480,065 segments, every one named; ownership from route type, city roads named after their city. No dates | 24 |
| ✅ | **Ohio** | ODOT road inventory | 402,947 segments, jurisdiction on all, names on 94%, **townships** as an authority. No dates | 19 |
| ✅ | **Pennsylvania** | PennDOT roadway segments | Name, owner, `YR_BUILT` and `YR_RESURF` on state-owned roads | 10.1 |
| ✅ | **New York** | NYSDOT maintenance jurisdiction | 394,175 segments, names on 90%, ownership named down to the borough. Third agency publishing domains. No dates | 22 |
| ✅ | **Michigan** | MDOT road centreline | 709,036 segments — the largest network shipped. HPMS ownership, class, traffic. No dates | 22 |
| ✅ | **Virginia** | VDOT route master | 196,896 routes; ownership from route *type*, because VDOT maintains the secondary system in every locality but two. No dates | 21 |
| ✅ | **Louisiana** | LA DOTD LRS | Name, HPMS owner, construction and improvement years on control sections | 10.2 |

### Probed, not shipped

| State | Why not | § |
|---|---|---|
| Florida | `RCI_Layers` exposes a name and little else; `State_Roads_TDA` is 2,198 features with no attributes | 18, 22 |
| California | Caltrans' `All_Roads` is 723,692 segments carrying only a route id; the Roads & Highways API adds postmiles, not ownership | 22 |
| Illinois | The org a search returns holds no Illinois road layer — four in-state pins returned nothing | 22 |
| Georgia | The layer named `HPMS` is a Chattanooga tri-state regional extract: **zero features in Atlanta** | 22 |
| Washington | `HpmsSegments` is 3,176 rows; no statewide roadway service found | 18, 23 |
| New Jersey | `NJDOT_Roadway_Network` (106,232) carries a route label and LRS validity dates, no owner; the one layer with `JURISDICTN` returns nothing in Newark | 23 |
| Tennessee | `Pavement_Roughness` (154,237) carries a county and a survey year, no owner or name | 23 |
| Indiana | 29 `LRSE_*` event services and **not one for ownership** | 23 |
| Maryland | iMap publishes no transportation or roads service at all | 23 |
| Missouri | `MO_MoDOT_Roads_Arcs` carries a name and designation, no ownership | 23 |
| California | Caltrans server has a `CHhighway` folder with one service | 18 |
| Wisconsin, Minnesota, South Carolina | No statewide roadway service found | 24 |
| Oklahoma, Connecticut, Utah, Nevada | No statewide roadway service naming an owner | 25 |
| Arkansas | `On_System_Roadway_Inventory` is 20,428 state-system segments with no ownership field | 26 |
| Mississippi, Kansas, Idaho | No statewide roadway service found | 26 |
| Nebraska | Omaha publishes 35,239 centrelines but `MAINTBY` is the value `1` on every one | 26 |
| Oregon | No statewide service; Portland's metro centreline is shipped instead | 25 |
| Colorado | `PavementCondition` is 437,195 segments carrying a route id, surface and survey year — no name, no owner | 24 |
| Alabama | `HPMS_Year2017_F_System_Data` is 185,150 segments carrying only a record year and route id | 24 |
| **National (FHWA)** | `HPMS_Public_Release` and `ARNOLD_Inventory_HPMS` return **`499 Token Required`** — settles that there is no national ownership layer without a key | 18 |

---

## Counties

| ✅ | County | Source | What it gives | § |
|---|---|---|---|---|
| ✅ | **Maricopa, AZ** | MCDOT + assessor + recorder | The deepest coverage anywhere: owner, project, plat, declaration, pavement, parcels | 1–2 |
| ✅ | **Cameron, TX** | County road inventory | 3,119 unincorporated roads: name, surface, lanes. No dates | 15 |

### Probed, not shipped

| County | Why not | § |
|---|---|---|
| Hidalgo, TX | No public road or street service found | 15 |
| Starr, TX | No road service | 15 |
| Pima, AZ | No public road service; covered by ADOT statewide instead | 17 |
| County GIS generally | Auto-discovery fails — 1 of 12 counties had a usable endpoint | 11 |

---

## Cities

| ✅ | City | Source | What it gives | § |
|---|---|---|---|---|
| ✅ | **Dallas, TX** | Pavement condition | **27,588 rehab years, no sentinel**, work type, condition, block range | 14 |
| ✅ | **San Antonio, TX** | Pavement inventory | 98,986 segments, named owner incl. **11,017 private**. Dates 96% placeholder, filtered | 14 |
| ✅ | **Arlington, TX** | Pavement inventory | **Installed *and* replaced dates**; `Built`/`Reconstructed` are null decoys | 16 |
| ✅ | **Laredo, TX** | Pavement condition | A real `YEAR_BUILT` on ~5,200 streets; 1980 placeholder on 50.9%, filtered | 16 |
| ✅ | **Denver, CO** | Pavement treatments | `YR_LSTWK` on 82%, no sentinel; maintenance names the airport, parks, a cemetery | 20 |
| ✅ | **Portland, OR** | TriMet metro centreline | 92,464 streets; owner names 33 bodies outright and needs no rename table. Oregon's only entry. No dates | 25 |
| ✅ | **Louisville, KY** | Metro pavement condition | 24,327 streets: owner incl. 111 private, condition, class, cross streets. Paving year on ~1,150 only | 23 |
| ✅ | **Edinburg, TX** | Capital projects | **Contractor, actual cost, completion date** on 139 projects | 15 |
| ✅ | **Pharr, TX** | Street inventory | Owner incl. 697 private, pavement rating, 2015–18 repaving | 15 |
| ✅ | **Irving, TX** | Road centreline | Owner incl. 820 private, DFW airport slivers. No dates | 17 |
| ✅ | **Weslaco, TX** | Street centreline | Name and responsible jurisdiction. No dates | 15 |
| ✅ | **Brownsville, TX** | Road centreline | Name only — the thinnest profile shipped | 15 |
| ✅ | **McAllen, TX** | Annexation history | 346 tracts 1927–2023. Not a construction date and never shown as one | 15 |

### Probed, not shipped

| City | Why not | § |
|---|---|---|
| **Harlingen, TX** | **Template data** — rows named "PROJECT 1", one shared end date, centroids in Edinburg | 15 |
| New York, NY | 122,269 centrelines but `RWJURISDICTION` is **96% null** — names only, which TIGER gives | 20 |
| Houston, TX | 235,765 centrelines, no dates; project layers hold 17 and 6 features | 14 |
| Austin, TX | Street centreline carries only GIS record metadata | 14 |
| Los Angeles, CA | Cool-pavement studies, no citywide inventory | 20 |
| Chicago, IL | Search resolves to CMAP, the regional agency, not the city | 20 |
| Seattle, WA | 1,020 services, none a centreline with ownership or dates | 20 |
| Boston, MA | Superseded — its layer is MassDOT's schema, and the statewide version shipped | 20 |
| Fort Worth, TX | 624 polygons with only a document-update date | 16 |
| Lubbock, TX | `CIP` holds 2 rows; `COL_Streets` 969 with no dates | 16 |
| Phoenix, Tucson, Mesa, Chandler, Gilbert, Scottsdale, Tempe, AZ | None publishes a usable street service; all named by ADOT statewide instead | 17 |
| Corpus Christi, Plano, Garland, Frisco, El Paso, TX | No city street or pavement service found | 16 |
| Mission, San Juan, San Benito, Rio Grande City, TX | No service found | 15 |

---

## Where to look next

1. **Virginia's pavement-conditions layer** (`Pavement_Conditions_2023_All_Systems`, 101,080
   rows) has an `EFF_YEAR` that has not been checked — it may or may not be a survey year.
2. **Cities inside covered states** add *dates*, which the statewide layers mostly lack —
   Charlotte, Raleigh, Columbus, Cleveland, Boston.
3. **Counties** remain the weakest tier: two shipped against 3,143 in the country, and §11
   established that auto-discovery does not work.
