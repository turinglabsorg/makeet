# Validation

Validated on 16 October 2026 using Apple Swift 6.4, an iPhone 16 Pro Simulator running iOS 18.5, and the installed macOS SDK.

## Verified behavior

- 18 Swift Package Manager tests cover quantitative logging, extra activity beyond a target, day boundaries around both daylight saving transitions, observed-day denominators, current/best streaks, invalid entries, scheduling collisions, historical preferences, exhausted availability, persistence between independent model containers, corrections limited to the chosen habit and its local day, decimal rounding, and composed emoji validation.
- Simulator UI tests cover creating a habit, repeated increments, undo, archiving/restoring, demo navigation, and truthful connection status.
- A Simulator-only EventKit integration test creates an isolated temporary calendar, creates a real event, repeats the request without duplicating the event, recognizes the planned habit, and rejects a conflicting second block. The temporary calendar is removed at the end of the test.
- The iOS application and its WidgetKit extension compile.
- The macOS application and its native WidgetKit extension compile.
- Today, Trends, and Connections have been inspected using rendered Simulator screenshots. Demo data is labeled in the interface and the screenshots.

## Boundaries

CloudKit is explicitly disabled in the shipped configuration. Multi-device synchronization, real Google account synchronization, physical-device permission prompts, App Store provisioning, native macOS runtime behavior, and widgets on a Home Screen or Mac desktop have not been validated. They must not be inferred from successful compilation or shared-store integration tests.

The initial calendar integration creates confirmed time blocks and refreshes availability. Moving/canceling existing plans and complete bidirectional provider reconciliation remain product milestones.

## Push foundation verification

- Five Simulator-hosted tests cover no prompt during refresh, explicit consent, refreshed tokens, denied/revoked permission, APNs registration failure/retry, and permission-request errors.
- The Connections UI scenario confirms the notification permission row exists and no system alert appears on opening the screen.
- Both platform applications and widget extensions compile with APNs configuration. These unsigned builds do not establish provisioning or APNs delivery.
- A topic-specific Sandbox provider key has been created and encrypted through hush. Authenticated device registration, scheduling, production credentials, and delivery to a signed installation remain unverified.

## Quantity controls, appearance, and languages

Four Simulator UI scenarios verify left-minus/right-plus ordering, decrement to zero, disabled empty-state controls, creation using an emoji, existing detail undo/archive/restore, and localized navigation/creation in Italian, English, French, German, and Spanish. Screenshots of all five languages were rendered; the German layout and emoji creation were visually inspected.

Native catalogs contain 203 keys across the interface and permission descriptions. Validation checks all five translations, interpolation types, and coverage against compiler-extracted app/widget strings. User-authored names and units are preserved. Additional languages can be added in Xcode's string catalogs without new runtime branching.

Development-signed build 0.1.0 (2), containing these changes, was installed as an update and launched on the owner's physical iPhone. The existing app data container was retained. Physical widget placement, widget button interaction, and complete device permission/calendar flows remain separate checks.

## Public service and website

The embedded Go site passes HTTP integration tests for all five languages and page states. Desktop and iPhone-width layouts, the German interface, language switching and native FAQ expansion were inspected in the browser. Go race integration tests and vet pass.

The dedicated persistent Mac Pro process serves the public website and API through valid HTTPS at `makeet.app` and `api.makeet.app`. Public health returns `ok`; provider configuration returns an empty list, so public sign-in/registration is not enabled. SQLite uses a private directory and 0600 database permissions. The website labels development screenshots and unfinished integrations. Legal pages return 503/noindex until launch requirements are met.

The iOS App Store Connect record exists with version 1.0 in preparation. No TestFlight upload, App Review submission or store publication is verified by this infrastructure work.

## Apple account lifecycle

Go HTTP/database integration tests verify authorization-code identity binding, encrypted grant custody, rejection under the wrong account/audience, a failed provider revocation preserving the account and records, and successful revocation followed by complete deletion. Additional checks reject altered ciphertext, invalid signing/encryption configuration and provider redirects that could disclose credentials. Existing identity/session/sync integration tests still pass under the race detector, and vet passes. These tests use generated signing fixtures; real Apple login/revocation is not yet verified.

## Native account foundation

32 Swift package tests pass, including real local HTTP checks for concurrent refresh, rotation persistence failure, sign-out during refresh and expected-account rejection. Disk-store checks cover account separation and stale widget scope rejection. Ledger tests cover persistence/retry identity, in-flight edits, independent activity UUIDs, bounded batches, latest revisions and explicit conflicts. Both iOS and macOS apps/widgets compile with Google SDK 9.1.0; the Connections UI scenario and account status in all five languages pass on iPhone Simulator. Public registration stays disabled, so these are not real provider or multi-device account-sync results.

Build 0.1.0 (3) is installed and launched on the connected physical iPhone, preserving the existing archive. Real provider sign-in remains disabled on the public service. A separate regression confirms a widget correction is respected even when the app previously loaded that activity.

