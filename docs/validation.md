# Validation

The sections below record successive validation stages. The final dated section describes the latest verification and remaining release boundaries.

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

## Complete archive transition on iOS 27 (build 7)

The owner reported a second failure after build6. Its exact symbols identify `Habit.id` -> `Habit.snapshot` -> `HabitCard.init` inside a deferred Today ForEach factory. The earlier detached-card regression did not cover construction after archive replacement. Restored-account smoke tests also did not exercise a new login.

A dedicated iPhone16Pro Simulator running iOS27.0 was installed; the physical phone runs27.0.1. The revised regression opens Account settings, alternates populated and empty archives while the view hierarchy is mounted, and reproduces the same SwiftData reset assertion on both18.5 and27.0 before the structural correction. `ArchiveHost` now retains a container in view state inside its own identity boundary, so old sheets and lazy factories keep their original store until their graph is removed. The corrected iOS27 regression passes through six replacements and confirms retired stores are released after removing the hosting hierarchy.

`ArchiveIOS27Lifetime.xcresult` passes both lifecycle tests. `Build7IOS27UI.xcresult` passes creation/quantity/decrement/undo/archive, explicit account/local onboarding and persistence, all five onboarding languages and language-selection persistence. iOS device and macOS builds succeed. Build7 is prepared; actual new provider confirmation and TestFlight delivery remain unverified.

The Xcode Cloud post-clone hook executed successfully with the real local SDK/catalog/package commands (33 package tests). The post-xcodebuild hook validates 275 compiler-extracted keys against280 translated keys and supports separate test workers. Cloud setup is in progress; no successful cloud upload or internal TestFlight availability is claimed.

## Complete iOS 27 scheme and cloud bootstrap (2026-10-17)

The complete Makeet scheme passes on iPhone 16 Pro / iOS 27.0: 16 tests passed, no failures, and two deliberate skips. The physical-account smoke test skips Simulator; the isolated EventKit integration skips without calendar authorization. This run includes both archive-lifetime regressions, all notification tests and the full UI suite. It does not establish a new physical Apple confirmation, live Google authentication or APNs delivery.

The first Xcode Cloud build of the archive-lifetime correction succeeded. Logs confirm the actual post-clone catalog/package checks, dependency resolution, iOS compilation, scheme cataloging and post-build compiler-string validation passed. The workflow now has required iOS 27 tests, an App Store Connect archive and owner-only internal TestFlight distribution. A particular TestFlight build must still be verified as processed and available before claiming delivery.

The detached-card fixture creates its archive in a non-inlined autorelease pool with autosave disabled. A bounded XCTest predicate expectation observes actual release while queued framework ownership drains, preserving the weak assertion before rendering. Five repetitions of both lifecycle tests pass on iOS27 (ten executions, zero failures). A sensitivity check that temporarily restores persisted-model color access still triggers the original BackingData fatal error; the production snapshot implementation passes. This is separate from the mounted archive-transition regression, which verifies store retention through complete view teardown.

## First internal TestFlight delivery (2026-10-17)

Cloud build 2 passed its required iOS27 test action and archive action. After its one-time export questionnaire was completed, processed TestFlight build 0.1.0 (2) became available with Testing status in the owner-only internal group. The sole tester shows Invited. This build contains the ArchiveHost correction; a fresh physical Apple confirmation remains to be checked by the owner. The later build 3 was not distributed because its detached-card fixture release assertion failed. The fixture repair preserves the assertion and the required CI test gate.


## Guided welcome and private profile

The owner confirmed successful installation and fresh Apple authentication on TestFlight0.1.0(2), without the reported crash. Cloud4 then passed its required iOS27 tests, archive and automatic internal TestFlight postaction for8336a82.

Onboarding version2 introduces a labeled day preview, explicit account/local choice, balanced provider buttons and a final guide. Completion remains explicit and language persists; an update presents the guide once while retaining any existing session and archives. The step survives container replacement. Profile photos/names are private account data, imported from Google only for an empty profile or chosen through the system photo picker. Client downsampling and server JPEG reencoding remove metadata.

HTTP/database race tests cover ownership, a second session reading the same profile, stale revision rejection, photo removal, invalid image/name rejection and deletion cascade. The native account-client HTTP fixture verifies photo bytes, revision conflicts and account guards;34 package tests pass. iOS27 UI tests pass in all five languages for the onboarding/account choice/provider button widths and local completion/persistence. Native tests verify image bounds/metadata removal and account cache isolation; both original archive-lifetime regressions still pass. Actual edits and photo receipt on multiple signed devices remain to be checked.


