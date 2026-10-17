# Contributing to Avo

Thanks for helping Avo grow! Small fixes and big ideas are both welcome.

## Requirements
- macOS 14 or newer
- Xcode (the full app, opened once)

## Build and run
- Open `Avo.xcodeproj` in Xcode and press Run.
- Or from the terminal: `xcodebuild -scheme Avo build`
- Run the tests: `xcodebuild -scheme Avo test`
- Install your build to /Applications: `./install.sh`

A Debug build adds a **Debug** submenu to the menu bar menu. It shows the engine's state and lets you make a nudge come due in 20 seconds and press the card's buttons, so you don't have to wait 25 minutes.

To check the card visually, render every state to PNG: `TEST_RUNNER_AVO_SNAPSHOTS=1 xcodebuild -scheme Avo test` writes them to `build/snapshots/`.

## Project layout
- `Avo/App`: app entry point and wiring
- `Avo/Engine`: the pure scheduler state machine, exercise picker and work hours
- `Avo/System`: sensors (camera, mic, full-screen, idle) and the login item
- `Avo/Model`: shared value types
- `Avo/Settings`: the Settings window
- `Avo/Menu`: the menu bar menu
- `Avo/Card`: the nudge card, a non-activating floating panel
- `Avo/Persistence`: daily history, streak and move rotation, as JSON in Application Support
- `Avo/Theme`: design tokens (colours, fonts)
- `Avo/Assets.xcassets`: pose and face art, menu bar and app icons
- `AvoTests`: unit tests
- `design/art/`: Avo's pose and face art (SVG), the app icon and the social preview
- `docs/SPEC.md`: the source of truth for behaviour, timing and copy

## Code style
- Swift 6, main-actor-by-default.
- Prefer value types and pure logic for anything you want to test.
- Tests use Swift Testing.
- No third-party dependencies.
- No network calls or analytics. Ever.
- UI copy must match the spec.
- The nudge panel stays non-activating. It must never steal keyboard focus.
- Build with zero warnings.

## Proposing behaviour changes
Open an issue first if it is a big one. If you change behaviour, timing or copy, update `docs/SPEC.md` in the same PR.

Happy stretching!
