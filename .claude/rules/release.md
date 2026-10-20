---
paths:
  - "fastlane/**"
  - "scripts/testflight.sh"
  - "project.yml"
---
# Release and App Store screenshots

## Screenshots
- Two sets in `fastlane/screenshots/en-US/`: iPhone 6.9 inch (1320x2868, `01-*.png`) and iPhone Duo outer
  display (1398x2034, `duo_01-*.png`). The uploader picks the ASC display type from the pixel size.
- Manifests: `~/ios/appstore-screenshots/configs/keyring.json` (slot 1, iPhone 17 Pro) and `keyring-duo.json`
  (`store_slot` 11, iPhone Duo, `screenshot_display` "LCD", the outer screen; "LCD-1" is the folded inner panel and
  is blank). Capture with `./bin/shotflow capture <manifest> --output <dir>`, inspect every raw PNG, copy them into
  `samples/keyring/capture-proof[-duo]/`, then `./bin/shotflow all <manifest> --output <dir>`.
- Screenshot routes: `-ScreenshotRoute pace|recalls|record|build|family|history` plus `-RecordZoom 1.12` for a
  readable Service Record. `-SeedDemo` leads the garage with a truck, a motorcycle and a boat.
- Upload: `ASC_APP_VERSION=1.0 fastlane ios upload_screenshots` (wraps `asc-sync-screenshots`; never deliver's
  `overwrite_screenshots`, which duplicated sets elsewhere in the fleet).
- ASC refuses screenshot deletes while the version is an item in a review submission draft (409 "Can't Delete
  Screenshot while Ready For Review"). Remove the version's `reviewSubmissionItem` from the draft, sync, then
  POST it back; the IAP items stay in the draft throughout. Done this way for 1.0 on 2026-10-19.

## Submission
- `~/ios/release/release.py check --app 6823808045 --version <v>` is the readiness gate. For 1.0 the only flag is
  2.1(b): the first IAPs ride with the version, which is expected.
- Privacy labels and the physical-device screen recording for review notes need Jack's ASC web session.
