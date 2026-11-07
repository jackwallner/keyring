VERDICT: PASS

# Verification of the state machine fixes, 2026-11-06

Independent check of `state-machines-2026-11-06-fixes.md` against `state-machines-2026-11-06-review.md` and the audit. Change read in full: `git diff b44ea8585eae530a696ca7355948c1477d64593a..HEAD` (6 fix commits, the fixes doc, an empty snapshot commit). No app code or tests changed by this check.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| SM-2 | yes | clean (one edge in notes) | Route: History swipe > Delete (`HistoryViews.swift:201,621`) calls `delete(_ entry:)`, which now captures whether the entry carried the cache before deleting it and falls back to the highest surviving row or entry (`GarageStore.swift:1115-1117`, `:800-812`). Edit goes through `LogServiceView.swift:646` / `FuelLogView.swift:439` into `log(editing:)` / `logFuel(editing:)`, which check the source before the entry is overwritten (`:855`, `:1027`) and reset when the new figure is lower or cleared (`:897-901`, `:1057-1061`). Upward edits keep the old raise path. Tests assert the cache and date after the transition; reverted fix fails (run below). |
| MB-1 | yes | clean | RevenueCat 5.96.0 throws `ErrorUtils.paymentDeferredError()` for StoreKit `.pending` (`StoreKit2TransactionListener.swift:131-132`), code `ErrorCode.paymentPendingError` (`ErrorUtils.swift:230-235`), fetched from the tagged source. `purchase` now maps that to `.pending` with `errorMessage = nil` (`StoreService.swift:256-268`, `:281-287`). Paywall shows the existing pending copy on `.pending` (`PaywallView.swift:195`); onboarding shows it and does not open the paywall (`OnboardingView.swift:492-507`). `update(customerInfo:)`, `isPro`, the offer and paywall triggers are untouched. Reverted fix fails the test. |
| SM-1 | yes | clean (same edge as SM-2) | Route: Saved readings swipe > Delete (`VehicleDetailView.swift:967`). Main meter now moves the cache only when the deleted row carried it (`reading.value >= vehicle.reading`, `GarageStore.swift:782`) and falls back to the highest row or entry. Deleting an old correct row no longer drops the odometer. Aux branch unchanged in behaviour. Reverted fix fails the test. |
| S3 | yes | clean | Widget label, colour and sort now derive from `Item.status(on:)` (`KeyringWidget.swift:44,146,154`; `WidgetSnapshot.swift:20-27,72-79`). Matches `DueEngine.evaluate`: a passed calendar date is overdue (`DueEngine.swift:76`), a passed estimate stays due soon (overdue by meter only when the reading reaches the target), and the 30 day window is the same constant (`soonWindowDays`, `:51`). Snapshot JSON fields unchanged, so existing App Group snapshots decode. `DueEngine.swift` is already in the widget target (`project.yml:82`). Tests call the same function the widget calls. |
| SM-3 | yes | clean | `EditVehicleView.save()` computes `readingTyped` with `readingWasTyped` before `changeMeter` (`AddVehicleFlow.swift:839-840`); a field that equals the converted reading, raw or rounded (the form rounds on switch, `:503-505`), no longer calls `correctReading` (`:861-862`). `NumberField` keeps the bound value unless the user edits it (`Components.swift:457-466`), so the comparison sees the form's figure. Typed figures and hours switches (convert returns nil) still correct the meter, as before. Shared vehicles cannot switch (`meterLocked`). The test replays `save()` in the same order; the base check (`draft.reading != shownReading`) fails it, as recorded in the review run. |
| MB-2 | yes | clean | Same change: no `correctReading`, so `GarageStore.swift:715` never deletes the converted 12,000 mi row. `testSwitchingUnitsInTheEditorKeepsTheLastRealReading` asserts the row count, the converted value and `readingDate`. |
| S1 | yes (code) | clean | `SettingsView.swift:185-187` re-reads the authorization status on `scenePhase == .active`, the transition taken on return from iPhone Settings. No headless test possible (simulator cannot grant permission from outside the app); accepted as the review said. No stored state written. |
| SM-4 | yes | clean | `GarageView.swift:318` uses `PlannedVehicles.remaining(_:in:)` (`OnboardingView.swift:554-557`), which counts retired and sold own-garage vehicles. A garage holding only a sold planned car now shows the normal empty state with "Add a vehicle" (`GarageView.swift:36-43`) instead of the dashed card. Pro lock on cards (`:324`) still uses `ownedVehicleCount`, so the free limit and paywall timing are unchanged. |

## Revert proof (top three)

