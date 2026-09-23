# App Store listing — hoobiltit

`scripts/push-listing.py` pushes the name, subtitle, promotional text, description and
keywords below to App Store Connect. Every paragraph of the description is one line, because
the App Store renders each line break literally — hard-wrapped text shows up ragged on a phone.

**Name** hoobiltit: US Road Information
**Subtitle** Who built this road?
**Primary category** Reference · **Secondary** Navigation
**Copyright** 2026 hoobiltit
**Support URL** https://hoobiltit.com/
**Marketing URL** https://hoobiltit.com/
**Privacy Policy URL** https://hoobiltit.com/privacy
**Terms of Use** https://hoobiltit.com/terms — also set as the custom EULA in App Store Connect

## What's New
hoobiltit may now ask you for a rating, but only after it has answered your roads on a few different days. It never asks while you're driving, and asks at most once per version. Thanks for the early support.

## Promotional text
Now covering 19 states — including New Hampshire's Class VI roads and Vermont's private roads, the ones nobody maintains.

## Description
Every road was built by someone. hoobiltit tells you who owns the road you're on, who maintains it, and — where the records exist — when it was built and which project did the work.

Drop a pin on a road and it names the agency responsible: a state department of transportation, a county, a city, a town or township, a tribal nation, or a private owner. Where the agency publishes more, you get more: construction and resurfacing years, traffic counts, pavement condition, and in Texas the project's cost and contractor.

WHAT IT ANSWERS
• Who owns and maintains this road
• When it was built, resurfaced or last improved
• Which project did the work — with cost and contractor in Texas
• Traffic counts, surface, pavement condition and road class
• Whether it is a public road at all — private roads and unmaintained rights of way are named as such

BUILT ON PUBLIC RECORDS
Answers come from the agencies themselves: state transportation departments, county road inventories, city pavement registers and federal datasets. Every fact on the card shows which agency it came from, so you can check it.

IT TELLS YOU WHEN IT DOESN'T KNOW
Agencies publish unevenly, so coverage is uneven too. Where a state records who owns a road but no dates, the card says exactly that. Where a record is ambiguous, the app reports nothing rather than guessing. It will not invent a fact to fill a gap.

DRIVE MODE
Names each road as you drive, on the Lock Screen and in the Dynamic Island.

SHARE WHAT IT FINDS
Send a card for any road, export the full report with every source it consulted, or have the app draft a public-records request to the agency for what it doesn't publish. The roads you drove export as a spreadsheet.

PRIVACY
No account, no login, no analytics — and no server of ours at all. Lookups go from your device straight to the public map services that answer them. Nothing is recorded about you and nothing is published anywhere.

COVERAGE
Road ownership statewide in 19 states: Arizona, Delaware, Georgia, Iowa, Kentucky, Louisiana, Massachusetts, Michigan, Montana, New Hampshire, New Mexico, New York, North Carolina, Ohio, Pennsylvania, South Dakota, Texas, Vermont and Virginia.

Construction or improvement years in Texas, North Carolina, Delaware, Louisiana, Pennsylvania (state roads) and Arizona (state routes), and from city records in Dallas, Arlington, Laredo, Denver and Louisville. The deepest detail anywhere is Maricopa County, Arizona: owner, project, plat and pavement.

Everywhere else in the US, the app names the street and, on the National Highway System, who owns it. Coverage grows with every release.

## Keywords
highway,DOT,ownership,jurisdiction,county,pavement,street,public works,GIS,plat,maintenance,bridge

## App Review notes
No account or login — the app opens straight to the map and needs no sign-in.

HOW TO TEST
1. Launch the app. Allow location, or skip it and drop a pin manually.
2. Drag the pin onto any road and tap it. The card names the road, the agency that owns
   it, and whatever else that agency publishes.
3. Coverage is strongest at these pins, if the simulator is not in a covered area:
   • Dallas, TX          32.7767, -96.7970   (owner, project history, cost)
   • Charlotte, NC       35.2271, -80.8431   (owner and improvement dates)
   • Concord, NH         43.2081, -71.5376   (town-maintained road)
   • Canterbury, NH      43.3494, -71.4999   (a Class VI road: "Not publicly maintained")
   • Phoenix area, AZ    33.6396, -112.1826  (deepest coverage — plats, parcels, projects)

ABOUT THE DATA
Every lookup goes from the device directly to a public government map service (state
DOT, county or city GIS). There is no backend of ours, no account system and no
analytics. Location is used to centre the map and, in Drive mode, to name roads as the
user drives; it is never sent anywhere except as query coordinates to those public
agency services.
