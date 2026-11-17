# Pre-submit review, 1.1.3 (build 26), 2026-11-07

Scope: app sources changed since the live version 1.1.2. The last `project.yml` change at 1.1.2 is `dcf314b` (build 25); HEAD is `821ef44` (1.1.3, build 26). Docs, fastlane, qa, tests and `android/` excluded.

Changed files: `Keyring/Views/AddVehicleFlow.swift`, `GarageView.swift`, `OnboardingView.swift`, `SettingsView.swift`, `KeyringWidget/KeyringWidget.swift`, `Shared/Services/GarageStore.swift`, `StoreService.swift`, `WidgetSnapshot.swift` (108 lines added, 34 removed). Every change comes from the 2026-11-06 state machine fixes (`state-machines-2026-11-06-fixes.md`).

Checked, no defect found:

- Crashes and data loss: no force unwraps, indexing or new model attributes. `WidgetSnapshot.Item` only gained a method, so snapshots written by 1.1.2 still decode. The odometer fallback (`resetReadingToHighestKnown`) only runs when the deleted or edited entry or reading was the source of the vehicle's reading. Starting odometers have always had a `MeterReading` row (`b142f6f` onward), so deleting the first entry cannot drop a vehicle to 0. `PlannedVehicles.remaining(_:in:)` is `@MainActor` and its only caller is `GarageView`.
- Purchases: `paymentPendingError` maps to `.pending` with no error message. The paywall (`PaywallView.swift:195`) and onboarding (`OnboardingView.swift:496-506`) already show the pending copy. Cancelled and failed paths are unchanged. `isPro`, restore, offering lookups and the paywall's Terms of Use, Privacy Policy and Restore links are untouched.
- State: Edit vehicle's miles/km switch no longer stamps a reading. Same-unit edits still compare against the shown reading, and a rounded figure counts as untyped. The Settings reminders row refreshes on `scenePhase == .active`. A sold or retired vehicle keeps its onboarding slot crossed off. The widget works out status from `.now` on its midnight reload, and no meter-only or no-record job changes status.
- App Review: no new strings with prices, platforms or health claims. The `$` figures in `StoreService` fixture products only compile for the simulator (`#if targetEnvironment(simulator)`, `StoreService.swift:424-512`).

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P2 | `Shared/Services/GarageStore.swift:800` (with `:712`) | `correctReading` (Edit vehicle) removes saved readings above the corrected figure but leaves logged entries above it. The new highest-known fallback can then bring the typo back. Example: a fill-up typed as 54,000, odometer corrected to 52,000 in Edit vehicle, a later fill-up at 52,500 logged on the wrong vehicle and deleted. The odometer now reads 54,000 (1.1.2 left it at 52,500). It needs a typo left in an entry plus a correction plus a delete of the source entry or row. Jobs show earlier than they should, and editing the typo entry fixes it. | Not fixed: there's no rule that tells a corrected figure from a normal lower "past reading", since both are saved as a `MeterReading` dated now. Picking which figure wins is a design decision. |

Tests: `gh-sim test --scheme Keyring --only KeyringTests`, run `keyring@20261107-222753-21e8-claude-mbpro388d6-1107-223033-31498` (GitHub Actions 42455041445): built, 174 passed, 0 failed.