On `scratch-revert` (since deleted): `Shared/Services/GarageStore.swift` restored to `b44ea85` (reverts SM-2 and SM-1, which share commit `56cf493`), and the `paymentPendingError` mapping removed from `StoreService.state(forPurchaseError:)` (the MB-1 test calls that helper, so the logic was reverted and the helper kept to compile the test). Tests unchanged.

gh-sim `keyring@20261106-202901-21c7-claude-mbpro33a32-1106-211701-22430`, GitHub run 42342062247: 0 passed, 3 failed.
- `PurchaseErrorTests/testAPendingPaymentIsNotAFailure`: nil vs `.pending`
- `OdometerSourceTests/testDeletingAFillUpLoggedOnTheWrongVehicleRestoresTheReading`: 53000 vs 51000
- `OdometerSourceTests/testDeletingAnOldReadingKeepsTheNewerFillUp`: 51000 vs 55000

Each regression test fails without its fix and passes with it.

## Must change

Nothing.

## Test results

- Full suite on HEAD: `gh-sim test --scheme Keyring`, id `keyring@20261106-202901-21c7-claude-mbpro33a32-1106-203227-3777`, GitHub run 42338904136 (Xcode 27.1, iPhone 17, iOS 27.2): **174 passed, 0 failed, 0 skipped**. Matches the fixes doc (174 passed). No new failure, nothing to rerun on the base.
- Revert proof: GitHub run 42342062247, above.
- Screens: `gh-sim launch --args "-SeedDemo" --screen "-ScreenshotRoute settings" --screen "-EmptyLog"`, id `keyring@20261106-202901-21c7-claude-mbpro33a32-1106-222247-10722`, GitHub run 42346746019: build and launch succeeded; see notes.

## Scope (check 4)

- Changes stay within the 8 listed claims; every diff hunk maps to one of them.
- No trial, onboarding order, offer, price, membership or paywall-trigger change. MB-1 only reroutes a thrown pending error to the existing pending copy.
- No backend, App Store Connect or RevenueCat change.
- No UNVERIFIED claim (the review had none). S3, S1 and MB-1 were CONFIRMED by the review on code reading, so a fix without a failing base test is allowed.
- No stored setting or record cleared on an inferred state. `errorMessage` is in-memory only.
- No stored format change: `WidgetSnapshot` Codable fields unchanged (`upcoming` became a function, not a field); Core Data model untouched.
- No held items. Every in-scope review claim (SM-2, MB-1, SM-1, S3, SM-3, MB-2, S1, SM-4) is in the fixes table; S2 left alone as NOT A BUG.
- Disputed: the fixes doc lists none, so there is nothing to rule on.

## Notes

- Screens (real screenshots from run 42346746019): Garage with the demo garage renders normally (recalls, Needs attention, key tags, tab bar), and Settings renders with the Reminders row ("Turn on reminders") and no layout change. The changed states themselves cannot be reached from launch args: a sold onboarding-planned car (needs onboarding picks plus a sale), the widget after its due date passes, the return from iPhone Settings with permission granted, and an Edit vehicle unit switch. None of these changes adds or moves a view, so the unit tests and code reading above carry them.
- Upgrade edge, not a failure: `correctReading` (Edit vehicle) leaves entries above the corrected figure (`GarageStore.swift:715` deletes rows only). A user who used that escape hatch on the base build to walk back a typo entry, and never fixed the entry itself, keeps that typo entry in the log. If they later delete or lower the entry or row that now carries the reading, `resetReadingToHighestKnown` picks the typo entry and the odometer jumps back up to it. This is consistent with invariant I1 (the typo is still a logged figure, and the pace and `reading(of:on:)` already count it), it needs a prior manual correction plus a later delete of the current source, and the typo entry can now be edited down because of this fix. Worth a follow-up only if it shows up in support.
- `isSourceOfReading` compares doubles exactly. That is sound: the cache is assigned from the entry's own value, and `changeMeter` scales both by the same factor.
- `plannedSlots` now runs a Core Data fetch (`retiredVehicles`) per evaluation; `GarageView` already fetched it twice per body for the Sold and retired link. No visible cost.
- The widget uses `.now` in the view rather than the entry date; this was already true of the "Today"/"in N days" text, and the timeline has one entry refreshed after midnight.
- The fixes doc cites commit ids (`602751f`, `ee5dfc8`, `b153d9f`, `b21aabc`, `b171abf`, `884739d`) that differ from the branch's (`56cf493`, `0a51ffa`, `37b9d70`, `7dc3bde`, `e672682`, `b64e6a1`). Each pair has an identical diff (checked), so it is a rebase, not a content mismatch.
- No watch target exists; notifications, localized strings and Duo layouts are not touched by the diff beyond the Garage planned card count.
