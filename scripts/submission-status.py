"""Audit App Store submission readiness for the current version.

Reports only what the API can see. App Privacy and Content Rights are web-UI only —
see store/SUBMISSION.md.
"""
import sys
sys.path.insert(0, "scripts"); import asc

APP = "6809232030"
jwt = asc.token(*asc.credentials())

s, b = asc.call("GET", f"/apps/{APP}/appStoreVersions?limit=1", jwt)
ver = b["data"][0]; VER = ver["id"]
s, b = asc.call("GET", f"/appStoreVersions/{VER}/appStoreVersionLocalizations", jwt)
VERLOC = b["data"][0]["id"]
s, b = asc.call("GET", f"/apps/{APP}/appInfos", jwt)
INFO = b["data"][0]["id"]
s, b = asc.call("GET", f"/appInfos/{INFO}/appInfoLocalizations", jwt)
INFOLOC = b["data"][0]["id"]

def get(p):
    return asc.call("GET", p, jwt)[1]

rows = []
def chk(label, ok, detail=""):
    rows.append(("PASS" if ok else "TODO", label, str(detail)[:52].replace("\n", " ")))

v = get(f"/appStoreVersions/{VER}")["data"]["attributes"]
chk("Copyright", v.get("copyright"), v.get("copyright") or "")
vl = get(f"/appStoreVersionLocalizations/{VERLOC}")["data"]["attributes"]
for f in ["description", "keywords", "promotionalText", "supportUrl"]:
    chk(f, vl.get(f), vl.get(f) or "")
il = get(f"/appInfoLocalizations/{INFOLOC}")["data"]["attributes"]
for f in ["name", "subtitle", "privacyPolicyUrl"]:
    chk(f, il.get(f), il.get(f) or "")
ai = get(f"/appInfos/{INFO}?include=primaryCategory,secondaryCategory")
chk("Categories", ai.get("included"), ", ".join(i["id"] for i in ai.get("included", [])))
chk("Age rating", ai["data"]["attributes"].get("appStoreAgeRating"),
    ai["data"]["attributes"].get("appStoreAgeRating") or "")
rd = get(f"/appStoreVersions/{VER}/appStoreReviewDetail").get("data")
chk("Review contact", rd, rd["attributes"]["contactEmail"] if rd else "")
bd = get(f"/appStoreVersions/{VER}/build").get("data")
chk("Build attached", bd, f"build {bd['attributes']['version']}" if bd else "none")
for st in get(f"/appStoreVersionLocalizations/{VERLOC}/appScreenshotSets").get("data", []):
    n = len(get(f"/appScreenshotSets/{st['id']}/appScreenshots").get("data", []))
    chk(f"Screenshots {st['attributes']['screenshotDisplayType']}", n, f"{n} image(s)")
chk("Pricing", get(f"/apps/{APP}/appPriceSchedule").get("data"), "set")

print(f"{'':5}{'ITEM':34}DETAIL")
for st, l, d in rows:
    print(f"{st:5}{l:34}{d}")
print(f"\nversion {v.get('versionString')}: {v.get('appStoreState')}")
print("web-UI only, not visible here: App Privacy, Content Rights "
      "(see store/SUBMISSION.md)")
