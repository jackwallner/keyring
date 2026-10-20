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
- `JAVA_HOME=~/jdks/temurin-17/Contents/Home ./gradlew :app:testDebugUnitTest` from `android/`.
- Connected: lease an idle `agent-emu-1`/`agent-emu-2` (check `adb devices` and qemu processes first), boot
  `emulator -avd agent-emu-1 -port 5584 -no-window -no-audio -no-boot-anim -no-metrics -no-snapshot-save`, then
  `ANDROID_SERIAL=emulator-5584 ./gradlew :app:connectedDebugAndroidTest`. The AVDs render in software on the
  4-core Intel jmbp: after a cold boot SystemUI, the launcher and Digital Wellbeing ANR for several minutes; wait
  for the guest load to drop before tests or captures. Kill the emulator with `adb -s emulator-5584 emu kill`.
- Debug launch extras (debug source set only; release/QA ignore them): `seedDemo`, `demoPro`, `emptyLog`,
  `skipOnboarding`, `previewStore` (US price ladder, no store), `dark`, `uiTest`,
  `route vehicle|log|fuel|recalls|insights|task|add|history|settings|paywall`, `focus <ProFeature>`.

## Catalog parity
- `MaintenanceCatalog.kt` is a mechanical conversion of `Shared/Catalog/MaintenanceCatalog.swift`. After any Swift
  catalog change run `python3 scripts/export-android-catalog.py` (writes
  `android/app/src/test/resources/catalog_literals_swift.json`) and port the change; `CatalogParityTest` fails
  until every computed Kotlin item matches its Swift literal and the literal count matches.
- jmbp's Swift is 5.7 (CommandLineTools), too old to compile the Swift 6 catalog, so the literals are extracted
  from source instead of exported by running Swift.

## Intentionally different from iOS (platform gaps, decisions pending)
- CloudKit sync and family sharing (`CKShare`): no Android equivalent. The log is one JSON file in app storage
  (`files/garage.json`, excluded from backup). Cross-platform sharing needs a backend decision (Supabase or
  similar); not guessed. Settings says sharing and iPhone sync aren't on Android.
- Receipt, pump, odometer and VIN scanning (Vision/VisionKit): not ported. The Android paywall does not claim
  receipt reading. ML Kit would add a Google SDK and a Data safety change; decision pending.
- Not yet ported: photos and documents, second (aux) meters, storage/sold flows, valuations and value links,
  clubs, upgrades and gear browsing, service nearby, import from other apps, the per-VIN NHTSA web check,
  the widget (Glance), trip check.
- Rating ask: Play In-App Review after a logged service from the 2nd launch, 30-day cooldown, no question first.
- Privacy and terms link to `docs/android-privacy.html` and `docs/android-terms.html` (live once merged and
  Pages deploys).

## Play state
- 2026-10-20 (jmbp run): port verified, 51 JVM + 7 connected tests, lint clean, debug and QA APKs. Not created in
  Play Console; no upload key, RevenueCat Play app or Play products yet. Remaining steps are in
  `~/fleet-evidence/shift-android-keyring-1-1792531430/REPORT.md` (release preparation section).
