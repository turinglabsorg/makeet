# Storage, calendars, and widgets

## Sources of truth

Habit definitions and timestamped activity records are authoritative in SwiftData. Calendar events describe planned sessions only. A calendar event ending, moving, or being deleted must never infer activity completion.

App and widget extensions use the same `Habit` and `Activity` models and App Group identifier. Each increment inserts a separate UUID-bearing activity instead of overwriting a shared daily counter. Every explicit save reloads WidgetKit timelines. The widget intent fetches the current habit before logging and rejects missing or archived habits. Storage errors are shown, not converted to an empty successful state.

The shared store is intentionally local by default. Independent-context persistence tests verify that app-like and widget-like contexts retain each other's registrations and that undo survives reopening the store. These tests do not establish cross-device sync or widget lifecycle correctness.

## CloudKit activation

Apple's supported SwiftData sync path uses CloudKit. The schema avoids unique constraints and required relationships, and all stored properties have defaults. `SharedStore` supports the private container `iCloud.org.turinglabs.avvi`, gated by the Boolean `CloudSyncEnabled` Info.plist value declared explicitly for each target in `project.yml`.

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

Creation rechecks permission, destination writability, slot freshness, and conflicts. Each generated event includes an `avvi://plan/<habit-uuid>-<start-epoch>` marker. Before creating an identical event in the selected destination, the adapter checks for that marker. The planner suppresses additional same-day blocks for recognized Avvi events in selected calendars. This is a first idempotency boundary, not full bidirectional reconciliation.

Current limits: calendar selection and destination are device preferences; Avvi does not yet maintain a durable provider-independent planned-session table; deselecting or externally editing/moving marked events can affect detection. Existing events are never silently rescheduled. Direct app-to-provider calendar lifecycle sync remains a next milestone.

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
