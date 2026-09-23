"""Upload screenshots to an App Store version localization.

Apple's flow is three steps per image: reserve an appScreenshot (which returns a
set of upload operations), PUT the bytes to each, then PATCH uploaded=true. The
checksum Apple wants is the MD5 of the whole file.

Uploads the captioned images (scripts/caption-screenshots.py) to the version that is
still editable. A new version starts with a copy of the previous version's screenshots,
so each set is emptied first — otherwise the new ones land after the old.
"""
import hashlib, os, sys, urllib.request
sys.path.insert(0, "scripts"); import asc

APP = "6809232030"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}
# 6.9" images (1320x2868) go in the 6.7" slot: the API exposes no APP_IPHONE_69 and
# Apple accepts either size there. 13" iPad images (2064x2752) likewise go in 12.9".
SETS = {"APP_IPHONE_67": "store/screenshots/captioned/iphone69",
        "APP_IPAD_PRO_3GEN_129": "store/screenshots/captioned/ipad13"}
VERLOC = None  # resolved at run time from the editable version

def existing_set(jwt, display):
    s, b = asc.call("GET", f"/appStoreVersionLocalizations/{VERLOC}/appScreenshotSets", jwt)
    for d in b.get("data", []):
        if d["attributes"]["screenshotDisplayType"] == display:
            return d["id"]
    s, b = asc.call("POST", "/appScreenshotSets", jwt, {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": display},
        "relationships": {"appStoreVersionLocalization": {"data": {
            "type": "appStoreVersionLocalizations", "id": VERLOC}}}}})
    if s not in (200, 201):
        print(f"   ERR create set {display} [{s}] {b}"); return None
    return b["data"]["id"]

def upload(jwt, set_id, path):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    s, b = asc.call("POST", "/appScreenshots", jwt, {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(data), "fileName": name},
        "relationships": {"appScreenshotSet": {"data": {
            "type": "appScreenshotSets", "id": set_id}}}}})
    if s not in (200, 201):
        print(f"   ERR reserve {name} [{s}] {str(b)[:200]}"); return False
    sid = b["data"]["id"]
    for op in b["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=180).read()
    s, b = asc.call("PATCH", f"/appScreenshots/{sid}", jwt, {"data": {
        "type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True,
                       "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    ok = s in (200, 201)
    print(f"   {'OK ' if ok else 'ERR'} {name} [{s}]")
    if not ok: print("      ", str(b)[:250])
    return ok

def empty(jwt, set_id):
    s, b = asc.call("GET", f"/appScreenshotSets/{set_id}/appScreenshots", jwt)
    for shot in b.get("data", []):
        s, _ = asc.call("DELETE", f"/appScreenshots/{shot['id']}", jwt)
        print(f"   removed {shot['attributes']['fileName']} [{s}]")

jwt = asc.token(*asc.credentials())
s, b = asc.call("GET", f"/apps/{APP}/appStoreVersions?limit=10", jwt)
version = next((v for v in b["data"] if v["attributes"]["appStoreState"] in EDITABLE), None)
if not version:
    sys.exit("No editable version — create the next version in App Store Connect first.")
s, b = asc.call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations", jwt)
VERLOC = next(l["id"] for l in b["data"] if l["attributes"]["locale"] == "en-US")
print(f"version {version['attributes']['versionString']}")
for display, folder in SETS.items():
    print(f"{display}:")
    set_id = existing_set(jwt, display)
    if not set_id: continue
    empty(jwt, set_id)
    for f in sorted(os.listdir(folder)):
        if f.endswith(".png"):
            upload(jwt, set_id, os.path.join(folder, f))
