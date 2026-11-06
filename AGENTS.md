# Agent guide

Native SwiftUI app (`EZHA/`) with a shared package (`Packages/EZHAKit`). Product rules: `PRODUCT.md`.

## Never open Xcode

Do every build, test, screenshot, and device install from the command line (`xcodebuild`, `xcodegen`, `xcrun simctl`, `xcrun devicectl`). Do not run `open *.xcodeproj` or `xed`.

## Checks: run only what the change touches

Run the checks for the files you changed, not every check. Aim for the fastest check that proves the change. Run the cheap checks first: lint, then backend tests, then unit tests, then UI tests.

| You changed | Run |
|---|---|
| Docs, comments, `AGENTS.md` | Nothing |
| Any Swift file | `scripts/lint-changed.sh` |
| `supabase/migrations/`, RPCs | RPC checks (below) |
| `supabase/functions/<name>/` | `supabase/scripts/test-functions.sh <name>` |
| `Packages/EZHAKit` | Unit tests (below) |
| A screen in `EZHA/Features/` | Build, unit tests, and the UI test class for that screen |
| Shared UI (`EZHA/DesignSystem/`) or `UITests/` harness files | Build, unit tests, and the UI classes that use it |

### Commands

- **Lint:** `scripts/lint-changed.sh` lints the changed and new Swift files. It fails only when a file has more errors than at `HEAD`, because some older files have lint errors. Fix only your own lines. One file: `swift format lint --strict <file>`.
- **Build and unit tests:** `xcodebuild -scheme EZHA -destination 'platform=iOS Simulator,name=EZHA iPhone 17 Pro' -derivedDataPath /tmp/ezha-dd build test`. `build test` builds once; do not run `build` first. While you iterate on one suite, add `-only-testing:EZHAKitTests/<Suite>`; run all unit tests once at the end.
- **Edge Functions:** `supabase/scripts/test-functions.sh ai-estimate` runs `deno check`, `deno test`, and `deno fmt --check`. With no name, it checks the functions changed against `HEAD`. Without a local `deno`, it uses the `denoland/deno` Docker image, so Colima must run.
- **RPC checks:** `colima start`, `export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`, `supabase start`, `supabase db reset`, then run `supabase/tests/rpc_checks.sql` as its header shows. Use Colima, not Docker Desktop. Add a check there for each new column or RPC behavior.

### Environment

- The Simulator (`xcodebuild test`, `xcrun simctl`, `UITests/run.sh`), Docker, Colima, and `supabase` do not work in the agent sandbox. Run them outside the sandbox from the first attempt.
- When a test fails, check whether it also fails on `HEAD` before you change it: `git worktree add --detach /tmp/ezha-head-check HEAD`, run the same test there, then `git worktree remove --force /tmp/ezha-head-check`. Report a failure that also occurs on `HEAD` as an existing failure.

## Checks after every UI change

Verify the change yourself before you report it as done. Do not ask the user to check it first.

1. Run the UI harness for the changed screens only: `UITests/run.sh -only-testing:EZHAUITests/LibraryUITests` (one class) or `-only-testing:EZHAUITests/LoggerUITests/testName` (one test). Do not run the full suite (`UITests/run.sh` with no filter) for a scoped change. It is slow. Run it only for a change to shared UI or the harness itself. Other Simulator: `DEVICE="iPhone 17" UITests/run.sh`.
2. Add or update a test in `UITests/` for the changed behavior. Call `capture("<name>")` on each changed screen. Capture light, dark (`launch(..., dark: true)`), and largest text (`launch(..., large: true)`).
3. Open the PNGs in `UITests/.output/screenshots/` with the Read tool and look at them: clipped text, overlaps, wrong colors in dark mode, controls under the keyboard.
4. Report which tests ran, pass or fail, and what you saw in the screenshots.

### How the harness works

- `UITests/project.yml` builds the app's views (`EZHA/`, without `EZHAApp.swift`) into `HarnessApp`, with fixture clients and no network. `run.sh` regenerates `UITests/EZHAUITests.xcodeproj` with `xcodegen`; the project and `.output/` are git-ignored.
- `HarnessApp.swift` picks the screen from `HARNESS_SCENARIO`: `today`, `libraryTab`, an editor (`foodEditor`, `drinkFoodEditor`, `mealEditor`, `drinkQuickLog`), or a logger state from `LoggerFixtures.state` (`entry`, `review`, `multiple`, `label`, `drink`, `library`, `failure`).
- `Fixtures.swift` holds the fixture data, for example `LoggerFixtures.libraryFoods()`.
- Tests subclass `HarnessTestCase` (`launch`, `capture`). A new `UITests/<Name>UITests.swift` file is found automatically; other new test-target files must be added to `project.yml`.
- `run.sh` fails when no test ran, for example when an `-only-testing` name is wrong.
- Find elements by accessibility identifier. Text matches break: `LabeledContent` replaces the label of the field inside it, and iOS 26 does not upper-case `Form` section headers. When you must match text, match case-insensitively (`label ==[c] %@`).
- For a new state, add a scenario in `HarnessApp.swift` and its data in `Fixtures.swift`. Do not change existing fixtures that other tests use.
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