The complete local iOS27 scheme passed every native test and all UI flows except the original Connections test's assumption that notification status was initially onscreen. The test now scrolls after checking the account summary, matching the taller account presentation. That corrected UI check and both profile tests pass in ProfileFinalChecks.xcresult; the final macOS build succeeds. Five-language compiler coverage validates294 extracted keys against313 catalog entries. Existing Simulator/permission guards remain unchanged; no required test was disabled to distribute the change.

The profile backend is deployed with schema4 and a verified backup/rollback binary. Local/public health returns200, anonymous profile requests return401, and all15 public policy routes return200 with the profile notice translated in all five languages. The existing runtime identity configuration and credentials were preserved. User-created profile updates on a signed device remain a device check.


## Profile presentation and statistics regression coverage (2026-10-18)

A signed-in Debug Simulator UI fixture reproduces Edit profile closing Account and returning to Today on iOS27. The editor is now presented by the stable Connections navigation container instead of a Form Section; account confirmation dialogs use that same container. Name, photo and original revision remain view state throughout an edit. A stale retry cannot adopt a freshly fetched remote revision and overwrite another device's update. Saving dismisses the keyboard so a failure remains visible.

Required UI coverage now opens the editor from Today and Planner, saves/cancels/reopens, checks relaunch persistence, retains a failed-save draft, rejects stale retries, edits during the authenticated update guide, and selects/removes a system photo. The fixture intercepts only its own .invalid host and uses temporary profile storage; it never uses Keychain, real archives or the public API. It is compiled out of device/Release builds, verified by absent binary markers.

The added demo-statistics UI test exposed a main-thread stall: each hourly-chart activity predicate recalculated the complete statistics history. Detail now builds immutable snapshots/statistics once per render. The domain engine aggregates valid entries once by habit-local day and returns selected-window hourly registration counts. Tests preserve lifetime streaks, selected-period totals, invalid/other-habit filtering and both repeated DST hours. A fixture with 2,500 days and 10,000 registrations passes across 7-, 28- and 84-day windows.

The complete initial iOS 27 scheme executes 25 tests: 23 pass and two retain their deliberate guards (physical-device smoke test and calendar permission); after enabling only the dedicated Simulator's calendar, the isolated EventKit creation/idempotency/conflict test also passes. Profile checks pass with network failures and conflicts. The final focused UI checks pass for 7-, 28- and 84-day changes and account confirmation cancellation; iOS27 uses a dismissible popover that may omit a Cancel button. 36 Swift package tests, Go race tests and vet pass; iPhone Release and native macOS/widget builds succeed. Catalog validation covers 294 extracted keys and 313 entries in five languages. Real Google authentication, signed multi-device updates and actual device delivery remain separate release checks.


## Weekday schedules, calendar history and permanent deletion (2026-10-18)

The additive weekday mask preserves daily behavior for older archives and JSON. An actual disk archive generated using the preceding model schema migrated with its habit/activity IDs and quantities intact; weekday edits persisted afterward. Package tests cover rest-day streaks/denominators, DST-aware future ranges, legacy decoding, combined calendar intensity, stale/atomic past-day corrections, reopening, permanent deletion and orphan prevention. The package now passes 46 tests, including authenticated subscription/export HTTP wire and account guards.

The iOS27 runtime paths cover weekday selection/empty-selection rejection/persistence/editing, plus-left/avatar-only-right navigation, archive in settings, monthly calendar/day correction/save/cancel/Today isolation, permanent deletion review/cancel/confirmation/navigation, future-plan horizon/review/cancel, and missing calendar configuration. Configured calendars show no redundant connected banner. Calendar configuration is tested through reachable selection controls, rather than requiring a noninteractive status label to be hittable beneath the navigation bar.

Isolated EventKit tests create future batches on selected weekdays, reject atomic conflicts, deduplicate repeated writes, read recurring/all-day/past-month events, and remove only confirmed future Makeet-linked events while preserving unrelated entries. Device-calendar account synchronization remains OS-owned; real Google calendar and device checks are distinct.

Native StoreKit tests use only a test-bundle catalog and assert an Xcode-environment preflight. Purchase/restore, account ownership, renewal, refund, expiration without renewal and unsuccessful outcomes pass with isolated transactions. Go race integration tests validate the Apple certificate chain/purpose/signature/claims, ownership, refund replay order, expiry, free account/export access and paid-sync rejection. These fixtures do not establish actual App Store Sandbox purchase, server-notification delivery or production billing readiness. Billing remains disabled.

