# Android client and release procedure

Makeet has a native Kotlin/Jetpack Compose developer candidate in `android/`, using the same Go account and synchronization service as the Apple clients. It supports Android 8.0 (API 26) and newer, targets Android 16 (API 36), and is entirely free. This source and an unsigned bundle do not establish Google Play availability or completed provider verification.

## Architecture

- `Domain.kt` implements habit-local day boundaries, Monday-first weekdays, quantities, explicit zero confirmation, limit penalties, signed progress, statistics and deterministic scheduling. Calendar blocks never complete a habit. Scheduling excludes limit habits and existing Makeet habit/day blocks.
- `HabitStore.kt` stores habit/activity records in an account-specific SQLite database. The separate local archive is preserved on sign-in, and import requires confirmation. The helper explicitly implements Closeable on older Android versions. Local schema 3 uses an indexed parent column compatible with older platform SQLite, backfilling earlier archives without changing record payloads or revisions. Habit and activity tombstones, a persisted immutable pending batch, per-record local sequences, cursors and explicit conflicts preserve offline edits and idempotent retries.
- `AccountAPI.kt` uses the existing version-2 synchronization protocol. A serialized client rotates refresh tokens, saves rotation before use, checks the expected account and refuses HTTP redirects. AndroidKeyStore encrypts session storage in the no-backup directory. Account deletion receives server confirmation before recording a durable local cleanup marker and clearing account data. Account calendar preferences are removed with the deleted archive.
- `MakeetModel.kt` owns the selected archive, authentication, synchronization, private profile and export operations. Profile saves retain the original revision, and a conflict refreshes the server profile without overwriting the editor's draft. Images are oriented using AndroidX ExifInterface, cropped and normalized to a metadata-free 320-pixel JPEG before upload; failed selections retain the current draft and show an error. Export uses the system document picker, binds the request to its archive and remains available offline.
- Native screens provide explicit account/local onboarding, Today, creation/editing, archive/restore/permanent deletion, calendar heatmaps and day corrections, trends, planning, profile editing, language settings and optional reminders. The toolbar has plus on the left and an accessible avatar-only account control on the right.
- `DeviceCalendar.kt` uses selected device calendars through CalendarContract, including recurring instances and events marked free. The day view shows both free and busy events; planning blocks only busy periods. It rechecks availability, permissions, current habit preferences and duplicates before an atomic, explicitly confirmed event batch. Calendar provider synchronization remains the operating system's responsibility. Identity login requests no Calendar API scope. Optional deletion cleanup targets only future Makeet-linked events in a bounded one-year range.
- `MakeetWidget.kt` uses native RemoteViews for two habits. It requests a four-column/two-row default on modern launchers and enough minimum height for both 48-dp control rows. Its intents include the archive scope, reject stale accounts and use the same SQLite logging operation. Unknown zero-limit days offer an explicit zero-confirmation action. Widget writes are queued for account sync when the app resumes; widgets receive no session tokens.
- `ReminderReceiver.kt` uses opt-in, inexact on-device reminders with generic text. Android controls delivery time. These are local notifications, not APNs or a verified FCM service. No Android remote-push claim is made.

## Languages and assets

`scripts/GenerateAndroidStrings.py` creates native English, Italian, French, German and Spanish resources from `Resources/Localizable.xcstrings` plus Android-specific copy in `android/strings.json`. Generated resource references are explicit so release resource shrinking preserves used translations. Regenerate and run `--check` after changing visible copy. Habit names, units, selected emoji, calendar titles and profile names remain user-authored.

The client uses Android system sans typography, the project's forest/warm palette and the original Makeet icon. Google and Apple sign-in marks are unmodified vendor assets. Apple documents its downloadable logo endpoint in [the cross-platform sign-in guide](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms). No editorial font or reconstructed Store screenshot is used.

Demo data is an explicit action available only in an empty local archive. Every screen and widget labels the examples. Demo habit IDs are stored separately from the synchronization payload, excluded from account import and included as labels in JSON export. Clearing examples preserves user-created habits. The optional Store capture test drives this actual product mode and native tabs; it does not construct screenshots from invented interfaces.

## Account access

Android supports Google sign-in and the shared username/password account flow. The owner requested removal of Apple sign-in from Android on 21 October 2026; its native control, browser polling code and callback intent filter are removed. Apple sign-in on iOS and existing Apple identities remain supported. An existing Apple account can add a username and password from its authenticated iOS Account screen and use those credentials on Android without changing its account UUID or progress.

Password registration requires email verification. Recovery confirms a single-use email code and revokes prior sessions. Existing-account credential enrollment requires that account's authenticated session and verification of its recovery email; no email-based automatic account merging exists. Native passwords stay in view memory, while existing encrypted session storage handles issued tokens. See [the account protocol and delivery configuration](password-accounts.md).

## Build and verification

Use JDK 17, Android SDK 36 and the checked-in Gradle wrapper. AGP 8.13.2, Kotlin 2.2.21 and dependency versions are pinned. `local.properties` contains only the local SDK path and is ignored.

```sh
python3 scripts/GenerateAndroidStrings.py --check
cd android
./gradlew :app:testDebugUnitTest :app:lintRelease :app:bundleRelease :app:assembleDebug :app:assembleDebugAndroidTest
```

The native test runner deliberately requires an explicitly selected emulator and rejects physical-device identifiers:

```sh
python3 scripts/RunAndroidTests.py --serial emulator-5556
```

