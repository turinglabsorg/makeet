# Project instructions

Read `~/.agents/AGENTS.md` for global instructions.

This is a native SwiftUI habit tracker for iOS, with a macOS companion and WidgetKit extensions. The owner selected the product name Makeet and the public repository turinglabsorg/makeet.

- Read `DESIGN.md` before changing UI.
- Use default system typography throughout app, widgets, and icon. Do not introduce serif or editorial typefaces.
- Keep the pure domain and scheduling logic in `Core/`; it must run under Swift Package Manager tests.
- App and widget share their SwiftData schema in `Shared/`.
- Never label simulated, disconnected, or unverified integrations as synchronized.
- Calendar completion and habit completion are separate concepts. Only explicit user logging changes progress.
- Calendar writes require a visible user confirmation and must be idempotent.
- All documentation and code are in English. The app and widgets support Italian, English, French, German, and Spanish through native string catalogs in `Resources/`. Localize app-owned text with `String(localized:)` or the appropriate native resource type. Preserve user-authored names/units and use system date/number formatting. Run `scripts/ValidateLocalizations.py`, including compiler extraction coverage after an iOS build, when changing strings.

## Public product and hosting requirements

- Makeet is intended for public use with open self-service registration. Do not impose invitation-only access or an owner-only account model.
- Each user's habits, activities, statistics, calendar connections, credentials, and assistant context are private to that account. Public registration does not make personal data public.
- A backend is required for the public product. Implement it in Go and run it on the owner's Mac Pro. Do not use Supabase. Authentication must use Apple and Google, not email/password. Keep Makeet's service, database, persistent storage, and configuration isolated from other projects on that host.
- Account-based synchronization is the target for the public product. The existing local SwiftData store and disabled CloudKit path are the current foundation, not an implemented public account service. Avoid independent competing sync authorities.
- Before adding account switching, partition or replace local app/widget stores by account and prevent the next session from seeing the previous user's cached data. Derive server-side record ownership from the authenticated session.
- Open registration and the Mac Pro deployment are requirements, not completed capabilities. Keep README and product status accurate until they are implemented and verified.

## Architecture and current capabilities

- `Core/HabitEngine.swift` derives daily quantities and streaks from timestamped activity entries using the habit's stored time zone. Quantities can exceed the target; only the visual fraction is capped. An unfinished today preserves yesterday's current streak.
- `Core/ScheduleEngine.swift` is an explainable local scheduler. It searches 07:00–22:00 in 15-minute intervals, avoids busy periods and other proposals, and uses historical logging hours only with at least five prior-day samples from the previous 28 days. There is no LLM service. The Go HTTP backend is being implemented in `backend/`; the native app is not connected to it yet.
- `Shared/Models.swift` defines `Habit` (target, step, unit, preferred hour, duration, time zone, archive/demo flags) and `Activity` (UUID, habit UUID, amount, timestamp, source). App and widgets use App Group `group.org.turinglabs.makeet`. Insert activity records rather than overwriting daily totals.
- `SharedStore.decrement` subtracts the configured step from the newest positive entries in the habit's current local day. It deletes exhausted entries, reduces partial entries, clamps at zero, preserves other habits/days, and reloads widget timelines after saving. Never introduce negative activity records. App and widgets place minus left and plus right; medium widgets show two habits to preserve 44-point controls.
- `Habit.symbol` remains backward compatible: SF Symbol names are unchanged; emoji use the `emoji:` prefix plus one validated grapheme (at most 64 UTF-8 bytes). `Shared/HabitAppearance.swift` validates composed emoji and renders both kinds through `HabitMark`. Do not add a second appearance authority or translate user-selected emoji.
- `CloudSyncEnabled` is an explicit Boolean Info.plist property for each target in `project.yml`. It is false by default. The private CloudKit path is prepared but unverified; do not enable it or claim cloud sync without provisioning and multi-device checks.
- `App/CalendarService.swift` handles EventKit permissions, selected availability calendars, a writable destination, event-store change observation, and confirmed block creation. `makeet://plan/<habit-uuid>-<start-epoch>` identifies app-created events. Preserve idempotency and recheck conflicts at save time. Direct Google OAuth and complete calendar lifecycle reconciliation are not implemented.
- `App/` provides Today, Trends/detail, Planner, Connections, habit creation, and archive/restore. After archiving, detail shows confirmation and an explicit return action; avoid combining automatic source-list removal with an additional navigation dismissal.
- `Widget/MakeetWidget.swift` provides small and medium iOS/macOS widgets with `LogHabitIntent`. Both extensions share the model schema and logging operation. Timeline reloads are requests to the OS, not guarantees of instant delivery.
- `--demo` seeds only an empty archive; demo data must remain labeled. `--ui-testing` uses an in-memory archive. Never seed production launches automatically.
- `App/NotificationService.swift` handles explicit notification consent, platform APNs registration callbacks, token refresh, failures, and fixed Today/Planner tap destinations. APNs tokens remain in memory; authenticated server registration and delivery are not implemented. Preserve the distinction between OS permission, device registration, and verified server delivery. Debug uses development APNs; Release uses production, with matching signing profiles required.

