"""Push store/listing.md to App Store Connect.

    python3 scripts/push-listing.py            # show what would change
    python3 scripts/push-listing.py --apply    # write it

Name, subtitle, description and keywords can only change on a version that is still
editable (PREPARE_FOR_SUBMISSION and friends), so they go to that version and are skipped
with a note when none exists — create the next version in App Store Connect first.
Promotional text can change at any time, so it goes to the editable version if there is
one and otherwise straight to the live one.
"""
import re
import sys
sys.path.insert(0, "scripts"); import asc

APP = "6809232030"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}
LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170,
          "description": 4000, "keywords": 100, "whatsNew": 4000}
apply = "--apply" in sys.argv

md = open("store/listing.md").read()
def section(title):
    m = re.search(rf"^## {re.escape(title)}\n(.*?)(?=^## |\Z)", md, re.S | re.M)
    return m.group(1).strip()
def field(label):
    return re.search(rf"^\*\*{label}\*\* (.+)$", md, re.M).group(1).strip()

want_info = {"name": field("Name"), "subtitle": field("Subtitle")}
want_ver = {"description": section("Description"), "keywords": section("Keywords"),
            "promotionalText": section("Promotional text")}
# The first version has no "What's New"; every update needs one.
if "## What's New" in md:
    want_ver["whatsNew"] = section("What's New")
for k, v in {**want_info, **want_ver}.items():
    if len(v) > LIMITS[k]:
        sys.exit(f"{k} is {len(v)} characters, limit {LIMITS[k]}")

jwt = asc.token(*asc.credentials())
def get(p):
    s, b = asc.call("GET", p, jwt)
    if s != 200:
        sys.exit(f"GET {p} -> {s} {b}")
    return b

versions = get(f"/apps/{APP}/appStoreVersions?limit=10")["data"]
editable = next((v for v in versions if v["attributes"]["appStoreState"] in EDITABLE), None)
live = next((v for v in versions if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)

def patch(kind, obj_id, current, wanted, label):
    changes = {k: v for k, v in wanted.items() if (current.get(k) or "") != v}
    if not changes:
        print(f"{label}: up to date")
        return
    for k, v in changes.items():
        print(f"{label}: {k} ({len(current.get(k) or '')} -> {len(v)} chars)")
    if apply:
        s, b = asc.call("PATCH", f"/{kind}/{obj_id}", jwt,
                        {"data": {"type": kind, "id": obj_id, "attributes": changes}})
        print(f"  PATCH -> {s}" + ("" if s == 200 else f" {b}"))

def version_loc(version):
    locs = get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    return next(l for l in locs if l["attributes"]["locale"] == "en-US")

if editable:
    tag = f"version {editable['attributes']['versionString']}"
    loc = version_loc(editable)
    patch("appStoreVersionLocalizations", loc["id"], loc["attributes"], want_ver, tag)
    infos = get(f"/apps/{APP}/appInfos")["data"]
    info = next(i for i in infos if i["attributes"].get("appStoreState") in EDITABLE
                or i["attributes"].get("state") in {"PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW"})
    il = next(l for l in get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
              if l["attributes"]["locale"] == "en-US")
    patch("appInfoLocalizations", il["id"], il["attributes"], want_info, "app info")
else:
    print("No editable version: name, subtitle, description and keywords skipped.")
    if live:
        loc = version_loc(live)
        patch("appStoreVersionLocalizations", loc["id"], loc["attributes"],
              {"promotionalText": want_ver["promotionalText"]},
              f"live version {live['attributes']['versionString']}")

if not apply:
    print("\nDry run. Re-run with --apply to write.")