## Accounts, push and release policies

- 33 Swift Package tests now pass, including real HTTP tests of refresh serialization, account ownership guards, sync ledger persistence/conflicts, archive isolation and the push registration/test/receipt wire protocol.
- Six Simulator notification tests pass, including receipt deduplication. The latest Connections UI scenario passes; app and widget builds pass for iOS and macOS. A development Google SDK umbrella-header warning remains in its upstream macOS headers.
- Go race tests and vet pass. HTTP integration tests cover encrypted device ownership, account/token transfer, logout/deletion/revocation isolation, push idempotency/rate limits/retries, Apple acceptance versus receipts, rejected tokens, refreshed-token races, daily reminder completion/time-zone/deduplication and activity query indexing. Generated provider fixtures do not prove live Apple/Google authentication or APNs delivery.
- Legal pages are tested in five languages, including strict controller-line isolation to privacy and fail-closed partial configuration. Desktop rendering was inspected with a fictional controller. The operator confirmed primary hosting in Italy.
- Backup snapshot/restore/rotation tests pass. The Mac Pro deployment has a daily isolated backup job and passed an isolated restore integrity/foreign-key/table-count drill. Apple iOS and Google identity access are now enabled for live validation after trusted relay rate-limit checks. Actual sign-in/revocation, multi-device sync and APNs device receipt remain unverified.

## Explicit language choice and live account entry

- An iOS UI test changes the language from Italian to English and French inside the app, verifies account copy, and confirms persistence after relaunch. The five-language Account UI test passes after the change. The catalog has 256 translated keys with compiler extraction coverage.
- Today has a direct Sign in/Account entry. Build 0.1.0 (5) is signed and installed on the connected iPhone. Actual phone launch/sign-in still requires unlocking and completing the provider consent on the device.
- Makeet-only ingress tests verify Cloudflare peers, valid single client-IP headers, removal of spoofed forwarding headers, IPv6, preserved request bodies, and byte-for-byte unchanged behavior for unrelated hosts. Actual HTTP tests verify per-client limits and reject untrusted-header attempts to reset them. Public HTTPS health is 200; direct origin requests are 403.
- Google consent is External / In production with the approved support contact and public site/policy links. The backend advertises Apple and Google; only live provider testing can establish successful authentication.

## Onboarding and current device issue

- First-run onboarding introduces quantities, trends and confirmed planning, then requires an explicit account or local-only storage choice. Account selection opens a dedicated sign-in screen; users can return to local mode. No calendar/notification prompt is shown during onboarding. Language and policy links are available immediately.
- Simulator UI tests pass for all five onboarding languages and for the explicit choice, optional account path, return to local mode and persistence after restart. Screenshots were inspected; weak contrast and German truncation were corrected. The catalog has 280 translated keys with compiler extraction coverage. iOS device build 6 and macOS builds succeed.
- Build 5 on the physical iPhone was reported to crash around the first Apple login. Read-only backend counts confirm one account, Apple grant and session, with no synchronized records or registered push device. The exact crash cause is not yet known. The device lists the Makeet crash report from 15:56, but transferring it requires the phone to remain connected and unlocked.
- Build 5 executable/debug-dylib symbols were preserved for symbolication. Build 6 is prepared but has not been installed; do not infer that onboarding changes fix the reported crash. Real device activation and notification receipt remain release blockers.

## Apple login archive-transition crash correction (2026-10-17)

The physical build 5 report was retrieved and symbolicated against its preserved debug-dylib UUID. The main-thread SwiftData assertion originates in `Habit.colorIndex`, called by `HabitCard.tint` inside the deferred GeometryReader layout after replacing the local archive during successful Apple authentication. A Simulator regression constructs a card, releases its ModelContainer and then renders it. The original implementation triggers the fatal SwiftData BackingData reset assertion; the corrected implementation renders successfully using immutable habit, appearance and activity snapshots. Persistence-backed models are retained only for current navigation/actions, not deferred drawing.

The detached-card regression, quantitative creation/logging/decrement/undo/archive flow and explicit onboarding/account-to-local/persistence tests pass in `CardCrashFixed.xcresult`. Localization validation covers 275 extracted keys and 280 five-language catalog entries. Corrected development build 0.1.0 (6) was signed, installed as an update and launched on the physical iPhone. A physical-only UI smoke test launches without test-data arguments, restores the existing Apple account, opens Account settings and verifies the last successful synchronization indicator; it passes in `PhysicalAccountRestored.xcresult`. Server counts confirm the session renewed without uploading records. No archive, account or Keychain data was deleted. A fresh Apple confirmation and Google login, multi-device progress sync and actual push receipt remain distinct release checks.

Google SDK URL callbacks are now handled above both onboarding and RootView. The explicit onboarding/account-to-local/persistence UI test passes after moving that handler. This verifies the UI boundary remains functional; an actual Google authentication flow is still required. The verified physical crash-correction build is unchanged while the owner repeats Apple confirmation.
