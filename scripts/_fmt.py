"""Format one ArcGIS query response for probe.sh. Reads JSON on stdin, label as argv[1]."""
import json, sys

label = sys.argv[1] if len(sys.argv) > 1 else "?"
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    # Distinguish "the layer has nothing here" from "the request did not come back".
    detail = raw.strip()[:80] or "empty response"
    print(f"  {label:34s} NO ANSWER ({detail})"); raise SystemExit

if "error" in d:
    print(f"  {label:34s} ERROR {d['error'].get('message')}"); raise SystemExit

fs = d.get("features", [])
print(f"  {label:34s} {len(fs)} feature(s)")
if fs:
    attrs = {k: v for k, v in fs[0]["attributes"].items() if v not in (None, "", " ")}
    print("      " + json.dumps(attrs)[:300])