All existing profile presentation/photo/archive-lifetime/notification regressions remain required. Signed Simulator tests verify the actual App Group; an unsigned binary cannot establish that shared-container entitlement. The JSON exporter is exercised through the real iOS27 Files Save control and timestamped names; its native data check verifies progress inclusion and exclusion of credentials. The supported five-language catalog contains 384 keys, with 356 compiler-extracted keys covered. iPhone Release and native macOS/widget builds pass; signed-device Google, APNs, multi-device sync and widget receipt remain release checks.


## Publication candidate checks — 18 October 2026

- The complete signed iOS27 scheme passed39tests with no failures. The physical-only existing-account smoke test was correctly skipped on Simulator. All46domain/HTTP/persistence package tests pass; the five-language384-key catalog covers356compiler-extracted keys.
- The five-language navigation/creation flow now visits the monthly calendar and also runs successfully on a13-inch iPad. Onboarding passes on both iPhone ProMax and iPad in all five languages. Native screenshot layouts were visually reviewed for both device sizes; no real account data is used.
- Six final focused tests pass after per-account planning-policy alignment: the ordered StoreKit setup host, purchase/restore/renewal/refund/expiry/account-isolation tests, unsuccessful-purchase tests, free-preview policy, unknown-policy local tracking and external purchase-intent onboarding. A recognized external intent opens the existing Plus/account flow after onboarding without starting a purchase or changing local progress.
- App and widget Release products include separate privacy manifests. The app-owned declarations cover account/profile/content/push/purchase functionality; the optional Google sign-in SDK also declares its own linked data and analytics. App Privacy and the five-language notice account for both. No HealthKit, motion, contacts, location-permission or advertising-tracking capability is added.
- Go race tests and vet pass, including signed HTTP OCSP fixtures for fresh/revoked/stale/unknown/malformed status, issuer/serial binding, delegated-responder authority, cancellation, redirects and outages. HTTP integration tests cover private Sandbox allowlists, production/Sandbox entitlement separation and export/account erasure after expiry without affecting another account or resurrecting a deleted account. Five backup/operations tests pass.
- These checks do not establish real Apple Sandbox purchases, signed Apple notification delivery, production APNs receipt, real Google return/profile editing or multi-device synchronization. TestFlight1.0(11) is confirmed Testing in the sole-owner Makeet Internal group after successful cloud test/archive/internal-distribution actions; public release1.0is being prepared. Public charging remains off and App Review has not been submitted.


## Subscription cancellation disclosure

The account-deletion confirmation now states in all five languages that Apple subscription billing continues until cancellation. It links to official Apple subscription management while preserving immediate erasure. Two signed iOS27 UI tests pass, including opening, dismissing and reopening the actual confirmation in every language without deleting the fixture account. Native popovers may omit a Cancel row; the tests use the same outside-dismissal path as the existing account confirmation regression. All five captured dialogs were visually inspected.

The updated Terms and account-deletion pages explain free local use, the approved optional Plus list price, the complete annual payment, renewal/cancellation, restoration with the original accounts, and export/erasure access after expiry. HTTP race tests verify functional EULA and subscription-management links on the relevant routes and preserve the privacy-only controller identity boundary. Both iOS and macOS Release1.0(12) compilers pass; app/widget privacy manifests, test-resource exclusions and fixture-marker exclusions were verified. The five-language384-key catalog covers356compiler-extracted keys on both platforms. These checks do not replace real Apple Sandbox billing or production APNs receipt verification.


## Free planning and sync-only Plus — 19 October 2026

- Free use covers every local feature, including the Planner and confirmed calendar planning. Makeet Plus only unlocks account sync, which the server enforces with `subscription_required` when billing is enabled. The client planning gate, its cached public billing policy and the unknown-policy fixture were removed.
- The GitHub `Simulator tests` workflow passed the complete required scheme on a freshly booted iOS 27.0 iPhone 17 Simulator with Xcode 27.0 and ad hoc signing: 25 UI tests (the physical-only smoke test skipped), the StoreKit setup host and 16 calendar-target tests (the two calendar-permission tests skipped). Two further focused StoreKit/calendar runs also passed.
- `testPlanningAndLocalTrackingStayFreeWithoutPlus` opens the Planner horizon without a Plus screen and keeps logging and decrement free. Its screenshots, the updated Plus sheet and the five-language onboarding account choice were visually reviewed.
- The first GitHub runs exposed two pre-existing timing issues. The out-of-process Files exporter could stay blank for more than five seconds on a cold Simulator, and the unsuccessful-purchase test left an unanswered Ask to Buy request that intermittently failed the next real StoreKit purchase. The exporter wait now allows 30 seconds; the test asserts the pending request and declines it.
- Go race tests and vet, five-language catalog validation and the iOS/macOS builds pass. Real App Store Sandbox purchases, production APNs receipt and multi-device sync remain release checks.


