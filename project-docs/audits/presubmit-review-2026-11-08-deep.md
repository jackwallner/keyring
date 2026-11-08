# Pre-submit deep review, 2026-11-08 (1.1.3 build 26)

Scope: every user-reachable path on `origin/main` (821ef44), plus the app diff since the live version
1.1.2 (dcf314b, build 25): purchase, restore, paywall, onboarding, persistence and migration,
notifications, widget, iPhone Duo layout, import and export, localization. No simulator or local
xcodebuild was used; unit tests ran on GitHub's Macs with `gh-sim test --scheme Keyring`.

Branch: `review/2026-11-08-keyring-deep`.

## Findings

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P0 | Keyring/Views/Components.swift:498, Shared/Export/ServiceImport.swift:475, Shared/Services/FieldReader.swift:108 | Typing 20 digits into any number field (odometer, cost, price), importing a CSV whose mapped column holds a long ID, or scanning a barcode into a field reads as 1e19 or more. Showing it with `Int(value.rounded())` traps, and an import traps in `importHistory`'s duplicate key. | Fixed (dd0ee43): typed, imported and scanned figures are capped below 1e12 by `Format.bounded`. Tests in `NumberFieldTests`. |
| P0 | Keyring/Info.plist, Keyring/Views/HistoryViews.swift:767 | Sharing a saved photo or receipt opens the share sheet with an image, which offers Save Image. The app had no `NSPhotoLibraryAddUsageDescription`, so iOS terminates it on that tap. | Fixed (80e5617): usage string added. Test `PhotoSaveUsageTests`. |
| P0 | Keyring/Views/Components.swift:506, Keyring/Views/FuelLogView.swift:316, Keyring/Views/BuildViews.swift:65, Shared/Services/GarageStore.swift:880 | A figure worked out from two huge typed ones (gallons x price on a fill-up, quantity x price on a part) can pass `Int.max`; the field showing it traps, and a saved cost traps the next import into that vehicle. Needs absurd input. | Fixed (33380a5): worked-out figures and saved costs are bounded, and `NumberField.display` never converts an unbounded value. Test in `OdometerSourceTests`. |
| P1 | Keyring/Views/ImportView.swift:284 | Import from Settings into a garage of 2+ vehicles with a file that has no vehicle column, then "Columns look wrong?" and map a vehicle column: the old blank-name target stays `.unchosen`, so Import stays disabled on "Choose a vehicle" with no picker to clear it. Stale `.new` targets could also raise the paywall for vehicles that would not be created. | Fixed (55a4277): targets for names no longer in the file are dropped. No unit test: the state is private to the view. |
| P1 | Keyring/Views/AddVehicleFlow.swift:96 | Someone with no garage of their own and two joined garages sees the "Add to" picker showing the first joined garage, but the vehicle is saved into a newly created own garage (and counts against their free limit). | Fixed (f95f5d5): with no pick, the vehicle goes to the garage the picker shows. No unit test: view state. |
| P2 | Shared/Services/GarageStore.swift:1059 | The fill-up date picker reaches tomorrow; a fill-up dated ahead set the vehicle's reading date into the future and skewed the pace. Service entries already skipped future dates. | Fixed (a79e427). Test in `OdometerSourceTests`. |
| P2 | Keyring/Views/LogServiceView.swift:141, Keyring/Views/BuildViews.swift:487 | A picked file over 25 MB, or one that fails to read, is dropped with no message. | Not fixed: needs new copy and an alert, a design call. |
| P2 | Keyring/Views/LogServiceView.swift:637 (and Fuel, Add vehicle, Import, new job) | Save has no in-flight guard. A double tap could log twice, but the sheet's dismissal transition blocks touches, so this was not shown to happen. | Not fixed: not reproduced; check on a device. |
| P2 | Shared/Services/StoreService.swift:241 | `errorMessage` outlives the paywall: a cancelled purchase leaves "Purchase wasn't completed" in red the next time the paywall opens. | Not fixed: copy and state design, no lockout. |
| P2 | Shared/Services/SharingService.swift:169 | Leave garage returns silently when `fetchShares` fails, so the garage stays with no message. | Not fixed: needs error copy. |
| P2 | Keyring/Views/OnboardingView.swift:294 | "Try Pro free for a week" hard-codes the trial length. Correct for all three current products (1-week trial). | Not fixed: accurate today; reword if the trial changes. |

## Checked and fine

- Diff since 1.1.2: reading-source resets on edit and delete of entries and readings, `readingWasTyped` on a
  miles/km switch, widget status aging (`WidgetSnapshot.Item.status(on:)`, `DueStatus` is Comparable and the
  widget target compiles `DueEngine`), RevenueCat `paymentPendingError` mapped to pending, Settings refresh on
  return from iPhone Settings, planned slots counting retired vehicles.
- Purchase and restore: offering `default` with fallback to current, package kinds by type then identifier,
  intro eligibility resolved before any trial copy, cached Pro survives an offline launch, the paywall always
  has a close button, Terms and Privacy links on the paywall and onboarding, prices only from StoreKit, the
  `appl_` key never configured on the simulator, the Pro toggle in Settings is DEBUG-only.
- Gating: free limit enforced on add, planned slots, unretire and import; joined garages never count.
- Persistence: no model change since 1.1.2; every attribute optional or defaulted; locked-device stand-in
  store refuses writes; corrupt stores are moved aside, never deleted; `VehicleProfile` and `EntryDetails`
  JSON decode old saved data (every non-optional field existed from the first release).
- Notifications: one plan rebuilt after each change with stable identifiers, overdue roll-up capped, recall
  alerts deduped by campaign; the tap handler answers on the main thread.
- Duo: single view tree, pane selection only while split, notification routes select into the pane.
- Release-only paths: `ScreenshotConfig` and `-PaywallSnapshot` are constant off in Release.
- Localization: English only; number parsing handles native digits and locale separators (tested).
