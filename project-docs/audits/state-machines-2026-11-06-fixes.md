# Fixes for the state machine audit, 2026-11-06

Fixes for every claim `state-machines-2026-11-06-review.md` marked CONFIRMED or CONFIRMED-MINOR, in the review's ranked order. Base: `b44ea85`.

**Summary: 8 claims in scope (SM-2, MB-1, SM-1, S3, SM-3, MB-2, S1, SM-4). 8 fixed, 0 held, 0 skipped. 0 UNVERIFIED claims. S2 left alone (NOT A BUG).**

## Claims

| id | outcome | commit | regression test | what changed |
|---|---|---|---|---|
| SM-2 | fixed | `602751f` | `OdometerSourceTests`: `testEditingTheEntryToFixATypoLowersTheVehicleReading`, `testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading`, `testEditingAFillUpToFixATypoLowersTheVehicleReading`, `testDeletingAFillUpLoggedOnTheWrongVehicleRestoresTheReading` (controls: `testEditingAnEntryUpwardStillRaisesTheVehicleReading`, `testDeletingAnOlderEntryLeavesTheReading`, `testDeletingAnEntryAboveACorrectedReadingKeepsTheCorrection`) | `GarageStore.log(editing:)`, `logFuel(editing:)` and `delete(_ entry:)`: when the entry carried the vehicle's reading and is lowered, cleared or deleted, the reading falls back to the highest figure any saved reading or logged entry still carries, with its date (`resetReadingToHighestKnown`). Only that entry moves the cache, so an Edit vehicle correction below an older typo entry stays. |
| MB-1 | fixed | `ee5dfc8` | `PurchaseErrorTests` | `StoreService.purchase` maps RevenueCat's thrown `paymentPendingError` to `.pending` with no error message (`state(forPurchaseError:)`), so the paywall and onboarding show the existing "Waiting on Apple" copy instead of "Couldn't start your trial". No change to how Pro is judged or when a paywall shows. |
| SM-1 | fixed | `602751f` (shared with SM-2) | `OdometerSourceTests`: `testDeletingATypoReadingKeepsTheNewestFillUpReading`, `testDeletingAnOldReadingKeepsTheNewerFillUp` (control: `testDeletingATypoReadingFallsBackToTheEarlierReading`) | `GarageStore.delete(_ reading:)`, main meter: only a deleted row that carried the vehicle's reading moves it, and it falls back to the highest remaining row or entry, not the latest row. Deleting an old correct row leaves the reading. The aux meter branch is unchanged. |
| S3 | fixed | `b153d9f` | `WidgetStatusTests` | `WidgetSnapshot.Item.status(on:)` derives the status on the render date: a passed calendar date reads Overdue, a passed estimate reads due soon (never green), an up-to-date job inside the 30 day window reads due soon. The widget's label, colour and sort (`upcoming(on:)`) use it. |
| SM-3 | fixed | `b21aabc` | `UnitSwitchReadingTests`: `testSwitchingUnitsInTheEditorKeepsThePace` (controls: `testATypedFigureInTheNewUnitStillSetsTheMeter`, `testAnUntouchedFieldWithoutASwitchIsNotTyped`) | `EditVehicleView.save()` counts the odometer as typed only when it differs from the current reading converted to the picked unit (raw or rounded, `readingWasTyped`), so a unit switch alone no longer calls `correctReading`. |
| MB-2 | fixed | `b21aabc` (shared with SM-3) | `UnitSwitchReadingTests.testSwitchingUnitsInTheEditorKeepsTheLastRealReading` | Same change: with no `correctReading`, the rounded-down field no longer deletes the converted last real reading. |
| S1 | fixed | `b171abf` | none possible headless, see below | `SettingsView` re-reads the notification status when the scene becomes active, so the row updates on return from iPhone Settings. |
| SM-4 | fixed | `884739d` | `PlannedVehicleSlotTests` | `PlannedVehicles.remaining(_:in:)` crosses planned kinds off with owned vehicles including sold and retired ones; `GarageView.plannedSlots` uses it. A deleted vehicle still brings its card back, as the audit called acceptable. |

Regression test notes:
- The SM-1 and SM-2 tests use only APIs that exist on `b44ea85` and are the repro tests the review called sound, plus the review's own variants. Their failure on the base is recorded below.
- The SM-3, MB-2 and SM-4 tests call the helper the fix introduced, so on the base they do not compile; the same replay failed on the base in the audit's and review's runs (10.7285 vs 13.4112, real reading deleted, slot offered again).
- S3 and MB-1 had no reachable seam before (the widget's `when()` is private to the widget target, the purchase error path ran inline). The tests cover the extracted logic the widget and `purchase` now call.
- S1: the simulator cannot grant notification permission from outside the app, and `SettingsView` is not instantiable in a unit test. A device check settles it: deny the prompt, open Settings tab, tap "Turn on in iPhone Settings", allow, switch back; the row should become "Remind me at" without leaving the tab.
- The audit's repro suite was never added to the test target, so there was nothing to remove.

## Held for Jack

None.

## Skipped

None.

## Disputed

None.

## Not in scope

- S2: NOT A BUG per the review. The MB-1 fix clears `errorMessage` on the pending path, so a stale cancel message cannot show beside the pending copy either.
- P1 to P6: product calls, unchanged.
- The aux (hour) meter has the same raise-only rule for entries (`GarageStore.log`, `auxReading`). Neither the audit nor the review claimed it, so it is unchanged.

## Test results

- Full suite with the fixes: `gh-sim test --scheme Keyring`, run `keyring@20261106-182134-5740-claude-mbpro32c53-1106-182806-4215` (GitHub Actions run 42329398233; Xcode 27.1, iPhone 17, iOS 27.2). **174 passed, 0 failed, 0 skipped**, including all 25 new tests. No test failed, so none needed a check on `b44ea85`, and no test already failed there.
- New SM-1 and SM-2 tests on `b44ea85` without the fix: `gh-sim test --only KeyringTests/OdometerSourceTests`, run `keyring-base-b44ea85-mbpro32c53-1106-192803-12127`. The 6 claim tests failed, the 4 controls passed:
  - `testEditingTheEntryToFixATypoLowersTheVehicleReading`: 54000 vs 52000
  - `testEditingAFillUpToFixATypoLowersTheVehicleReading`: 54000 vs 52000
  - `testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading`: 62000 vs 50000
  - `testDeletingAFillUpLoggedOnTheWrongVehicleRestoresTheReading`: 53000 vs 51000
  - `testDeletingATypoReadingKeepsTheNewestFillUpReading`: 50000 vs 52000
  - `testDeletingAnOldReadingKeepsTheNewerFillUp`: 51000 vs 55000
  - Passed: `testDeletingATypoReadingFallsBackToTheEarlierReading`, `testDeletingAnEntryAboveACorrectedReadingKeepsTheCorrection`, `testDeletingAnOlderEntryLeavesTheReading`, `testEditingAnEntryUpwardStillRaisesTheVehicleReading`.
