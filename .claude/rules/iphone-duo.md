---
paths:
  - "Keyring/App.swift"
  - "Keyring/Views/GarageView.swift"
  - "Keyring/Views/VehicleDetailView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Shared/Utilities/ScreenshotConfig.swift"
---

# iPhone Duo (2026-10-27)

- Unfolded (regular width, room for two panes of at least 360 pt), `MainTabView`
  puts the tabs (Garage, History, Settings) with their bar on the leading side
  of the fold and `VehicleDetailPane` on the trailing side: the garage beside
  the vehicle it has open. The pane shows the first vehicle until a key tag is
  tapped; the selected tag gets a brass ring. Fold edges come from
  `GeometryProxy.verticalFold()` (iOS 27.1 `reservedRegions(.division,
  .includeInactive)`), else an even split. The math is `UnfoldedSplit`, pinned
  by `UnfoldedSplitTests`. Folded, portrait unfolded (669 pt) and every other
  iPhone keep the single column.
- `VehiclePane` is in the environment only while split. That is how Garage's
  key tags (and notification routes) select into the pane instead of pushing.
  Opening the Duo with a vehicle pushed moves it into the pane and pops Garage.
- One view tree for both poses: folding only changes frames, so the tabs keep
  navigation and scroll. Never swap layouts with an `if` around the tabs.
- Each pane gets `horizontalSizeClass = .compact`, so it lays out as on a phone.
- Split, the system's floating glass tab bar is hidden and each tab carries
  `paneTabBar` (opaque, same tabs) as a bottom `safeAreaInset`, so every list
  scrolls its last row clear of it and nothing shows through. The bar spans
  the leading pane only.
- The trailing pane keeps horizontal bars (`toolbarVerticalBehavior(.disabled)`,
  iOS 27.1). Without it the status bar and the vehicle's Edit, More, back and
  + buttons sat in a column on the display's trailing edge, over the hero card
  and list rows (run 2, 2026-10-27). Apply it only to that pane.
- `paneTabBar` is topped by a 20 pt page-coloured fade inside the inset, so a
  key tag scrolling under the bar dissolves instead of being sliced mid-glyph.
- Folded, iOS 27.1 draws its own vertical rail (status bar, tabs, toolbar) on
  the outer display's trailing edge. That is the system default and unchanged.
- Unsigned simulator builds (gh-sim) have no iCloud entitlement and CloudKit
  traps on first touch; `CloudKitEntitlement.isPresent` keeps them local-only.
- Captures: `gh-sim all --device 'iPhone Duo' --args "-SeedDemo -DemoPro"` plus
  one `--screen "-DuoScreen <s>"` per surface: `garage`, `schedule` (Rebel's
  maintenance), `explore` (RAV4), `history` (History tab, Lake boat),
  `build` (Tacoma's build list pushed in the pane). `DuoScreen` lives in
  `ScreenshotConfig` (DEBUG) and maps to the existing `-ScreenshotRoute`
  behaviour through `ScreenshotConfig.route`. Never `--url`: iOS 27.1 raises an
  "Open in" alert for every custom-scheme link.
