#!/usr/bin/env bash
# Re-run the endpoint reconnaissance behind docs/ENDPOINTS.md.
# Every source in v1 is anonymous; no keys, no setup. Usage: ./scripts/probe.sh [pin]
set -uo pipefail

RIT="https://gis.maricopa.gov/dot/rest/services/Maintenance/RoadInformationTool/MapServer"
BOS="https://gis.maricopa.gov/arcgis/rest/services/BOS/Transportation/MapServer"
ATIS="https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/ATIS_prod_gdb/FeatureServer"
PROP="https://gis.maricopa.gov/dot/rest/services/Property/RightOfWay/MapServer"
NBI="https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/NTAD_National_Bridge_Inventory/FeatureServer/0"
FUND="https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/mapped_route_export_July7/FeatureServer/0"

# National tier — works anywhere in the US, no key (docs/ENDPOINTS.md §7)
TIGER="https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb"
NHS="https://geo.dot.gov/server/rest/services/National_Highway_System/MapServer/0"
# State tier (§10)
PENNDOT="https://gis.penndot.pa.gov/gis/rest/services/opendata/roadwaysegments/MapServer/0"
LADOTD="https://gis.dotd.la.gov/road/rest/services/Roads_and_Highways_OpenData/MapServer"
TXINV="https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_Roadway_Inventory/FeatureServer/0"
TXRDS="https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_Roadways/FeatureServer/0"

# Named test pins from docs/ENDPOINTS.md §8 (bash 3.2 has no associative arrays)
PIN_NAMES="lonemountain goodyear i10 suncity williams mc85 mcdowell"
# Pins outside Arizona, for the national and state tiers.
NATIONAL_PINS="philadelphia phillylocal batonrouge perkins houston boston sanjacinto i35tx txcounty txtoll"
pin_coords() {
  case "$1" in
    lonemountain) echo "-112.528617 33.767648" ;;  # unincorporated, full county hit; on the centreline, not 104 m off it
    goodyear)     echo "-112.4118 33.4386" ;;  # city: layer 7 hits, layer 2 empty
    i10)          echo "-112.3756 33.4602" ;;  # ADOT state route
    suncity)      echo "-112.2749 33.5988" ;;  # subdivision + plat link
    williams)     echo "-112.317668 33.689441" ;; # county arterial + TIP project TT0248
    mc85)         echo "-112.4448 33.3939" ;;      # road name that genuinely ends in digits
    mcdowell)     echo "-111.667181 33.466228" ;;  # spot TIP project; linear record is on another street
    philadelphia) echo "-75.16558 39.95851" ;;     # PennDOT state-owned: VINE ST, YR_BUILT 1959
    phillylocal)  echo "-75.1652 39.9526" ;;       # same street, JURIS=5 stretch: YR_BUILT is 0
    batonrouge)   echo "-91.145970 30.419270" ;;   # BALIS DR: name+owner, deliberately no year
    perkins)      echo "-91.147830 30.418620" ;;   # PERKINS RD: the only 1971 row in that box
    houston)      echo "-95.3698 29.7604" ;;       # no profile: TIGER names it, NBI dates it
    boston)       echo "-71.0589 42.3601" ;;       # NHS ownership; TIGER's 60 m empty-box trap
    sanjacinto)   echo "-97.741957 30.263227" ;;   # TxDOT: city street with a state route 54.7 m away
    i35tx)        echo "-97.676922 30.490050" ;;   # TxDOT owns it; MAP_LBL is a shield label, TIGER names it
    txcounty)     echo "-95.667328 31.654532" ;;   # ADMIN=2, COUNTY ROAD 2108
    txtoll)       echo "-95.506920 29.564598" ;;   # ADMIN=6, Fort Bend Parkway
    *)            return 1 ;;
  esac
}

