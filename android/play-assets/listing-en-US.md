# Google Play listing (en-US), drafted 2026-10-20 from the Android build's actual behavior

## App name (30 max)
Vehicle Maintenance Log

## Short description (80 max)
Service schedules, reminders and recalls for every car, boat, bike and plane.

## Full description
Every vehicle, one logbook. Cars, trucks, motorcycles, boats, RVs, planes, ATVs and the mower: pick the kind and its maintenance schedule is built for you, with miles for the truck and engine hours for the boat.

It knows what's due
• Oil, tires, brakes, filters, fluids and inspections, with typical intervals you can edit
• Due dates estimated from how much you actually drive, not just the calendar
• Reminders a week ahead and on the day, plus one weekend note for anything overdue
• Track days, water crossings and dusty rides bring the right jobs due

Log it in seconds
• Maintenance, repairs, recall fixes, mods, events and fill-ups, each kept apart
• Date, reading, cost, shop or DIY, and notes
• Full history across every vehicle, by month

• Receipts, photos and documents kept with each visit or with the vehicle
• A second meter for generator hours, track hours or trail miles
• Put a boat or bike in storage for the season and reminders pause
• Import your history from Fuelly, Drivvo, Simply Auto or a spreadsheet
• Home screen widget with what's due next

Safety recalls
• Decode a VIN and list recalls from the U.S. NHTSA's public data
• Check what's still open on your VIN on NHTSA's own lookup
• A recall closes when the log shows the fix

Explore
• Price guides opened on your exact vehicle, plus the values you note over time
• Parts and tools for what's due, popular upgrades, owners clubs and forums
• Shops, mobile mechanics and detailers near you

Your data stays yours
• No account and no ads
• Your log stays on your phone
• Export every entry to a spreadsheet (CSV), free

Pro
Your first two vehicles are free forever, with unlimited logging, reminders, recalls and export. Pro adds every vehicle you own, a clean Service Record PDF for a buyer or a shop, and a breakdown of where the money goes, including your real cost per mile. Pro is available monthly or yearly with a one-week free trial for eligible new subscribers, or as a one-time purchase.

Schedules are general guidance for normal use. Your owner's manual and a qualified mechanic come first.

## Category and contact
- Category: Auto & Vehicles. Tags: maintenance, car care.
- Email: jackwallner@gmail.com. Website: https://jackwallner.github.io/keyring/
- Privacy policy: https://jackwallner.github.io/keyring/android-privacy.html (live after this branch merges)

## Data safety (from code, 2026-10-21)
- Data collected: Purchase history and an anonymous app user ID, sent to RevenueCat to confirm purchases
  (App functionality). Not shared for advertising, not sold.
- VIN, or year, make and model: sent to NHTSA's public API only when the user taps "Fill in from VIN" or opens
  Safety recalls. Processed ephemerally by a government API, not stored by the developer. Declare as
  "Vehicle info / Other" only if Play's form treats a user-initiated lookup as collection; it is not linked to
  an identity.
- Garage, entries, readings, values, attached photos and documents: stored on device only, excluded from backup.
  Not collected. Photos and files come through the system pickers (no media or storage permission).
- Per-VIN recall check: NHTSA's nhtsa.gov page loads in an in-app WebView with the VIN typed into its field;
  the user presses Search. The page's own cookies and reCAPTCHA run under NHTSA's policy; the app reads the
  result off the page and keeps it on the device. Same "user-initiated government lookup" answer as above.
- Encrypted in transit: yes (HTTPS). Deletion: in-app delete or uninstall; nothing is kept off device.
- No ads, no ad ID, no analytics SDK. Not a health, finance, government or news app.

## App access
- No login. Pro features unlock for review with the access code in Settings > App review access; the code's
  SHA-256 goes in `PLAY_REVIEW_CODE_SHA256` (Air only) and the plain code in the Play Console App access form.

## Content rating
- IARC: no violence, no user-generated content shared with others, no location sharing, in-app purchases yes.
  Expected: Everyone / PEGI 3.
