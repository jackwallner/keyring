---
paths:
  - "Keyring/App.swift"
  - "Keyring/Views/Components.swift"
  - "Keyring/Views/PaywallView.swift"
  - "Keyring/Views/OnboardingView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Shared/Utilities/DeviceName.swift"
  - "project.yml"
---

# iPad layout (1.2)

iPad is native: `TARGETED_DEVICE_FAMILY "1,2"`, all four orientations
(`UISupportedInterfaceOrientations~ipad`), Split View and Slide Over allowed.

- The garage-beside-the-vehicle layout from the iPhone Duo is the iPad layout
  (see `iphone-duo.md`). `UnfoldedSplit.make(isPad: true)` keeps the leading
  pane a phone-width list (36% of the width, 380 to 440 pt) and gives the
  vehicle the rest. Regular width of 720 pt or more splits: every iPad in
  portrait or landscape, and a 13-inch in a two-thirds Split View. Narrower
  windows (half of a 13-inch landscape, Slide Over) stay one column.
- Both panes are forced to `horizontalSizeClass = .compact`, so every screen
  lays out as on a phone. Width is capped by `paperBackground()`, which applies
  `readableColumn()`: `contentMargins(.horizontal, ..., for: .scrollContent)`
  centres scroll content in `Theme.columnWidth` (680 pt). Only the content is
  inset, so bars, scroll indicators and paper stay full width. Any new
  screen that skips `paperBackground()` must call `readableColumn()` itself.
- Paywall and onboarding cap their column at 560 pt. Sheets are the system's
  form sheet on iPad, so detents are ignored there; leave them.
- Copy that names the device uses `DeviceName.current` ("iPhone" or "iPad").
  Never hardcode "iPhone" in a user-facing string.
- The print panel is a popover on iPad and is anchored to the window centre
  (`ServiceRecordView.print`). `ShareSheet` and `UICloudSharingController` are
  presented as sheet content, which iPad accepts without a source view.
- Captures: `gh-sim launch --device "iPad Pro 13-inch (M5)"` with the same
  `-SeedDemo -DemoPro` and `-ScreenshotRoute` launch arguments as the iPhone
  set. App Store set is 13-inch iPad, 2064x2752.
