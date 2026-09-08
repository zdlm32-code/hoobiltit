"""Upload screenshots to an App Store version localization.

Apple's flow is three steps per image: reserve an appScreenshot (which returns a
set of upload operations), PUT the bytes to each, then PATCH uploaded=true. The
checksum Apple wants is the MD5 of the whole file.
"""
import hashlib, os, sys, urllib.request
sys.path.insert(0, "scripts"); import asc

VERLOC = "000ca161-0592-43a2-95f3-d789f87039f9"
# 6.9" images (1320x2868) go in the 6.7" slot: the API exposes no APP_IPHONE_69 and
# Apple accepts either size there.
SETS = {"APP_IPHONE_67": "store/screenshots/iphone69"}

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

jwt = asc.token(*asc.credentials())
for display, folder in SETS.items():
    print(f"{display}:")
    set_id = existing_set(jwt, display)
    if not set_id: continue
    for f in sorted(os.listdir(folder)):
        if f.endswith(".png"):
            upload(jwt, set_id, os.path.join(folder, f))