## TestFlight 13 and production push — 19 October 2026

The sync-only Plus change passed the required Xcode Cloud iOS test action at 15:24:54 UTC, alongside successful archive, backend and verification checks. App Store Connect confirms that processed version 1.0 (13) is Testing in the owner-only group. The owner confirmed real Google sign-in, profile editing and saving, and actual test-push receipt on that build. This confirmation does not establish multi-device synchronization, scheduled-reminder timing or real App Store Sandbox purchase and restoration.

The production APNs credential is limited to the two Makeet bundle topics and stored opaquely in local and Mac Pro hush. The authorized temporary download was removed. The isolated service uses production APNs, with a new listener verified after restart. Public API health and configuration return HTTP 200; billing remains disabled. The owner's concurrently deployed backend and updated five-language landing were preserved.

The five Store descriptions and reviewer instructions match the updated source after reload. All ten monthly and yearly subscription summaries, plus both reviewer notes, disclose synchronization-only Plus and free calendar planning. The 15-category App Privacy attestation is published. The Paid Apps Agreement is accepted but remains Pending User Info until banking and tax completion. The owner verified the professional EU contacts; their Apple status is In Review. No App Review submission or public release has occurred.

## Product-page completion — 19 October 2026

The current Apple UI was audited directly. Four actual native screenshots were confirmed in each required medium Dynamic Island iPhone and13-inch iPad slot across Italian, English, French, German and Spanish:40images. The separate initial Header and Search Results panel was empty and the release lacked a selected binary. Build13is now associated with version1.0and confirmed after reload.

The AppKit creative renderer executes successfully and produces five opaque5244x2950headerPNGs and five opaque3840x2560searchPNGs, using the original app icon and real native demo captures. The first header composition exposed an additional crop in Apple's phone preview; the final layout adds safe margins and a text-column inset. Search uses a separate larger-content composition. Alltenfinalslots show1of1afterreload, with no Italian fallback in other locales. Product-page previews in allfive languages and the final Italian search preview were visually inspected; the icon and native gallery render correctly. The generated files' dimensions and opaqueRGBformat were checked. No native code, backend schema or API route changed, and no new native build was needed.

The listing remains Prepare for Submission. No public product page, App Review submission, preview video or completed real subscription purchase-screen review attachment is claimed. Banking/tax steps remain on the owner's explicit hold pending Apple's membership residence correction.


## Entirely free release and flexible goals — 19 October 2026

The owner superseded the previous paid-sync offer. Production native purchases and backend billing processing are disabled; account synchronization remains free even if dormant billing credentials are configured. Purchase History was removed from the app-owned privacy manifest, leaving provider SDK declarations intact.

Package tests cover explicit zero versus an unknown day, positive limits, malus, signed statistics/streak/calendar consistency, fractional cancellation, disk reopen, remote record application, old JSON defaults and opt-in negative corrections. HTTP tests cover signed and zero records, atomic/retried account sync, export/isolation, indexed legacy-client rejection and disabled billing. No backend database schema migration is introduced.

The actual iOS 27 Simulator flow creates a zero-limit habit, confirms zero, logs two malus occurrences, decrements back to zero, creates a signed minimum goal, decrements below zero, saves and reopens a negative calendar correction, and cancels a zero reset without changing the saved value. The complete focused flow passes and its native screenshots were reviewed. Free external-purchase-intent handling, native Files export and five-language account-erasure/cancel paths also pass.

