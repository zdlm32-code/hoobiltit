#!/usr/bin/env python3
"""Find a state's road inventory, if it publishes one.

The reconnaissance behind docs/COVERAGE.md, automated. Given a state and a few search
phrases it finds candidate ArcGIS organisations, keeps polyline layers big enough to be a
statewide network, and reports the ones carrying an ownership- or date-shaped field.

    ./scripts/statescan.py Georgia "GDOT Georgia roads" "Georgia HPMS"

What it does NOT do is decide. A hit is a lead: the extent still has to be checked (a
Missouri search once returned Georgia's HPMS, because both sit in a shared regional org),
the codes still have to be derived, and a date field still has to be grouped to see whether
it is real or a placeholder. See the trap checklist in docs/COVERAGE.md.
"""
import json, urllib.request, urllib.parse, collections, re, sys
import concurrent.futures as cf

def get(url, timeout=8):
    return json.load(urllib.request.urlopen(url, timeout=timeout))

# Service names worth opening. Deliberately narrow: an org can hold thousands of layers and
# every one opened costs two requests.
SERVICE = re.compile(r'HPMS|ROAD_?INVENT|ROADWAY|ROAD_?CHAR|CENTERLINE|LRS_?ROUTE|PAVEMENT'
                     r'|ROAD_?NETWORK|STATE_?ROAD', re.I)
# Layers that are about something beside the road itself.
SKIP = re.compile(r'SIGN|LIGHT|CLOSURE|EVENT|BIKE|TRAIL|CRASH|RAIL|BRIDGE|TRANSIT|SIDEWALK', re.I)
OWNER = re.compile(r'OWNER|JURIS|MAINT|ADMIN|RESPONS|CUSTOD', re.I)
DATED = re.compile(r'YEAR|_YR|BUILT|CONST|RESURF|IMPROV|INSTALL|REHAB|LAST_?WORK', re.I)
# Below this a layer is a district map or a sample, not a network.
MINIMUM_FEATURES = 20_000

def organisations(query, limit=2):
    """The ArcGIS Online orgs whose items match a phrase, most-viewed first."""
    url = "https://www.arcgis.com/sharing/rest/search?" + urllib.parse.urlencode(
        {'q': query, 'f': 'json', 'num': 15, 'sortField': 'numViews', 'sortOrder': 'desc'})
    try:
        found = get(url, 12)
    except Exception:
        return []
    counted = collections.Counter()
    for item in found.get('results', []):
        url = item.get('url') or ''
        if 'arcgis.com' in url and '/rest/services' in url:
            parts = url.split('/')
            counted[(parts[2].split('.')[0], parts[3])] += 1
    return [org for org, _ in counted.most_common(limit)]

def inspect(job):
    """Open one service and report it if it looks like a road network."""
    host, org, name = job
    for kind in ("FeatureServer", "MapServer"):
        base = (f"https://{host}.arcgis.com/{org}/arcgis/rest/services/"
                f"{urllib.parse.quote(name)}/{kind}")
        try:
            layers = get(base + "?f=json").get('layers') or []
            if not layers:
                continue
            first = layers[0]['id']
            described = get(f"{base}/{first}?f=json")
            if described.get('geometryType') != 'esriGeometryPolyline':
                return None
            fields = [f['name'] for f in described.get('fields', [])]
            owners = [f for f in fields if OWNER.search(f)]
            dates = [f for f in fields if DATED.search(f)]
            if not owners and not dates:
                return None
            count = get(f"{base}/{first}/query?where=1%3D1&returnCountOnly=true&f=json",
                        15).get('count', 0)
            if not count or count < MINIMUM_FEATURES:
                return None
            return {'url': f"{base}/{first}", 'name': name, 'count': count,
                    'owners': owners[:4], 'dates': dates[:4], 'layers': len(layers)}
        except Exception:
            continue
    return None

def scan(state, queries):
    jobs, seen = [], set()
    for query in queries:
        for host, org in organisations(query):
            if (host, org) in seen:
                continue
            seen.add((host, org))
            try:
                services = [s['name'] for s in
                            get(f"https://{host}.arcgis.com/{org}/arcgis/rest/services?f=json",
                                15).get('services', [])]
            except Exception:
                continue
            # An org this large is a content aggregator, not an agency.
            if not services or len(services) > 2500:
                continue
            jobs += [(host, org, s) for s in services
                     if SERVICE.search(s) and not SKIP.search(s)][:25]
    hits = []
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        for hit in pool.map(inspect, jobs):
            if hit:
                hits.append(hit)
    # De-duplicate: an org often publishes the same layer under several names.
    best, by_count = [], {}
    for hit in sorted(hits, key=lambda h: -h['count']):
        if hit['count'] in by_count:
            continue
        by_count[hit['count']] = True
        best.append(hit)
    print(f"=== {state}: {len(best)} candidate(s)")
    for hit in best[:4]:
        print(f"   {hit['name'][:44]:<46} n={hit['count']:<9} layers={hit['layers']}")
        print(f"      owner-ish {hit['owners']}")
        print(f"      date-ish  {hit['dates']}")
        print(f"      {hit['url']}")
    if not best:
        print("   nothing — try the state DOT's own server before concluding")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    scan(sys.argv[1], sys.argv[2:])
