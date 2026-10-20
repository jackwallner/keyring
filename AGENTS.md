# Vehicle Maintenance Log Project Guide

Vehicle Maintenance Log (code name Keyring, renamed 2026-10-17). A shared service log for every vehicle a family owns (cars, trucks, motorcycles, boats, aircraft, RVs, ATVs, mowers). XcodeGen project/scheme: `Keyring`, sim lease owner `keyring`. User-facing copy says "Vehicle Maintenance Log" (home screen "Maintenance Log", paid tier "Pro"); bundle IDs, the CloudKit container, product IDs and type names keep `keyring` because changing them orphans data and the ASC record.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency), iOS 17+
- Core Data + `NSPersistentCloudKitContainer`, two stores (private + shared) for garage sharing via `CKShare`
- RevenueCat, entitlement `pro`, offering `default`
- Vision (receipt OCR), VisionKit (VIN / odometer / invite scanning), PDFKit-free PDF rendering via UIGraphicsPDFRenderer
- WidgetKit (upcoming jobs)

## Identifiers
- App `com.jackwallner.keyring`, widget `com.jackwallner.keyring.widget`
- App Group `group.com.jackwallner.keyring`, iCloud `iCloud.com.jackwallner.keyring`
- ASC app `6823808045`. RevenueCat project `proj634d6667`
- Products: `com.jackwallner.keyring.monthly` ($1.99, 1-week trial), `.yearly` ($14.99, 1-week trial), `.lifetime` ($29.99)
- Free tier: 2 active vehicles, unlimited logging, reminders, recalls, sharing, CSV. Pro: unlimited vehicles, Service Record PDF, receipt and pump-photo auto-fill, insights. Fill-ups, odometer photo reading and photo fill for typed fields are free. Limit lives in `ProFeature.freeVehicleLimit`.

## Architecture
- `Shared/Models`: `KeyringModel` (code-built Core Data model: Garage, Vehicle, MaintenanceTask, ServiceEntry, MeterReading, Valuation, Attachment), `VehicleKind` (kinds, powertrains, meters)
- `Shared/Catalog`: maintenance schedules per kind/powertrain, makes, clubs, upgrades
- `Shared/Services`: `GarageStore` (all reads/writes), `DueEngine` (pure due math), `ReminderScheduler`, `SharingService` + `ShareInvite`, `NHTSAClient` (VIN decode, recalls), `ReceiptReader`, `StoreService`, `DemoSeed` (DEBUG)
- `Shared/Export`: `ServiceRecordPDF`, `RecordBuilder`, CSV, cost insights
- `Keyring/Views`: Garage (key-tag cards), VehicleDetail, LogService, Schedule, History, Explore (value, gear, upgrades, clubs, service nearby, recalls, insights), Family, AddVehicleFlow, Paywall, Onboarding, Settings

## Rules that hold everywhere
- Third-party values (KBB, Edmunds, J.D. Power, Aircraft Bluebook) are deep links only. Never show one as the app's own number.
- Amazon links open in Safari, never an in-app webview or the PDF. `AmazonLinks.associateTag` is empty; the disclosure only shows once a tag is set.
- `StoreService` never configures the `appl_` key on the simulator.
- Before a release: `xcodebuild test -scheme KeyringUITests` walks every main screen and taps the value, club, parts, recall and settings links (expects Safari to open); `scripts/check-links.py` fetches every outside URL. Bot-walled sites (Edmunds, eBay, J.D. Power, nhtsa.gov) need a real browser check.
- Debug launch args: `-SeedDemo`, `-DemoPro`, `-EmptyLog`, `-ScreenshotRoute vehicle|explore|record|log|fuel|fuelcard|build|pace|recalls|family|add|history|settings`, `-RecordZoom <factor>` (record preview zoomed to the top of the page), `-PaywallSnapshot monthly|yearly|lifetime`.

## Deep notes (load on demand)
| File | Covers | Read when |
|---|---|---|
| `.claude/rules/cloudkit.md` | schema tool, sharing, public DB, Production deploy | touching Persistence, sharing, the model |
| `.claude/rules/release.md` | screenshot sets (iPhone, Duo), ASC upload, submission draft | screenshots, ASC, release |

## App-specific notes
- Rating ask: `ReviewPrompter` calls `requestReview()` after a logged service from the 2nd launch, 30-day cooldown, no gate.
- Support/privacy/terms pages: `docs/` on GitHub Pages (`jackwallner.github.io/keyring`), mirrored to `jackwallner.com/ios/vehicle-maintenance-log/` (old `/ios/keyring/` redirects).
- Recalls: NHTSA's per-VIN repair status is behind reCAPTCHA, so `RecallMatcher` closes a recall from the log instead (a logged fix, or its NHTSA or maker code in an entry's notes or a saved receipt's OCR text).

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, ratings ask, gotchas):
the global agent rules + the `ios-dev` skill.