The final free-release branch `f089343` passed [Verify Makeet](https://github.com/turinglabsorg/makeet/actions/runs/39299074492) and the [complete iOS 27 Simulator scheme](https://github.com/turinglabsorg/makeet/actions/runs/39299074429). The result bundle reports 45 tests: 42 passed, 0 failed and 3 explicit skips (physical-account smoke plus two unavailable Simulator EventKit-calendar cases). All 51 package tests pass. App/widget compilers pass on iOS and macOS; the 403-key, five-language catalog covers 370 compiler-extracted keys. Actual CI screenshots for zero/negative goals, free access and account erasure were reviewed. These results preserve the stated real-device/EventKit boundaries.

The Go race suite includes legacy pending-batch upgrade retries, account-indexed old-client rejection, zero/signed round-trip/export/isolation, the free production policy, and reminders for unlogged, confirmed-zero, malus, negative, rest and future days. Main was advanced only after the required branch checks and screenshot review.

A manual Home Screen smoke on the dedicated iOS 27 Simulator uses a persistent local archive, outside the in-memory XCTest host. The medium widget renders two habits and both controls without clipping, including zero-limit malus and an opt-in negative balance. Widget minus changes the signed balance from -1 to -2 and corrects the limit occurrence from 1 to 0. Opening the app confirms both saved quantities and the respected zero limit. This establishes the local iOS widget/app round trip; signed-account switching, macOS desktop interaction and OS background timeline delivery remain separate checks.

The tested Go executable and embedded site were deployed with an online SQLite backup, checksum-guarded atomic replacement and an isolated listener restart under the existing persistent supervisor. Private runtime configuration, wrapper and credential injection were unchanged; a rollback binary was retained. Public health/config return HTTP 200 with billing false and Apple/Google enabled. All 25 public routes across five languages return HTTP 200. Free/limit copy matches source, subscription-management links are absent, and the approved controller line remains privacy-only. Browser checks confirm the public free FAQ and five 390px layouts without horizontal overflow. The temporary viewport and isolated local preview were cleaned up.

Both unsubmitted subscription products now have 0 of 175 countries selected, verified in Apple with saved evidence. The app download has zero customer prices and proceeds in all 175 countries, including EUR 0 in Italy. All five Store descriptions and shared reviewer notes match the free-release source. After immediate owner authorization, the App Privacy update was published with 14 categories; only Purchase History was removed. No new account/security permission or paid agreement was accepted by this change.

Xcode Cloud build 14 from `f089343` passed both the required iOS test and archive actions. The official archive and App Store IPA were retained with app/widget privacy manifests and matching version 1.0 (14); the Release app contains no test fixture markers, private key files or StoreKit test catalog. App Store Connect confirms the processed build is automatically assigned to the existing internal group with one tester. This is TestFlight distribution evidence, not App Review submission or public publication.

The internal group confirms 1.0 (14) is Testing. All five localized What to Test texts now describe the free offer, zero-limit malus and optional negative balances; exact saved values were checked through the language selector. The release version has build 14 selected and saved, retaining manual release. Apple's first review validation found a failed Spanish search-artwork upload despite its occupied slot. The failed placement was removed without deleting its library record, and the verified original was uploaded again. The submitted Spanish search placement instead reuses the already processed Spanish universal header asset, with both locale-specific usages verified in Asset Library. The additional search composition remains in the library; no native screenshot was removed.

Apple accepted the free iOS 1.0 submission at 19:40 UTC on 19 October and displayed **1 Item Submitted**, then **Waiting for Review**. The saved release binary is 1.0 (14), with no subscription products included and manual release retained. Submission reference: `a9c57d00-a409-4967-94c8-fbbe7c0f12cc`. The final Xcode Cloud result lists 42 passed, 0 failed and 3 skipped tests, and its internal TestFlight post-action succeeded. Public release, Apple approval and the remaining real-device checks are not implied by this receipt.


## Compact iOS progress review (21 October 2026)

The dedicated iOS27Simulator exercises compact Home controls, the leading zero-confirmation checkbox, navigation into detailed statistics, the monthly Trends rows (three complete previous months and the current month), empty historical periods and full-width Planner/day-event cards. Existing signed-quantity, past-day correction and statistics-period checks retain their behavior. Archive-host lifetime regressions remain required.

A separate persistent local-demo Home Screen smoke captures small, medium and large WidgetKit sizes. The medium widget shows all three active habits with44-point controls. Actual widget plus and zero-confirmation intents are verified after cold reopening the app, including persisted quantities and confirmed zero; the sample archive remains isolated to the dedicated QA simulator. Timeline refresh remains an OS request, and account switching, signed-device/background delivery and macOS interaction remain separate checks.

Review images use native iOSSimulator captures and Android UI drawn by an isolated SDK35JVMtest harness. Android renders are visual-review evidence, not a substitute for the API26/36instrumented release gates. No further push, deployment or store submission accompanies this screenshot review.
