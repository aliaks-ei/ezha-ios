# Agent guide

Native SwiftUI app (`EZHA/`) with a shared package (`Packages/EZHAKit`). Product rules: `PRODUCT.md`. Build history and handoff: `PROGRESS.md`.

## Never open Xcode

Do every build, test, screenshot, and device install from the command line (`xcodebuild`, `xcodegen`, `xcrun simctl`, `xcrun devicectl`). Do not run `open *.xcodeproj` or `xed`.

## Checks after every change

1. Lint the Swift files you changed: `swift format lint --strict <files>`. Fix only your own lines; some older files have lint errors.
2. Build and run unit tests:
   `xcodebuild -scheme EZHA -destination 'platform=iOS Simulator,name=EZHA iPhone 17 Pro' -derivedDataPath /tmp/ezha-dd build test`
3. SQL changes: start the local stack and run the RPC checks (see the header of `supabase/tests/rpc_checks.sql`). Colima, not Docker Desktop: `colima start`, then `export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`.

## Checks after every UI change

Verify the change yourself before you report it as done. Do not ask the user to check it first.

1. Run the UI harness: `UITests/run.sh`. One class: `UITests/run.sh -only-testing:EZHAUITests/LibraryUITests`. Other Simulator: `DEVICE="iPhone 17" UITests/run.sh`.
2. Add or update a test in `UITests/` for the changed behavior. Call `capture("<name>")` on each changed screen. Capture light, dark (`launch(..., dark: true)`), and largest text (`launch(..., large: true)`).
3. Open the PNGs in `UITests/.output/screenshots/` with the Read tool and look at them: clipped text, overlaps, wrong colors in dark mode, controls under the keyboard.
4. Report which tests ran, pass or fail, and what you saw in the screenshots.

### How the harness works

- `UITests/project.yml` builds the app's views (`EZHA/`, without `EZHAApp.swift`) into `HarnessApp`, with fixture clients and no network. `run.sh` regenerates `UITests/EZHAUITests.xcodeproj` with `xcodegen`; the project and `.output/` are git-ignored.
- `HarnessApp.swift` picks the screen from `HARNESS_SCENARIO`: `today`, `libraryTab`, or a logger state from `LoggerFixtures.state` (`entry`, `review`, `multiple`, `label`, `library`, `failure`). Add a scenario there for a new screen.
- `Fixtures.swift` holds the fixture data, for example `LoggerFixtures.libraryFoods()`.
- Tests subclass `HarnessTestCase` (`launch`, `capture`). Find elements by accessibility identifier where possible.
- The harness does not cover the live backend, sign-in, camera, or widgets. Say so when a change depends on them.

## Device

Build and install on the connected iPhone without Xcode (Personal Team; `EZHA-Dev.entitlements` drops Sign in with Apple):

1. `xcrun devicectl list devices` to get the device identifier and check it is available.
2. `xcodebuild -scheme EZHA -destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates -derivedDataPath /tmp/ezha-device CODE_SIGN_ENTITLEMENTS=EZHA/EZHA-Dev.entitlements build`
3. `xcrun devicectl device install app --device <device id> /tmp/ezha-device/Build/Products/Debug-iphoneos/EZHA.app`
4. `xcrun devicectl device process launch --device <device id> com.aliaksei.ezha`

## Backend

- Migrations live in `supabase/migrations/`. Keep them additive, so older app builds and the PWA keep working.
- Apply a migration to the remote project (`supabase db push`) before you install an app build that needs it.
