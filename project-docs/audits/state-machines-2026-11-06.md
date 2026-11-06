# State machine audit, 2026-11-06

Scope: iOS app, `Shared/`, the widget. No watch target and no backend function exist in the repo (entitlements come from RevenueCat on the device). Android is out of scope. Audited committed code at `f6f96fb` (tree was clean, `git stash -u` saved nothing). Nothing was fixed.

**Summary: 4 bugs proved by test (SM-1 to SM-4), 3 code path only (S1 to S3), 6 product calls.** The repro suite is `state-machines-2026-11-06-repro.swift` (9 tests: 5 failing findings, 4 passing controls). Final recorded run: gh-sim `keyring@20261106-114528-dd93-claude-mbpro3742e-1106-123401-9999` (xcode 27.1, iPhone 17, iOS 27.2).

Money, trials and entitlements held up: the 2-vehicle free limit is enforced at every owned-vehicle entry point, trial copy is gated on resolved intro eligibility, and the reminder pipeline rebuilds from scratch after every write and every foreground. The bugs are all in the cached meter reading and one derived list.

## Test seams used

- `GarageStore(persistence: Persistence(cloudKit: false, inMemory: true))` with real `log`, `logFuel`, `updateReading`, `correctReading`, `changeMeter`, `markSold`, `delete`.
- `ReminderScheduler.plan(...)` is pure and already covered. The scheduler itself talks to `UNUserNotificationCenter.current()` directly (`ReminderScheduler.swift:16`), so there is no fake to inject and pending-request claims stay unproved.
- `StoreService` is a private-init singleton with a private `update(customerInfo:)` and no `CustomerInfo` fixture path, so purchase-state claims stay code path.
- The widget view's `when()` is private to the widget target, which the test bundle does not include.
- `NSTimeZone.default` is settable (used in `CSVExportDateTests`); no time zone bug was found worth a test.

## Bugs, ranked by users reached times cost

