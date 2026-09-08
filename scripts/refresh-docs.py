#!/usr/bin/env python3
"""Regenerate the state lists that repeat the catalog.

README.md and website/index.html both name the states shipped, and both fell behind before
anyone noticed. This rewrites them from Sources/RoadCore/Resources/coverage.json, and prints
the profile counts for the COVERAGE.md header, which is still written by hand because it
carries a sentence about each entry that only a person can write.
"""
import json, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Sources/RoadCore/Resources/coverage.json"

# Two-digit FIPS to name. Kept here rather than imported because this is a build-time script,
# not app code; Jurisdiction.stateNames is the app's copy.
STATES = {
    "01": "Alabama", "02": "Alaska", "04": "Arizona", "05": "Arkansas", "06": "California",
    "08": "Colorado", "09": "Connecticut", "10": "Delaware", "11": "District of Columbia",
    "12": "Florida", "13": "Georgia", "15": "Hawaii", "16": "Idaho", "17": "Illinois",
    "18": "Indiana", "19": "Iowa", "20": "Kansas", "21": "Kentucky", "22": "Louisiana",
    "23": "Maine", "24": "Maryland", "25": "Massachusetts", "26": "Michigan",
    "27": "Minnesota", "28": "Mississippi", "29": "Missouri", "30": "Montana",
    "31": "Nebraska", "32": "Nevada", "33": "New Hampshire", "34": "New Jersey",
    "35": "New Mexico", "36": "New York", "37": "North Carolina", "38": "North Dakota",
    "39": "Ohio", "40": "Oklahoma", "41": "Oregon", "42": "Pennsylvania",
    "44": "Rhode Island", "45": "South Carolina", "46": "South Dakota", "47": "Tennessee",
    "48": "Texas", "49": "Utah", "50": "Vermont", "51": "Virginia", "53": "Washington",
    "54": "West Virginia", "55": "Wisconsin", "56": "Wyoming",
}

def main():
    catalog = json.loads(CATALOG.read_text())
    names = sorted(STATES[fips] for fips in catalog["states"])
    shipped = (len(catalog["states"]) + len(catalog["counties"])
               + len(catalog.get("places") or {}))

    readme = ROOT / "README.md"
    text = readme.read_text()
    row = ("| State | " + ", ".join(names) +
           " | Name and who is responsible, statewide. Construction or improvement dates where "
           "the state publishes them — Texas carries a full project register back to 1970 with "
           "cost, North Carolina 473,000 improvement dates |")
    text = re.sub(r"^\| State \|.*$", row, text, count=1, flags=re.M)
    readme.write_text(text)

    site = ROOT / "website/index.html"
    html = site.read_text()
    # The state-tier card is the one under the "State records" heading; the other two cards
    # carry their own `where` line and must not be touched.
    html = re.sub(r'(<h3>State records</h3>\s*<p class="where">)[^<]*(</p>)',
                  lambda m: m.group(1) + " · ".join(names) + m.group(2), html, count=1)
    site.write_text(html)

    print(f"{len(names)} states, {shipped} profiles total")
    print("COVERAGE.md header should read:")
    print(f"  **{shipped} profiles shipped · {len(catalog['states'])} states · "
          f"{len(catalog['counties'])} counties · {len(catalog.get('places') or {})} cities**")

if __name__ == "__main__":
    main()