envelope() { python3 -c "print(f'{$1-$3},{$2-$3},{$1+$3},{$2+$3}')"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# $1=label $2=url  — prints feature count and the first feature's populated attributes
q() {
  curl -s -m 25 --retry 3 --retry-delay 1 --retry-all-errors \
       -H 'User-Agent: roadapp-probe' "$2" | python3 "$HERE/_fmt.py" "$1"
}

probe_pin() {
  local name=$1; read -r X Y <<<"$(pin_coords "$name")"
  local E; E=$(envelope "$X" "$Y" 0.0015)
  local ENVQ="geometry=$E&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&returnGeometry=false&f=json"
  echo "=== $name  ($X, $Y)"
  q "RIT/7  municipality"      "$RIT/7/query?$ENVQ"
  q "RIT/2  mcdot maintained"  "$RIT/2/query?$ENVQ"
  q "RIT/3  subdivision/plat"  "$RIT/3/query?$ENVQ"
  # Project lines sit off the centerline, so they get the wider corridor envelope (§2.3).
  local CORR; CORR=$(envelope "$X" "$Y" 0.004)
  local CORRQ="geometry=$CORR&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&returnGeometry=false&f=json"
  q "BOS/770 linear TIP"       "$BOS/770/query?$CORRQ"
  q "BOS/760 spot TIP"         "$BOS/760/query?$CORRQ"
  q "BOS/790 linear MIP"       "$BOS/790/query?$CORRQ"
  q "BOS/780 spot MIP"         "$BOS/780/query?$CORRQ"
  # ADOT is ArcGIS Online: point+distance works there, but envelope works everywhere.
  q "PROP/1 road declaration"  "$PROP/1/query?$ENVQ"
  q "PROP/0 row acquisition"   "$PROP/0/query?$ENVQ"
  q "ATIS/29 adot ownership"   "$ATIS/29/query?$ENVQ"
  q "ATIS/3  year last constr" "$ATIS/3/query?$ENVQ"
  q "FUND   programmed cost"   "$FUND/query?$ENVQ"
  # Structures sit further off the centerline than a street segment does (§7.1).
  q "NBI    bridges"           "$NBI/query?$CORRQ"
  echo
}

# The national and state tiers at one pin. Every service here is keyless.
probe_national() {
  local name=$1; read -r X Y <<<"$(pin_coords "$name")"
  local E; E=$(envelope "$X" "$Y" 0.0015)          # ~150 m, the app's own search radius
  local P; P=$(envelope "$X" "$Y" 0.00002)         # ~2 m, a point as an envelope
  local ENVQ="geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&returnGeometry=false&f=json"
  echo "=== $name  ($X, $Y)"
  q "TIGER/1  county+state"    "$TIGER/State_County/MapServer/1/query?geometry=$P&$ENVQ"
  q "TIGER/4  place"           "$TIGER/Places_CouSub_ConCity_SubMCD/MapServer/4/query?geometry=$P&$ENVQ"
  q "TIGER/8  local roads"     "$TIGER/Transportation/MapServer/8/query?geometry=$E&$ENVQ"
  q "NHS      ownership"       "$NHS/query?geometry=$E&$ENVQ"
  q "PennDOT  inventory"       "$PENNDOT/query?geometry=$E&$ENVQ"
  q "LA/49    roadways"        "$LADOTD/49/query?geometry=$E&$ENVQ"
  q "LA/91    ownership"       "$LADOTD/91/query?geometry=$E&$ENVQ"
  q "LA/69    last construct"  "$LADOTD/69/query?geometry=$E&$ENVQ"
  q "TxDOT    inventory"       "$TXINV/query?geometry=$E&$ENVQ"
  echo
}

# Guard for the trap LRSJoin exists to avoid: in this box Louisiana's construction table has
# exactly one row, and it belongs to Perkins Rd — not to the nearest street. If that stops
# being true the join is no longer being tested by real data.
check_measure_join() {
  read -r X Y <<<"$(pin_coords batonrouge)"
  local E; E=$(envelope "$X" "$Y" 0.0015)
  local ENVQ="geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&returnGeometry=false&f=json"
  echo "=== Louisiana event join (ENDPOINTS.md §10.2)"
  local rid
  rid=$(curl -s -m 25 "$LADOTD/69/query?geometry=$E&$ENVQ&outFields=RouteID,YearLastConst" \
        | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("err"); raise SystemExit
f=d.get("features",[])
print(f[0]["attributes"]["RouteID"] if len(f)==1 else ("none" if not f else "many"))')
  echo "  construction rows in the Balis Dr box -> ${rid:-?}"
  if [[ "$rid" == "033903558402991001" ]]; then
    echo "  OK: still Perkins Rd's route, not the nearest street's. The join is under test."
  else
    echo "  CHANGED: re-read ENDPOINTS.md §10.2 — the fixture no longer models the trap."
  fi
  echo
}

# PennDOT's ownership field. MAINT_RESPON_IND looks like HPMS-times-ten and is not; JURIS is
# the real one. If PennDOT ever republishes with HPMS codes, the decode inverts silently.
check_penndot_codes() {
  echo "=== PennDOT ownership codes (ENDPOINTS.md §10.1)"
  local juris
  juris=$(curl -s -m 40 "$PENNDOT/query?where=1%3D1&outFields=JURIS&returnDistinctValues=true&returnGeometry=false&f=json" \
          | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("err"); raise SystemExit
print(",".join(sorted({str(f["attributes"]["JURIS"]) for f in d.get("features",[])})))')
  echo "  distinct JURIS -> ${juris:-?}"
  if [[ "$juris" == "1,2,5,6" ]]; then
    echo "  OK: 1 PennDOT, 2 Turnpike, 5 local, 6 bridge commission. Not HPMS."
  else
    echo "  CHANGED: re-read ENDPOINTS.md §10.1 before trusting the PennDOT decode table."
  fi
  echo
}

# Regression guard for docs/ENDPOINTS.md §4: distance+units must still be the broken form
# on on-prem, and the envelope must still work. If this flips, the client can be simplified.
check_distance_quirk() {
  read -r X Y <<<"$(pin_coords lonemountain)"
  local base="$RIT/2/query?outFields=OnRoad&returnGeometry=false&f=json"
  local dn en
  dn=$(count "$base&geometry=$X,$Y&geometryType=esriGeometryPoint&inSR=4326&distance=100&units=esriSRUnit_Meter&spatialRel=esriSpatialRelIntersects")
  en=$(count "$base&geometry=$(envelope "$X" "$Y" 0.0015)&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects")
  echo "=== distance-vs-envelope quirk (on-prem, same point)"
  echo "  point+distance -> ${dn:-?} feature(s)   envelope -> ${en:-?} feature(s)"
  if [[ "$dn" == "err" || "$en" == "err" ]]; then
    echo "  INCONCLUSIVE: a request failed; re-run before drawing any conclusion."
  elif [[ "$dn" == "0" && "$en" != "0" ]]; then
    echo "  OK: quirk still present; keep using envelopes (ENDPOINTS.md §4)."
  else
    echo "  CHANGED: re-read ENDPOINTS.md §4 — the server behaviour moved."
  fi
  echo
}

# TxDOT's ownership decode is *derived*, not documented: the service publishes ADMIN: NO DOMAIN,
# and the meaning of each code was inferred from its HSYS cross-tab (ENDPOINTS.md §10.2b). That
# makes it the most fragile table shipped, so it gets the strictest guard. If TxDOT ever
# republishes ADMIN in HPMS codes, every Texas owner inverts silently.
check_txdot_codes() {
  echo "=== TxDOT ADMIN ownership codes (ENDPOINTS.md §10.2b)"
  local pairs
  pairs=$(curl -s -m 90 "$TXINV/query?where=1%3D1&groupByFieldsForStatistics=ADMIN,HSYS&outStatistics=%5B%7B%22statisticType%22%3A%22count%22%2C%22onStatisticField%22%3A%22OBJECTID%22%2C%22outStatisticFieldName%22%3A%22n%22%7D%5D&returnGeometry=false&f=json" \
          | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print("err"); raise SystemExit
if "error" in d: print("err"); raise SystemExit
g={}
for f in d.get("features",[]):
    a=f["attributes"]; g.setdefault(a["ADMIN"],set()).add(a["HSYS"])
# The three codes that carry 99.5% of the state, and the one family each must map to.
ok = g.get(2)=={"CR"} and g.get(4)=={"LS"} and "IH" in g.get(1,set()) and "CR" not in g.get(1,set())
print("ok" if ok else "changed", max(g) if g else 0)')
  echo "  ADMIN -> HSYS partition, highest code -> ${pairs:-?}"
  case "$pairs" in
    "ok 16") echo "  OK: 1 TxDOT, 2 county (CR only), 4 local (LS only); range still tops out at 16." ;;
    ok*)     echo "  CHANGED: the partition holds but the code range moved — re-read §10.2b." ;;
    err*)    echo "  INCONCLUSIVE: the request failed; re-run before drawing any conclusion." ;;
    *)       echo "  CHANGED: re-read ENDPOINTS.md §10.2b before trusting the TxDOT decode table." ;;
  esac
  echo
}

# Feature count for a query URL, or the string "err" if the request did not come back.
count() {
  curl -s -m 25 --retry 3 --retry-delay 1 --retry-all-errors "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("err"); raise SystemExit
print("err" if "error" in d else len(d.get("features", [])))'
}

is_national() { case " $NATIONAL_PINS " in *" $1 "*) return 0;; *) return 1;; esac; }

if [[ $# -gt 0 ]]; then
  pin_coords "$1" >/dev/null || {
    echo "unknown pin '$1'; try: $PIN_NAMES $NATIONAL_PINS" >&2; exit 2; }
  if is_national "$1"; then probe_national "$1"; else probe_pin "$1"; probe_national "$1"; fi
else
  for p in $PIN_NAMES; do probe_pin "$p"; done
  for p in $NATIONAL_PINS; do probe_national "$p"; done
  check_distance_quirk
  check_measure_join
  check_penndot_codes
  check_txdot_codes
fi