| id | bug | what the user sees | promise | user route | impact | evidence | file:line |
|---|---|---|---|---|---|---|---|
| SM-2 | Editing or deleting the service or fill-up that set the odometer leaves `vehicle.reading` at the old figure | After fixing a mistyped odometer on an entry, the vehicle page and every distance-based "due" still use the typo. Delete the entry: same | `GarageStore.swift:283` "The highest reading known by the end of `date`, from meter updates and logged entries" (the app's own definition of the reading); the Update odometer sheet tells the user "To fix a typo, delete the wrong reading below" (`VehicleDetailView.swift:936`) but an entry's reading is not in that list (it lists `MeterReading` rows only, `VehicleDetailView.swift:917-919`). Indirect, see note 1 | Garage > vehicle > Log service, reading 54,000 (truth 52,000; under the extra-digit prompt) > Save > History tab > swipe the entry > Edit > reading 52,000 > Save > Garage > vehicle page odometer still reads 54,000. Or swipe > Delete | Anyone who logs readings through services or fill-ups (fill-ups are free, so most users), on any typo smaller than the prompt threshold (about 5,000 mi on a 30 day gap) or that they confirmed through the prompt. Every device, no special setup. Cost: odometer and all due statuses wrong until they find Edit vehicle > odometer, the only reset (`AddVehicleFlow.swift:860-862`) | Proved: `testEditingTheEntryToFixATypoLowersTheVehicleReading`, `testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading`; controls `testControlEditingAnEntryUpwardRaisesTheVehicleReading` passes (raise works, lower does not) | `GarageStore.swift:885` (only raises), `:1089` (`delete(_ entry:)` no recompute), fuel twin `:1042` (same raise-only rule, untested) |
| SM-1 | Deleting a saved odometer reading falls back to the latest remaining `MeterReading`, ignoring fill-ups and services logged since | Delete the typo per the footer and the odometer drops below a fill-up already in the log | `VehicleDetailView.swift:936` "To fix a typo, delete the wrong reading below" and `:973` "Swipe left on a wrong reading to delete it"; `GarageStore.swift:790` (aux branch) "the wrong figure can't stay as the vehicle's reading", and `:793-797` treats logged entries as a source of the reading when no row is left | Garage > vehicle > Fill-up (52,000) > vehicle page odometer button > Update odometer, type 520,000 > Save > "Save 520,000?" confirm > reopen the sheet > Saved readings > swipe the 520,000 row > Delete. Odometer reads 50,000, the fill-up says 52,000 | Users who add a vehicle with an odometer (one `MeterReading` is created at setup, `GarageStore.swift:411-418`), log later fill-ups or services, then save and delete a wrong manual reading. Rarer than SM-2 (needs a manual update typo and the delete), same cost: understated odometer means jobs show later than they are, and `readingDate` reverts so the pace is computed from older data | Proved: `testDeletingATypoReadingKeepsTheNewestFillUpReading` ("50000.0" is not equal to "52000.0"); control `testControlDeletingATypoReadingFallsBackToTheEarlierReading` passes | `GarageStore.swift:776-801` (entries consulted only when no row remains, `:793-797`) |
| SM-3 | Switching miles/km in Edit vehicle also stamps a "reading today" | Estimated due dates get later after a unit switch, because the pace is computed over a gap that now ends today with no distance driven | `AddVehicleFlow.swift:860` "Edit sets the meter exactly, so a typo can be walked back" describes a typed reading, and `GarageStore.swift:730` says `changeMeter` "Miles and kilometers convert every stored figure" | Garage > vehicle > Edit (top right, `VehicleDetailView.swift:74`) > Meter picker: Kilometers > Save (nothing typed). The form converts and rounds the odometer field (`AddVehicleFlow.swift:502-508`), so `readingTyped` (`:839`) is true and `correctReading` runs with `readingDate = now` | People who switch unit and whose last real reading is older than a few weeks and who have under a year of readings (until then it is the pace fallback that rules). Rare event (metric users who first picked miles); cost is moderate, wrong estimated dates and reminder dates until the pace recovers, self-heals after new readings. Shared garages are exempt (`meterLocked`) | Proved: `testSwitchingUnitsInTheEditorKeepsThePace` (10.7285 is not 13.4112 +/- 0.3); control `testControlSwitchingUnitsConvertsThePace` passes. The test replays the sequence in `EditVehicleView.save()` (`:838-863`) because the view is not instantiable | `AddVehicleFlow.swift:839,860-862`, `GarageStore.swift:712-727` |
| SM-4 | Selling a vehicle brings its onboarding "Add your car" card back | After marking the car sold, the garage shows a dashed "Add your car" card again | `GarageView.swift:316` "Vehicles picked in onboarding and not added yet" | Onboarding: pick Car > finish > add the car > vehicle page > Sold or retired > Garage | Only users who picked kinds in onboarding and later sell or retire a vehicle of a picked kind; one card, removable by long press (`GarageView.swift:352`). Low | Proved (expression replayed from the view): `testSellingThePlannedCarDoesNotBringItsSlotBack`; control `testControlAddingThePlannedCarCrossesItOff` passes | `GarageView.swift:317-319` (reads `garage.vehicles`, which hides retired, `GarageStore.swift:186`) |
| S3 | Widget shows "Today" forever for a job that has gone overdue | Home Screen widget says "Today" in the due-soon colour for a job the app calls Overdue | `KeyringWidget.swift:174` "The next maintenance due across your garage."; `WidgetSnapshot.swift:6` "written by the app after every change" | Open the app (job due in 5 days) > leave the phone 3 weeks > widget reads "Today" (`KeyringWidget.swift:159`, `..<1`) | Widget users who go weeks without opening the app (a maintenance app is opened rarely). The reminder still fires on the due day and each Saturday, so the cost is a wrong glance, not a missed job | Code path. The test bundle cannot reach the widget view's private `when()`. A widget snapshot test with `statusRaw = 1` and a `dueDate` 20 days back would settle it | `KeyringWidget.swift:12-16,155-165`, `GarageStore.swift:1285-1305` (written only from `publish()`) |
| S2 | A stale purchase error shows beside the Ask to Buy pending message | Red "Trial wasn't started. Tap again to continue." under "Waiting on Apple to confirm" | `ConversionCopy.swift` `purchasePendingMessage` "Nothing has failed and nothing has completed" | Paywall > Continue with Pro > cancel the system sheet > Continue with Pro again on an Ask to Buy account | Ask to Buy accounts that cancel once first; tiny population | Code path. `StoreService.errorMessage` is `private(set)`, set at `StoreService.swift:241,259` on cancel and never cleared on a new purchase or a `.pending` result; `StoreService` has no injectable `Purchases`. Settled by a fake `Purchases` or a `CustomerInfo` fixture path | `StoreService.swift:230-270`, `PaywallView.swift:195,213` |
| S1 | Settings keeps the old notification row after the user returns from iOS Settings | "Turn on in iPhone Settings" stays after permission was granted (reminders themselves do schedule, on the next foreground) | `SettingsView.swift:100` footer "A heads-up a week before each job..." | Settings tab > Turn on in iPhone Settings > enable > return | Users who denied the first prompt and later re-enable. Display only | Code path. `notificationStatus` is set only in `.task` (`SettingsView.swift:179-182`). Settled by a UI test that backgrounds the app, or knowing whether the tab's `.task` re-runs on re-selection | `SettingsView.swift:179-182,243` |

Notes
1. SM-2's promise is indirect, by design of the sources: no copy says "fixing an entry fixes the odometer". The reviewer should treat it as the weakest cited claim among the proved four. What makes it a bug and not a product call is that the app's own definition of the current reading (`reading(of:on:)`, `delete(_ reading:)`'s entries fallback at `:791-797`) includes entries, and the cache disagrees with that definition after an edit.
2. The first gh-sim run's version of the edit test failed its own precondition (62,000 triggers the extra-digit prompt, so it could not be reached without confirming a dialog). It was changed to 54,000 and rerun; in the final run every precondition assertion held and only the claim failed.

## Recorded values

Final run (`...-1106-123401-9999`, 4 passed, 5 failed), failures verbatim:
- `testDeletingATypoReadingKeepsTheNewestFillUpReading`: ("50000.0") is not equal to ("52000.0")
- `testDeletingTheEntryThatSetTheReadingLowersTheVehicleReading`: ("62000.0") is not equal to ("50000.0")
- `testEditingTheEntryToFixATypoLowersTheVehicleReading`: ("54000.0") is not equal to ("52000.0")
- `testSwitchingUnitsInTheEditorKeepsThePace`: ("10.728533329411542") is not equal to ("13.411199996792732") +/- ("0.3")
- `testSellingThePlannedCarDoesNotBringItsSlotBack`: XCTAssertTrue failed (slot offered again)
- Passed: `testControlDeletingATypoReadingFallsBackToTheEarlierReading`, `testControlEditingAnEntryUpwardRaisesTheVehicleReading`, `testControlSwitchingUnitsConvertsThePace`, `testControlAddingThePlannedCarCrossesItOff`.

The first run (`...-1106-120009-4428`) gave the same values for the other four tests (50000/52000, 62000/50000, 10.72853332944174 vs 13.411199997152325, slot offered again).

## Product calls (no promise to quote, not counted)

- P1. A usage event (track day, water crossing) logged on the same calendar day as the service is ignored: `pendingEvent` starts the window at the next day (`GarageStore.swift:358`). Same-day granularity is probably intended; a track day after the morning brake job does not bring brakes due.
- P2. No notification prompt exists for a device that gets vehicles without `AddVehicleFlow` (second family member joining a shared garage, new phone restoring from iCloud, import creating vehicles). The Settings "Turn on reminders" button is the only route (`SettingsView.swift:77-82`); `AddVehicleFlow.swift:100-106` asks only after the first add.
- P3. Cached `isPro` stands when RevenueCat cannot be reached (`StoreService.swift:162,358`), and a lapsed Pro keeps all vehicles beyond the free two. Both read as grace by design.
- P4. `RecallWatcher.record` stores the new list before `notify` checks permission (`RecallWatcher.swift:34,61-62`), so a recall that appears while notifications are off is never pushed, though the in-app banner shows it.
- P5. `ReviewPrompter.markAsked` stamps the 30 day cooldown before the system decides whether to show the prompt.
- P6. Overlapping `schedule` calls: a cancelled task still calls `removeAllPendingNotificationRequests` once and can finish one in-flight `add` (`ReminderScheduler.swift:144-158`). Not reproducible without a fake notification center; no failure observed.

## Related fixes, in order

1. SM-2 and SM-1 together: make the cache derived. One `refreshReading(of:)` that sets `reading`/`readingDate` from the max of `MeterReading` rows and entries, called from `delete(_ reading:)`, `delete(_ entry:)`, `log(editing:)`, `logFuel(editing:)` and the fuel delete. Then the Update odometer footer stays true.
2. SM-3: in `EditVehicleView.save()`, call `correctReading` only when the draft figure differs from the converted current reading (compare after `changeMeter`).
3. SM-4: compute `plannedSlots` from owned vehicles including retired ones.
4. S3: let the widget compute status from `dueDate` and the render date, or have the app refresh the snapshot from the background recall task.
5. S2 and S1: clear `errorMessage` when a purchase starts; refresh `notificationStatus` on `scenePhase == .active`.


## State machines

Marked "bad" transitions break the invariant named in the last column. Ids refer to the bug table.

### M1. Vehicle meter (implicit: `Vehicle.reading` / `readingDate` cache plus `MeterReading` rows plus `ServiceEntry.reading`)

Sources of truth for "what the odometer is": `Vehicle.reading` (a cached high-water mark), `MeterReading` rows, and `ServiceEntry.reading` on every service, repair and fill-up. Only `updateReading`, `correctReading` and `recordOdometerChange` write a `MeterReading`; `log`, `logFuel` and `importHistory` raise the cache without one.

Invariants
- I1. `vehicle.reading` equals the highest reading any surviving `MeterReading` or entry carries (the definition `GarageStore.reading(of:on:)` uses, "The highest reading known").
- I2. `readingDate` is the date of that reading, so the pace (`dailyUse`) is computed from real measurements only.
- I3. Stored readings are true totals (shown + odometer-change offset), in the vehicle's unit.

| From | Event | To | Invariant |
|---|---|---|---|
| any | `updateReading` higher | cache raised, row added | ok |
| any | `log` / `logFuel` with higher reading | cache raised, no row | ok (but see next rows) |
| cache set by an entry | edit that entry to a lower reading (`log(editing:)` only ever raises) | cache unchanged | breaks I1 (SM-2) |
| cache set by an entry | `delete(entry)` | cache unchanged | breaks I1 (SM-2) |
| cache set by a row, entries hold more | `delete(reading)` falls back to latest remaining row, ignores entries unless no row is left | cache below an entry | breaks I1 (SM-1) |
| any | `correctReading` | cache = value, `readingDate` = now, rows above removed, entries above untouched | breaks I2 when called from a unit switch (SM-3); entries above the value are left (documented escape hatch, Edit vehicle) |
| miles/km | `changeMeter` | all stored figures scaled | ok (`yearlyUse` is converted by the form, `AddVehicleFlow.swift:509`) |
| miles/km/hours | `changeMeter` to or from hours | readings cleared, intervals reset to catalog | ok, confirmed in a dialog (`AddVehicleFlow.swift:806`) |
| any | `removeOdometerChange` | offset dropped, stored true totals kept | ok: stored totals stay equal to what the gauge would have shown with no rollover |

### M2. Due status of a job (explicit enum `DueStatus`, pure `DueEngine`)

States: `noRecord`, `ok`, `dueSoon`, `overdue`. Derived on every read from last-done (entries covering the task, or the setup baseline), the meter and the pace. Nothing is persisted, so edits and deletes of entries are always reflected. Triggered jobs (`UsageEvent`) add `DueEngine.triggered`.

Invariants
- D1. status is a pure function of (entries, baseline, vehicle reading, pace, now).
- D2. a stored vehicle (`storedSince != nil`) has pace 0, only the calendar runs.

| From | Event | To |
|---|---|---|
| noRecord | baseline set or entry logged | ok / dueSoon / overdue |
| ok | now passes due date, or reading passes target | dueSoon, then overdue |
| overdue | entry covering the task logged, or entry deleted/edited away | recomputed (a deleted entry reverts the job, correct) |
| any | cache reading wrong (M1) | status wrong, because `currentReading` is the cache | indirect, SM-1/SM-2 |
| any | event logged on the same calendar day as the last service | event ignored (`pendingEvent` uses start of the next day), see Product calls |

### M3. Reminder pipeline (implicit: UserDefaults mute/hour keys + iOS permission + pending requests)

State: (iOS authorization: notDetermined / denied / authorized / provisional) x (per-vehicle mute) x (reminder hour) x (stored/retired/sold vehicles) x (pending requests on the device). The pending set is rebuilt from scratch by `ReminderScheduler.schedule(for:)`, which runs from `GarageStore.publish()` after every `save()` and `reload()` (every foreground, every CloudKit remote change), from `setMuted`, `setReminderHour`, the Settings "Turn on reminders" button and the first-vehicle prompt.

Call sites of the scheduler (complete): `GarageStore.swift:1305` (publish), `ReminderScheduler.swift` `setReminderHour` and `setMuted`, `SettingsView.swift:81`, `AddVehicleFlow.swift:104`. Nothing else adds or removes pending requests. Recalls use an immediate request (`trigger: nil`, `RecallWatcher.swift:81`), never pending.

Invariants
- N1. After any change to dues, mute, hour, storage, retirement or deletion, the pending set equals `plan(...)` for the current store.
- N2. When permission arrives later, the next foreground rebuilds the set.
- N3. Nothing is pending for a done job.

| From | Event | To | Invariant |
|---|---|---|---|
| any | log, edit, delete, retire, sell, store, mute (all call `save()` or `schedule`) | rebuilt | N1 ok |
| authorized | permission revoked in iOS Settings | requests stay pending but are not shown | ok |
| denied / notDetermined | granted in iOS Settings | next foreground `reload()` rebuilds | N2 ok (verified from code: `App.swift` scenePhase active -> `garage.reload()` -> `publish()`) |
| denied / notDetermined | `schedule` | returns before `removeAllPendingNotificationRequests` (`ReminderScheduler.swift:147`), leaves older pending requests | ok, iOS withholds them |
| authorized | two `schedule` calls overlap | the first task is cancelled, but a cancelled task still calls `removeAll` once and may finish one `add` | N1 could break for one request; cannot be run (no fake behind `UNUserNotificationCenter.current()`), left as an unproved note |
| authorized | app suspended mid loop (a background CloudKit import calls `schedule`) | the set was wiped and is partly refilled, soonest first | N1 broken until the next foreground; not reproducible without a fake |
| notDetermined | user never adds a vehicle on this device (joined a shared garage, restored from iCloud, imported) | no prompt anywhere except Settings > "Turn on reminders" | product call P2 |
| Settings visible | permission changed in iOS Settings and user returns | `notificationStatus` is `@State` set in `.task` only (`SettingsView.swift:179-182`), so the row can show the old state until the tab re-appears | display only, bug S1 (code path) |

### M4. Pro entitlement and purchase (`StoreService`)

State: `isPro` (cached in the App Group, restored at init), `packages`, `introEligibility` + `introEligibilityResolved`, `errorMessage` (one shared field), `isLoading`, `isConfigured`.

Invariants
- E1. `isPro == !customerInfo.entitlements.active.isEmpty` after every `update`.
- E2. Trial copy is shown only after eligibility resolved and eligible.
- E3. A message shown beside a purchase result describes that result.

| From | Event | To | Invariant |
|---|---|---|---|
| any | launch | `isPro` = cached value; `refreshStatus` replaces it on success; on failure the cache stands and an error is set | E1 held after success; offline lapse stays Pro until a fetch (grace, product call P3) |
| any | `receivedUpdated` delegate | `update` | ok |
| not Pro | purchase cancelled | `errorMessage` = "Trial wasn't started. Tap again to continue." | ok |
| `errorMessage` set | next purchase returns `.pending` | `errorMessage` untouched, paywall also shows the pending message | breaks E3 (S2, code path) |
| `errorMessage` set | `isPro` becomes true | subscriber view hides it; the string stays until the next offering load | harmless |
| not Pro | restore finds nothing | `errorMessage` set | ok |
| any | simulator | never configured, StoreKit fixtures | by design |

Free-tier limit (`ProFeature.freeVehicleLimit = 2`, counted by `ownedVehicleCount`, non-retired, own garage only) is enforced at all four entry points: `GarageView.startAdding`, `VehicleDetailView.restore`, `ImportView.commit` and the planned cards. No path found that adds an owned vehicle past it without Pro. A lapsed Pro keeps every vehicle (product call P3).

### M5. Vehicle lifecycle (`isRetired`, `soldDate`, `storedSince`, `storedUntil`, delete)

States: active, stored, retired/sold, deleted. `retire(false)` clears sold fields but keeps `storedSince`; `store` keeps the earlier `storedSince`; `returnFromStorage` clears both. Reminders: active only (stored vehicles contribute only the "comes out of storage" note). Widget: active, non-stored.

| From | Event | To | Invariant |
|---|---|---|---|
| active | store(until) | stored, return note planned | ok |
| stored | return | active, `storedUntil` cleared, note removed on rebuild | ok |
| active | markSold | retired, no reminders, widget row gone | ok |
| retired | restore | active, gated by the free limit | ok |
| retired (was planned in onboarding) | `GarageView.plannedSlots` reads `garage.vehicles`, which hides retired vehicles | the "Add your <kind>" card returns | breaks "planned and not added yet" (SM-4) |
| any | delete | row gone, planned card returns | acceptable |

### M6. Onboarding and first run (`hasCompletedSetup`, `pendingFirstVehicle`, `plannedVehicles`, `@State page`)

`RootView`: `isAcceptingInvitation && vehicles.isEmpty` -> joining; `!hasCompletedSetup && vehicles.isEmpty` -> onboarding; else tabs. Any non-empty garage forces `hasCompletedSetup = true`. `finish()` sets planned kinds, `pendingFirstVehicle`, `hasCompletedSetup`. GarageView consumes `pendingFirstVehicle` once. No bad transition found; a purchase that succeeds and a kill before `finish()` re-enters onboarding with Pro on and the Continue button calls `finish()` (`OnboardingView.swift:483`).

### M7. Sharing (`SharingService`: `isAcceptingInvitation`, `share`, joined garages)

`accept`/`join` set `isAcceptingInvitation`, poll up to 60 s for the shared store to import, then clear it. Failures clear it and set `invitationError`. `leave` purges the local zone only. Device-local ledgers (`reviewedRecalls`, `recallCache`, `mutedVehicles`, `vinRecallChecks`) are keyed by vehicle id and never pruned when a vehicle is deleted or a garage left (leak, no user-visible effect found).

### M8. Recall watcher (`lastRecallCheck`, `recallCache`)

`record` writes the new list before `notify` runs, so a campaign that appears while notifications are off or undetermined is marked known and never pushed (P4). `lastRecallCheck` is stamped when any one vehicle was reached, so a vehicle whose request failed is not retried for 12 hours. Both are by-design trade-offs, in-app recall banner still shows the campaign.

### M9. Widget snapshot (`WidgetSnapshot`)

Written only from `GarageStore.publish()` (app launch, foreground, change). `statusRaw` and `dueDate` are frozen at write time; the widget re-reads the same snapshot at midnight (`KeyringWidget.swift:12-16`) and renders `days < 1` as "Today" (`:159`). A job that was due soon when the app was last opened reads "Today" in the due-soon colour forever after it passes, never "Overdue" (S3, code path). The background recall refresh does not call `publish()`.

### M10. Review prompt (`launchCount`, `lastReviewRequest`)

Asked after a logged service or a second vehicle, from launch 2, 30 day cooldown. `markAsked` is stamped before the system decides whether to show it; the system may show nothing, which costs the user the 30 days. Product call only.