## Project generation and verification

- `project.yml` is the source of truth for the checked-in Xcode project. Regenerate with `xcodegen generate` after target/configuration changes.
- Apple targets are `Makeet`, `MakeetWidget`, `MakeetMac`, and `MakeetMacWidget`. Minimum deployment targets are iOS 17 and macOS 14. No personal signing team is stored in the project.
- `swift test --disable-sandbox` runs domain and shared-store persistence tests. The iOS `MakeetUITests` target exercises creation, logging, undo, archive/restore, screens, and integration status.
- `MakeetCalendarTests` contains notification state tests and a Simulator-only EventKit integration test. The EventKit test requires calendar permission, creates/removes its own temporary calendar, and verifies creation, idempotency, and conflict rejection. Never redirect it to personal calendars or remove its physical-device guard. The test scheme passes `--ui-testing` so its app host uses an in-memory archive.
- See `docs/validation.md` for tested behavior and unresolved device/cloud boundaries. Update those claims when integration coverage changes.

## Naming and public information

- The owner selected Makeet as the definitive product name on 2026-10-16. Use `org.turinglabs.makeet` identifiers, the `makeet` URL scheme, and public repository `turinglabsorg/makeet`. Purchase of `makeet.app` is verified. Its nameservers were migrated to Cloudflare; the pre-release site/API are deployed on the Mac Pro and support@makeet.app forwards through Cloudflare Email Routing.
- Public-facing operator branding is Meaningtech. Do not put the owner’s personal name, residential address, personal email/PEC, tax code, or invoicing identifiers into source, website content, screenshots, or public configuration. Legal pages remain unpublished until adequate public operator details are confirmed.
- `backend/` uses Go, standard HTTP, OIDC verification, and a dedicated SQLite database. Its authentication/session and sync integration tests use generated signed fixtures over actual HTTP and a temporary database. Never add a test-token login bypass to production.

## Backend protocol

- `backend/cmd/makeet` binds `127.0.0.1:8086` by default. Configuration uses `MAKEET_LISTEN`, `MAKEET_DATABASE`, `MAKEET_APPLE_CLIENT_IDS`, and `MAKEET_GOOGLE_CLIENT_IDS`. Empty provider audiences disable that provider. Keep provider signing keys in hush.
- Public endpoints are `GET /healthz`, `GET /v1/config`, and `POST /v1/auth/challenges`, `/v1/auth/exchange`, `/v1/auth/refresh`. Bearer-authenticated endpoints are `POST /v1/auth/logout`, `GET /v1/me`, `DELETE /v1/me`, and `POST /v1/sync`.
- Identity ownership uses the verified provider/subject pair, never email matching. Challenges expire after five minutes and are consumed once. Access tokens expire after 15 minutes; rotating refresh tokens share a fixed 30-day session expiry. Replayed refresh tokens revoke the session. Persist token hashes only.
- SQLite tables are `users`, `identities`, `challenges`, `sessions`, `access_tokens`, `used_refresh`, `records`, `changes`, and `batches`. User deletion cascades through account data, but Apple provider-grant revocation remains a separate unfinished requirement.
- Sync mutations accept at most 100 habit/activity records and use per-account UUID mutation IDs, atomic revision checks, tombstones, and cached retry responses. Normalize UUIDs and validate activity parents within the same account. Pulls paginate 200 changes with a cursor and `has_more`. Preserve independent activity UUIDs; do not overwrite daily counters.
- Auth rate limits currently use the socket peer address. Finalize trusted relay client-IP handling before public registration. The service is deployed with identity providers disabled, and the native app does not use these account endpoints yet.

## Public pre-release website

- `backend/internal/site` embeds templates, assets and five language catalogs in the Go executable. The public deployment runs persistently through grog serve on the Mac Pro, isolated from other services.
- Home/support pages are live; privacy, terms and account deletion routes return a localized pre-launch notice with HTTP 503/noindex. Do not present these as completed release policies or enable public accounts before the remaining identity, privacy, sync and deletion work.
- App Store Connect app ID is 6823557479, iOS version 1.0 in preparation. The owner authorized the legal name only in Apple's mandatory seller field; public site/source branding remains Meaningtech and personal data restrictions still apply.
- A topic-specific Sandbox APNs key is provisioned for the two Makeet app IDs, encrypted as hush MAKEET_APNS_KEY. Keep its value and all provider credentials out of source/logs. Production provisioning and actual delivery remain pending.
