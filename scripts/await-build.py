"""Wait for a specific build to finish processing, then attach it to a beta group.

Usage: await-build.py <version>

Takes the version explicitly. An earlier cut grabbed builds[0] from an unsorted
list and declared success on whichever build happened to be there already —
which, right after an upload, is the *previous* one.
"""
import sys, time
sys.path.insert(0, "scripts")
import asc

APP_ID = "6809232030"
GROUP_ID = "8e8e706b-54cb-4f36-9566-e6a436b9857f"

if len(sys.argv) < 2:
    print("usage: await-build.py <version>", flush=True)
    raise SystemExit(2)
WANTED = sys.argv[1]
DEADLINE = time.time() + 45 * 60

while time.time() < DEADLINE:
    key_id, issuer, path = asc.credentials()
    jwt = asc.token(key_id, issuer, path)          # re-minted each pass; tokens expire
    status, body = asc.call(
        "GET", f"/builds?filter[app]={APP_ID}&filter[version]={WANTED}&limit=1", jwt)
    builds = body.get("data", [])
    if not builds:
        print(f"build {WANTED}: not yet visible in App Store Connect", flush=True)
    else:
        build = builds[0]
        state = build["attributes"].get("processingState")
        print(f"build {WANTED}: {state}", flush=True)
        if state == "VALID":
            status, body = asc.call(
                "POST", f"/betaGroups/{GROUP_ID}/relationships/builds", jwt,
                {"data": [{"type": "builds", "id": build["id"]}]})
            print(f"attach build {WANTED} to Internal group: {status}", flush=True)
            if status not in (200, 201, 204):
                print(body, flush=True)
                raise SystemExit(1)
            print("READY", flush=True)
            raise SystemExit(0)
        if state in ("INVALID", "FAILED"):
            print(f"build {WANTED} PROCESSING FAILED", flush=True)
            raise SystemExit(1)
    time.sleep(60)

print(f"TIMED OUT waiting for build {WANTED}", flush=True)
raise SystemExit(2)
