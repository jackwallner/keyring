# iPhone Duo review, 2026-10-27

Source `f2751af`. Evidence: gh-sim run 4
`keyring@20261027-125947-5307-claude-mbpro25b51-1027-154022-14349` (GitHub Actions
40596594374, jackwallner/gh-sim): built, 121 unit tests passed (incl. 7
`UnfoldedSplitTests`), app still running at the end. Captures in
`captures-20261027/`: inner 2853x2007 landscape, outer 1398x2034, as captured
(no rotation or crop).

## Pane pairing

Leading pane: the tabs (Garage, History, Settings) with an opaque pane tab bar.
Trailing pane: the selected vehicle's detail, in its own navigation stack, so
a pushed screen (Build) stays in that pane. The open vehicle's key tag carries
a brass ring. Nothing straddles the fold.

## Store set (order, file, proposed header)

| # | File | Header |
|---|------|--------|
| 1 | `screen1-DuoScreen-garage-inner.png` | Every vehicle and what it needs, side by side |
| 2 | `screen2-DuoScreen-schedule-inner.png` | Service due dates set by how you ride |
| 3 | `screen3-DuoScreen-explore-inner.png` | Value, parts, how-tos and roadside in one tap |
| 4 | `screen5-DuoScreen-build-inner.png` | Track every mod and what it cost |
| 5 | `screen4-DuoScreen-history-inner.png` | Every service and fill-up, one shared log |
| 6 | `screen1-DuoScreen-garage-outer.png` | See which vehicle needs service next |

## Visual review of run 4 (inner)

- Two real screens on every surface, split at the reported fold; the fold band
  holds only page background and the pane's hairline.
- The pane tab bar is opaque and reserved as a bottom inset; list rows scroll
  clear of it and a 20 pt fade dissolves the card passing under it.
- iOS 27.1 draws the status bar and the vehicle pane's More, back and +
  buttons in a column on the display's trailing edge. The pane respects that
  inset, so no button sits over a card. Edit stays in the pane's own bar.
- No sheet, alert, paywall, empty state or transition frame. Data is
  `-SeedDemo -DemoPro` (in-memory, no RevenueCat or CloudKit).
- Known limitation: the trailing pane is about 370 pt wide after the system
  column, so two Explore tile subtitles truncate with an ellipsis ("Insurance
  and who t...", "Kelley Blue Book an..."), the same as on the folded display.

## Defects found and fixed

| Run | Defect | Cause | Fix |
|-----|--------|-------|-----|
| 1 | Test host and every launch crashed; captures showed the home screen | gh-sim builds unsigned, no iCloud entitlement; `CKContainer(identifier:)` traps | `CloudKitEntitlement.isPresent` reads the simulator executable's embedded entitlements; without it the app runs local-only (`d721849`) |
| 2 | Status bar and More button in a column over the hero card and rows | The pane ignored its trailing safe area | Reverted that ignore (`f2751af`) |
| 2 | Tacoma key tag sliced mid-glyph at the pane tab bar | Hard bar edge | Fade inside the bar's inset (`aeb0d82`) |
| 3 | White 42 pt strips at both display edges, narrower leading pane | `toolbarVerticalBehavior(.disabled)` letterboxed the scene | Removed it (`f2751af`) |

## Not done here

- No screen recording: recording inside `gh-sim all` blocked launch recordings
  in Iron Splits; the six-run budget went to fixes.
- Render and ASC staging need `render-duo-set` and `asc-stage-duo`, which live
  on the Air only.
- The 1.1 draft's APP_IPHONE_67 set is byte-identical to 1.0 (captured
  2026-10-19). Shot 02 shows the old Explore tiles (no Roadside, How-to). It
  needs a `shotflow` recapture from `keyring.json` on the Air.
