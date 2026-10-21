# Google Play console notes (en-US), drafted 2026-10-20 from the Android build's actual behavior

Listing copy lives in `../metadata/android/en-US/` (title, short and full description).

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