Tests use isolated account databases, an emulator-only temporary CalendarContract calendar, and a Debug-only profile fixture over an intercepted `.invalid` origin. The profile fixture has no production login bypass and is excluded from Release. Native tests cover onboarding and all five language selections, creation/weekdays/limits, editing, archive/restore/deletion, signed logging, calendar correction Save/Cancel/reopening, profile Save/Cancel/conflict navigation, recurring events and conflict/idempotency checks, widget scope checks and SQLite upgrade/retry behavior. Manual Android 16 emulator checks also verified adding the Home Screen widget, its real plus/minus intents, persistence back in the app, the OS notification-consent dialog and test-notification posting. The signed, minified Release candidate passed local-mode onboarding, Italian selection, explicit demo entry and an actual DocumentsUI export/save producing valid credential-free JSON. Physical provider login, the system photo picker, scheduled background reminder delivery and signed-device widget behavior remain separate checks; emulator coverage must not be described as exhaustive release validation.

On pull requests and main, the Android workflow runs domain/HTTP tests, lint, release compilation, bundle audit and native tests on Android 8.0/API 26 and Android 16/API 36. It retains native screenshots and logs. CI completion must be checked on the exact candidate revision; merely adding the workflow is not evidence of a successful remote run.

`scripts/AuditAndroidBundle.py` uses official bundletool to validate the actual AAB, confirms package/SDK/free-release permissions, checks that test markers are absent and verifies 16KB load alignment of 64-bit native libraries. A distributable upload additionally requires `--require-signed`.

## Data boundaries for the Android declaration

The local archive, device-calendar event details and local reminder state stay on the device. Import and account synchronization send real habit names, schedules, quantities and timestamps to Makeet; user-authored habits may include health or fitness information. Sign-in sends the provider identity token, challenge and account identifiers to the existing HTTPS account service. A chosen private profile name/photo is uploaded only on Save. Account export can retrieve the server archive; the system document picker writes to the user-selected destination. Deletion requires server confirmation before clearing the account archive.

The actual release dependency tree includes Credential Manager, Google ID and transitive Google Play services Auth/FIDO/Blockstore libraries. It does not contain Firebase Analytics, Firebase Messaging, an advertising SDK or a billing library. The actual bundle manifest has no Advertising ID, contacts or broad media permission. These observations do not replace reviewing the applicable Google identity SDK disclosures and selecting the corresponding live Console data categories. No advertising or cross-app tracking is implemented by Makeet. The Android form must reflect these actual dependencies rather than copying the Apple Google Sign-In SDK label. [Android declaration guidance](https://developer.android.com/privacy-and-security/declare-data-use).

## Signing and Google Play gates

Use a dedicated Makeet upload key. Store its base64-encoded PKCS12 payload as `MAKEET_ANDROID_UPLOAD_KEYSTORE` and password as `MAKEET_ANDROID_UPLOAD_PASSWORD` in hush. Never commit a keystore, password or signing properties. The secure builder materializes the protected store only in a temporary private directory and removes it on exit:

```sh
hush run --name MAKEET_ANDROID_UPLOAD_KEYSTORE --env MAKEET_UPLOAD_KEYSTORE --redact -- \
  hush run --name MAKEET_ANDROID_UPLOAD_PASSWORD --env MAKEET_UPLOAD_PASSWORD --redact -- \
  python3 android/scripts/secure-bundle.py
```

On 20 October 2026 the owner confirmed the Play declarations and dedicated upload-key custody. The free Makeet app record (`4975909492999272952`) was created, and a signed, audited 1.0 (1) bundle was accepted into an unpublished internal-release draft. ReTrace mapping is attached. Console reports no blocking bundle error; warnings remain for missing testers and missing debug symbols for a transitive native library. These are distinct from the submitted iOS build and do not establish Android review approval or distribution.

Four Android OAuth clients now exist in the existing Makeet Google project: three bound to the Play app-signing fingerprints exposed by Console and one bound to the dedicated upload signer for Release QA. They reuse the existing backend audience and add no calendar scope. Apple Service ID `org.turinglabs.makeet.web` is registered with Sign in with Apple, grouped with `org.turinglabs.makeet`; its persisted configuration contains only `api.makeet.app` and the fixed HTTPS callback above. The previously registered Apple Service ID is unused by the Android client after the owner’s 21 October decision. Google certificate registration remains relevant; actual identity continuity tests remain release gates.

Before distribution, complete:

1. Preserve the free Makeet record, Play App Signing enrollment and dedicated upload credentials in hush.
2. Preserve the signed candidate and the four certificate-bound Google OAuth clients. Reuse the approved public backend/server audience; do not create an independent backend or Firebase authentication authority.
3. Deploy and verify password registration, email verification/recovery and explicit existing-account enrollment. Test real Google/password access, account restoration, profile/photo saves, cross-platform sync, offline replay, conflicts, account switching and deletion.
4. Complete Android-specific Data safety, app access, content rating, target audience, privacy/support/deletion URLs, localized listing text and genuine native screenshots. Do not copy the Apple SDK's disclosures into the Android questionnaire without auditing the Android dependency set.
5. Verify native photo/document pickers, permissions, local reminders, the Home Screen widget, smaller screens and an older supported Android release.
6. Use internal testing and the closed-testing/production-access process shown by this personal account. Google currently requires at least 12 continuously opted-in testers for 14 days for new personal accounts before applying for production access. Recruit actual testers; do not fabricate accounts or test engagement. [Google requirements](https://support.google.com/googleplay/android-developer/answer/14151465).

The existing Apple submission, its manual-release setting and the owner's banking/tax hold remain separate from Android preparation.
