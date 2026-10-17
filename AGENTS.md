# Keyring Project Guide

Keyring: Car Maintenance Log. A shared service log for every vehicle a family owns (cars, trucks, motorcycles, boats, aircraft, RVs, ATVs, mowers). XcodeGen project/scheme: `Keyring`, sim lease owner `keyring`.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency), iOS 17+
- Core Data + `NSPersistentCloudKitContainer`, two stores (private + shared) for garage sharing via `CKShare`
- CloudKit public database for owner photos (`OwnerPhoto`, `PhotoReport`)
- RevenueCat, entitlement `pro`, offering `default`
- Vision (receipt OCR), VisionKit (VIN / odometer / invite scanning), PDFKit-free PDF rendering via UIGraphicsPDFRenderer
- WidgetKit (upcoming jobs)

## Identifiers
- App `com.jackwallner.keyring`, widget `com.jackwallner.keyring.widget`
- App Group `group.com.jackwallner.keyring`, iCloud `iCloud.com.jackwallner.keyring`
- ASC app `6823808045`. RevenueCat project `proj634d6667`
- Products: `com.jackwallner.keyring.monthly` ($1.99, 1-week trial), `.yearly` ($14.99, 1-week trial), `.lifetime` ($29.99)
- Free tier: 2 active vehicles, unlimited logging, reminders, recalls, sharing, CSV. Pro: unlimited vehicles, Service Record PDF, receipt auto-fill, insights. Limit lives in `ProFeature.freeVehicleLimit`.

## Architecture
- `Shared/Models`: `KeyringModel` (code-built Core Data model: Garage, Vehicle, MaintenanceTask, ServiceEntry, MeterReading, Valuation, Attachment), `VehicleKind` (kinds, powertrains, meters)
- `Shared/Catalog`: maintenance schedules per kind/powertrain, makes, clubs, upgrades
- `Shared/Services`: `GarageStore` (all reads/writes), `DueEngine` (pure due math), `ReminderScheduler`, `SharingService` + `ShareInvite`, `NHTSAClient` (VIN decode, recalls), `CommunityPhotos`, `ReceiptReader`, `StoreService`, `DemoSeed` (DEBUG)
- `Shared/Export`: `ServiceRecordPDF`, `RecordBuilder`, CSV, cost insights
- `Keyring/Views`: Garage (key-tag cards), VehicleDetail, LogService, Schedule, History, Explore (value, gear, upgrades, clubs, recalls, gallery, insights), Family, AddVehicleFlow, Paywall, Onboarding, Settings

## Rules that hold everywhere
- Third-party values (KBB, Edmunds, J.D. Power, Aircraft Bluebook) are deep links only. Never show one as Keyring's own number.
- Amazon links open in Safari, never an in-app webview or the PDF. `AmazonLinks.associateTag` is empty; the disclosure only shows once a tag is set.
- Community photos need terms consent, report, block and 24-hour review (App Review 1.2). Keep all four.
- `StoreService` never configures the `appl_` key on the simulator.
- Debug launch args: `-SeedDemo`, `-DemoPro`, `-EmptyLog`, `-ScreenshotRoute vehicle|explore|record|log|family|add|history|settings`, `-PaywallSnapshot monthly|yearly|lifetime`.

## Deep notes (load on demand)
| File | Covers | Read when |
|---|---|---|
| `.claude/rules/cloudkit.md` | schema tool, sharing, public DB, Production deploy | touching Persistence, sharing, community photos, the model |

## App-specific notes
- Rating ask: `ReviewPrompter` calls `requestReview()` after a logged service from the 2nd launch, 30-day cooldown, no gate.
- Support/privacy/terms pages: `docs/` on GitHub Pages (`jackwallner.github.io/keyring`).

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, ratings ask, gotchas):
the global agent rules + the `ios-dev` skill.
