# Play listing assets

Staged for `play_stage.py`. Nothing has been uploaded to Play.

- `metadata/android/en-US/`: `title.txt` (29 chars, the live App Store name), `short_description.txt` (77),
  `full_description.txt` (about 2,100, plain text). Copy came from the earlier Android listing draft; no health claims.
- `listing/console-notes.md`: category, contact, privacy URL, Data safety, App access and content rating notes for the Console forms.
- `icon-512.png`: the iOS app icon (`Keyring/Assets.xcassets/AppIcon.appiconset/AppIcon.png`) resized with `sips -z 512 512`; RGB, no alpha.
- `feature-graphic.svg` / `feature-graphic.png`: 1024x500. The SVG embeds the 512 icon (rounded) beside the name and tagline on the
  icon's green. Rendered with headless Chrome:
  `chrome --headless=new --force-device-scale-factor=1 --window-size=1024,500 --screenshot=feature-graphic.png file://$PWD/feature-graphic.svg`.
  The PNG is RGB with no alpha.
- `screenshots/`: five 1080x2160 captures from the debug build on emulator `agent-emu-1` (API 36, `wm size 1080x2160`) with
  status bar demo mode (10:00, full Wi-Fi, full battery, no notifications). Launched with
  `am start -n com.jackwallner.keyring/.MainActivity --ez seedDemo true --ez demoPro true --ez skipOnboarding true --ez previewStore true --es route <route>`
  (routes: none for garage, `vehicle`, `history`, `recalls`, `value`). Pro comes from the debug-only `demoPro` path, with the
  Test Store key and no production RevenueCat key. `screencap` PNGs are RGBA, so `tools/strip_alpha.py` rewrites them as 24-bit RGB.
  Names: `01-garage`, `02-schedule`, `03-history`, `04-recalls`, `05-value`.
