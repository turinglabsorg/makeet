# App developer procedure

Makeet ships native Apple apps: the iOS 17+ app, the macOS 14+ companion and their widgets. A native Android client is under `android/`; see `docs/android.md` for its separate Play release gates. Read `AGENTS.md` and `DESIGN.md` first; `docs/ci.md`, `docs/validation.md` and `docs/release-readiness.md` hold the detailed evidence.

## Environments

- A Mac with Xcode 27 can build, run the Simulator, sign and test on a connected iPhone.
- An agent without Xcode edits Swift and runs `python3 scripts/ValidateLocalizations.py` and the Go backend tests locally, then verifies native changes through GitHub Actions on a branch.

## Build and test

- Regenerate the project with `xcodegen generate` after changing `project.yml`.
- On a Mac: `swift test --disable-sandbox`, then the `Makeet` scheme on an iOS 27 Simulator (commands in `README.md`).
- `Verify Makeet` runs on every push and pull request: package tests, catalog and compiler-extraction coverage, iOS and macOS builds, Go race tests and vet.
- `Simulator tests` runs the complete `Makeet` scheme on every branch except `main`. Download its result bundle and screenshots with `gh run download <run-id> -n simulator-tests` and inspect the affected screens before merging.
- Xcode Cloud runs the required scheme and the archive on `main`; a failed test blocks distribution.

## Signing

- The project stores no personal team. Xcode Cloud archives with automatic Apple-managed signing; GitHub Simulator runs sign ad hoc.
- The app and both widgets share App Group `group.org.turinglabs.makeet`. Debug uses development APNs and Release uses production APNs.

## Authentication

- Accounts retain Apple and Google identities and add verified username/password credentials through the same Go session service. Android does not expose Apple sign-in. Never add a test-token login to production. See `docs/password-accounts.md`.
- UI tests use `--ui-testing` (in-memory archive) and the Debug-Simulator `--profile-fixture` and `--password-fixture` with an `.invalid` host. They never touch Keychain sessions, real account stores or the public API.
- Real provider, multi-device and deletion checks use a disposable account on a signed device, never the owner's account.

## Screenshots

- Product and Store screenshots use `--demo`, which seeds labeled sample data into an empty archive. Never show real account data.
- XCTest attachments from the Simulator workflow are the review evidence for changed screens. Check narrow phone widths, the keyboard, scrolling, system bars and bottom controls.

## Distribution and release evidence

1. Work on a branch until `Verify Makeet` and `Simulator tests` pass and the screenshots are reviewed.
2. Merge to `main`; Xcode Cloud builds, tests, archives and distributes to the owner-only Makeet Internal group.
3. Record the cloud build number, completed test action and processed TestFlight build in `docs/validation.md`.
4. Submit for App Review only after the checks in `docs/release-readiness.md` pass. Release is manual. Report TestFlight availability, review submission, approval and store publication as separate states.

## Backend deployment

The Go service runs on the Mac Pro from a dedicated service directory outside this repository, with private runtime configuration and credentials injected through hush. Build from a clean `main` commit with `GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -trimpath ./cmd/makeet`, keep the previous binary for rollback, restart the service and verify `https://api.makeet.app/healthz` and the affected public routes.
