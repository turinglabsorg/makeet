# Storage, calendars, and widgets

## Public account architecture requirements

The target product supports open self-service registration and authenticated account-based synchronization. `backend/` implements the Go account and sync APIs with dedicated SQLite persistence and signed-identity HTTP integration tests. The native app is not connected yet. The Go service and embedded pre-release website are deployed on the dedicated Mac Pro service; authentication providers remain disabled. Use the owner's Mac Pro with a Makeet-specific service, database, and persistent storage. Authentication uses Apple and Google only; Supabase and password registration are excluded.

The shared account service should be the authoritative synchronization boundary for the public product. SwiftData remains the on-device store used by the app and its widget extension. Before enabling CloudKit alongside a backend, define one authority and an explicit adapter or migration strategy rather than allowing two independent writers to synchronize the same records differently.

Every remotely stored habit, activity, calendar connection, and planned session must belong to an authenticated account. Determine ownership from the server session and enforce it for reads, writes, sync cursors, and background jobs. A client-supplied record UUID or user identifier must not grant access to another user's data. Calendar credentials and assistant context follow the same account boundary.

Account switching and logout must also isolate the local App Group store, widget snapshots, pending writes, and calendar connection state. The current account-free local archive needs an explicit one-time import decision when registration is introduced. A successful sign-in must not silently upload a different person's previous local archive.

Account-scoped native caches, Keychain sessions, provider provisioning, Apple grant revocation, and production account configuration remain implementation requirements. The current local store, EventKit integration, and prepared CloudKit configuration below describe the existing native foundation. See the [backend protocol](../backend/README.md).

## Sources of truth

Habit definitions and timestamped activity records are authoritative in SwiftData. Calendar events describe planned sessions only. A calendar event ending, moving, or being deleted must never infer activity completion.

App and widget extensions use the same `Habit` and `Activity` models and App Group identifier. Each increment inserts a separate UUID-bearing activity instead of overwriting a shared daily counter. Every explicit save reloads WidgetKit timelines. The widget intent fetches the current habit before logging and rejects missing or archived habits. Storage errors are shown, not converted to an empty successful state.

The shared store is intentionally local by default. Independent-context persistence tests verify that app-like and widget-like contexts retain each other's registrations and that undo survives reopening the store. These tests do not establish cross-device sync or widget lifecycle correctness.

App and widget decrement operations subtract the configured step from today's newest entries in the habit's time zone. Exhausted entries are deleted and partial entries retain their original timestamp with a smaller positive amount. The operation stops at zero and leaves other days and habits unchanged. A future native sync adapter must publish these revisions/deletions rather than inventing negative activity records. The medium widget shows two habits so both adjustment controls retain 44-point touch targets.

Appearance is stored in the existing `symbol` field: SF Symbol names retain their current meaning, while a single emoji is encoded as `emoji:` plus its grapheme. The native picker supports presets and custom composed emoji. This does not change the SwiftData schema or the backend record shape.

## CloudKit activation

Apple's supported SwiftData sync path uses CloudKit. The schema avoids unique constraints and required relationships, and all stored properties have defaults. `SharedStore` supports the private container `iCloud.org.turinglabs.makeet`, gated by the Boolean `CloudSyncEnabled` Info.plist value declared explicitly for each target in `project.yml`.

Before enabling that value:

1. Register the App Group and iCloud container using the owner's chosen Apple development team.
2. Add the iCloud/CloudKit capability and container entitlement to the app targets and widget extensions, using Xcode and the same container identifier.
3. Enable the required background remote-notification capability for iOS, with the matching signing entitlements and profiles.
4. Initialize the development schema, test inserts/deletes/offline recovery on two signed devices, then deploy the schema before production distribution.
5. Add CloudKit account/error/freshness observation to the UI. A configured container is not proof of successful synchronization.

The initial UI deliberately reports cloud sync as not activated, or configured but awaiting verification. This repository does not provision an Apple account or claim multi-device tests have run.

Reference: [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## EventKit

Request full event access only after the user chooses to connect calendars. Read today's events from selected calendars, consider non-free/non-cancelled intervals occupied, observe `EKEventStoreChanged`, and refresh when the app returns to the foreground. The user independently selects a writable calendar for new blocks.

Creation rechecks permission, destination writability, slot freshness, and conflicts. Each generated event includes a `makeet://plan/<habit-uuid>-<start-epoch>` marker. Before creating an identical event in the selected destination, the adapter checks for that marker. The planner suppresses additional same-day blocks for recognized Makeet events in selected calendars. This is a first idempotency boundary, not full bidirectional reconciliation.

Current limits: calendar selection and destination are device preferences; Makeet does not yet maintain a durable provider-independent planned-session table; deselecting or externally editing/moving marked events can affect detection. Existing events are never silently rescheduled. Direct app-to-provider calendar lifecycle sync remains a next milestone.

Google calendars already configured in system Settings may be exposed through EventKit. This is different from a direct Google sign-in integration, and updates follow the system account's synchronization policy.

Reference: [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

## Direct Google synchronization design

Use OAuth with PKCE and the system authentication session, least-privilege scopes, and Keychain token storage. Never embed client secrets or access tokens in the app or repository.

A direct adapter needs initial pagination, a stored sync token per account/calendar/query, incremental updates including deletions, token-expiration recovery on HTTP 410, explicit retry/backoff, and revocation handling. Persist provider IDs and ETags in a planned-session mapping. Use conditional writes for conflicts and idempotent event creation to prevent duplicates across devices. Do not derive habit activity from provider events.

Reference: [Google Calendar incremental synchronization](https://developers.google.com/workspace/calendar/api/guides/sync).

## Widget lifecycle

Small and medium interactive widgets are provided for both iOS and native macOS. They show incomplete habits first and continue allowing increments above the daily target. The local store and `LogHabitIntent` are shared with the app. Widget reloads request an update; the OS controls actual delivery. Timelines request refresh at the next midnight or in 15 minutes, whichever is earlier. Multi-time-zone habits need a future refinement to choose the earliest relevant habit midnight.

Remaining device checks: install both extensions with valid App Group signing; add Home Screen and desktop widgets; increment while the app is closed; reopen and verify; cross midnight; revoke iCloud access; repeat after an offline period. Widget compilation alone does not verify these flows.

Reference: [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

## Push notifications

The iOS and macOS app targets include their platform-specific APNs entitlement. Debug selects development; Release selects production. Signed provisioning profiles must match that environment. Widget extensions do not register independently for push.

`NotificationService` requests alert, sound, and badge permission only from the explicit Connections action. Foreground refresh observes changes made in system Settings and registers already-authorized installations with APNs. Platform delegates receive refreshed tokens and registration failures; tokens stay in memory and are never logged. Notification taps open Today or Planner using a fixed destination allowlist.

The interface distinguishes OS permission, APNs registration, and the pending server connection. A token callback does not prove backend registration or delivery. A topic-specific Sandbox APNs key is provisioned for the two Makeet app IDs and stored encrypted through hush. A production key, authenticated device-token ownership, account logout/revocation cleanup, reminder scheduling, and signed-device delivery remain open. This foundation does not automatically schedule or send notifications.

References: [APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns), [notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [scoped APNs keys](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).
