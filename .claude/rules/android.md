---
paths:
  - "android/**"
  - "scripts/export-android-catalog.py"
  - "docs/android-*.html"
---
# Android port

Native Kotlin/Compose port in `android/`, started 2026-10-20 on jmbp (fleet run
`shift-android-keyring-1-1792531430`). Built from the Quit Zyn (`nicfree`) build
files, not a template.

## Identity
- Package and namespace `com.jackwallner.keyring` (permanent once uploaded). Launcher label "Maintenance Log";
  listing name "Vehicle Maintenance Log". versionCode 1, versionName 1.0, minSdk 26, target/compile 36.
- RevenueCat: entitlement `pro` (any active entitlement unlocks, like iOS), offering `default` (falls back to
  current). Products keep the iOS IDs: `com.jackwallner.keyring.monthly` and `.yearly` (Play subscriptions,
  base plans `monthly`/`yearly`, 7-day free-trial offer for new customers) and `.lifetime` (in-app product).
  US prices stay $1.99 / $14.99 / $29.99. Debug builds read `REVENUECAT_TEST_KEY`, release `REVENUECAT_PLAY_KEY`
  (must start `goog_`), reviewer unlock `PLAY_REVIEW_CODE_SHA256`, all from ignored `android/local.properties`.
- Free tier: 2 active vehicles (`ProFeature.FREE_VEHICLE_LIMIT`), retired ones don't count. Pro: unlimited
  vehicles, Service Record PDF, insights. Logging, fill-ups, reminders, recalls and CSV stay free.

## Build and test (jmbp or jmbp2, never the Air)
- From the Air: `fm-gradle :app:testDebugUnitTest` in `android/`. On jmbp or jmbp2 itself:
  `JAVA_HOME=~/jdks/temurin-17/Contents/Home ./gradlew :app:testDebugUnitTest`.
- Connected: lease an idle `agent-emu-1`/`agent-emu-2` (check `adb devices` and qemu processes first), boot
  `emulator -avd agent-emu-1 -port 5584 -no-window -no-audio -no-boot-anim -no-metrics -no-snapshot-save`, then
  `ANDROID_SERIAL=emulator-5584 ./gradlew :app:connectedDebugAndroidTest` (on that machine, or `fm-gradle` from the Air). The AVDs render in software on the
  4-core Intel jmbp: after a cold boot SystemUI, the launcher and Digital Wellbeing ANR for several minutes; wait
  for the guest load to drop before tests or captures. Kill the emulator with `adb -s emulator-5584 emu kill`.
- Debug launch extras (debug source set only; release/QA ignore them): `seedDemo`, `demoPro`, `emptyLog`,
  `skipOnboarding`, `previewStore` (US price ladder, no store), `dark`, `uiTest`,
  `route vehicle|log|fuel|recalls|insights|task|value|gear|upgrades|clubs|service|trip|documents|storage|retire|import|add|history|settings|paywall`
  (`import` preloads `DemoSeed.SAMPLE_CSV`), `focus <ProFeature>`.
- jmbp2 (8 GB): pass `-Dorg.gradle.jvmargs=-Xmx2560m -Pkotlin.compiler.execution.strategy=in-process` so Gradle,
  Kotlin and the 2 GB AVD fit together; the first boot ANRs SystemUI for about 10 minutes.

## Catalog parity
- `MaintenanceCatalog.kt` is a mechanical conversion of `Shared/Catalog/MaintenanceCatalog.swift`. After any Swift
  catalog change run `python3 scripts/export-android-catalog.py` (writes
  `android/app/src/test/resources/catalog_literals_swift.json`) and port the change; `CatalogParityTest` fails
  until every computed Kotlin item matches its Swift literal and the literal count matches.
- jmbp's Swift is 5.7 (CommandLineTools), too old to compile the Swift 6 catalog, so the literals are extracted
  from source instead of exported by running Swift.

## Explore catalogs
- `catalog/Clubs.kt` and `catalog/Upgrades.kt` are mechanical conversions of `Shared/Catalog/Clubs.swift` and
  `Upgrades.swift`. After editing either Swift file run `python3 scripts/export-android-explore.py` (writes
  `android/app/src/test/resources/explore_literals_swift.json`) and port the change; `ImportAndExploreTest`
  fails until every club and upgrade list matches. `catalog/Explore.kt` holds `AmazonLinks`, `ValueSource` and
  `ServiceFinder`, hand-ported; their iOS tests are ported in the same test class.
- `data/ServiceImport.kt` is a line-for-line port of `Shared/Export/ServiceImport.swift` (same header names,
  date-column voting with java.time strict formatters, two-digit years within the last 80 years). Fuel grade is
  not stored on Android entries, so imports drop it; partial fills are kept.

## Intentionally different from iOS (platform gaps, decisions pending)
- CloudKit sync and family sharing (`CKShare`): no Android equivalent. The log is one JSON file in app storage
  (`files/garage.json`, excluded from backup). Cross-platform sharing needs a backend decision (Supabase or
  similar); not guessed. Settings says sharing and iPhone sync aren't on Android.
- Receipt, pump, odometer and VIN scanning (Vision/VisionKit): not ported. The Android paywall does not claim
  receipt reading. ML Kit would add a Google SDK and a Data safety change; decision pending.
- Ported 2026-10-21 (run `shift-android-keyring-parity-1-1792561214`): photos, receipts and documents (files in
  `files/attachments`, picked with the system photo picker and `OpenMultipleDocuments`, no storage permission),
  vehicle photo, second meters (generator hours, whichever-first UTV miles), storage with a return reminder,
  sold/retired with handover, valuations and value links, clubs, upgrades, parts and tools, service nearby,
  trip check, import (vehicle Records, Settings), the per-VIN NHTSA check (WebView on nhtsa.gov, JS bridge
  `KeyringRecalls`, results in prefs `vinRecallChecks.<vehicleId>`), and a Glance widget (`UpcomingWidget`,
  snapshot JSON in prefs `widgetSnapshot`, written on every log change; stored vehicles left out).
- Platform differences in that work: service-nearby map searches use Google's universal Maps link
  (`google.com/maps/search/?api=1&query=`) instead of Apple Maps; the widget shows a tint swatch instead of the
  kind's SF Symbol (Glance needs drawable resources); "Scan a paper" for documents and the receipt/pump/odometer
  scanners stay out with the ML Kit decision above. Not ported yet: parts and measurements on entries
  (`EntryDetails`), the Build list, odometer changes/mileage status (`VehicleProfile`), facts editor and
  vehicle-section ordering; the import column fixer covers only the main table, like iOS.
- Rating ask: Play In-App Review after a logged service from the 2nd launch, 30-day cooldown, no question first.
- Privacy and terms link to `docs/android-privacy.html` and `docs/android-terms.html` (live once merged and
  Pages deploys).

## Play state
- 2026-10-21 (jmbp2 run `shift-android-keyring-parity-1-1792561214`): parity features above, JVM and connected
  counts in that run's `REPORT.md`. Still not in Play Console; release steps unchanged from the line below.
- 2026-10-20 (jmbp run): port verified, 51 JVM + 7 connected tests, lint clean, debug and QA APKs. Not created in
  Play Console; no upload key, RevenueCat Play app or Play products yet. Remaining steps are in
  `~/fleet-evidence/shift-android-keyring-1-1792531430/REPORT.md` (release preparation section).
