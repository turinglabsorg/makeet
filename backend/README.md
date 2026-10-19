# Makeet backend

Custom Go HTTP service with SQLite storage. Apple and Google provide identity; Makeet owns accounts, sessions, authorization, and the sync log. No hosted authentication platform or email/password login is used.

## Status

The HTTP service and embedded pre-release website are deployed on the dedicated Mac Pro service, behind HTTPS at `makeet.app` and `api.makeet.app`. Apple iOS and Google providers are enabled for live validation; Google consent is External / In production. Integration tests also run locally. The native app includes the account/session/sync adapter, and public Apple iOS account access is enabled for validation. Live Apple authorization/revocation, signed-device and multi-device validation remain release checks.

## Run

Requires Go 1.26 or newer:

```sh
cd backend
go test -race ./...
go vet ./...
go run ./cmd/makeet
```

Configuration:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MAKEET_LISTEN` | `127.0.0.1:8086` | HTTP listener behind the HTTPS relay |
| `MAKEET_DATABASE` | `./data/makeet.sqlite` | Dedicated durable SQLite database |
| `MAKEET_APPLE_CLIENT_IDS` | empty | Comma-separated allowed Apple audiences |
| `MAKEET_GOOGLE_CLIENT_IDS` | empty | Comma-separated allowed Google audiences |
| `MAKEET_APPLE_TEAM_ID` | empty | Public Apple developer team identifier |
| `MAKEET_APPLE_KEY_ID` | empty | Public Sign in with Apple signing-key identifier |
| `MAKEET_APPLE_SIGNING_KEY` | empty | PKCS#8 P-256 signing key, injected through hush |
| `MAKEET_PROVIDER_ENCRYPTION_KEY` | empty | Hex or base64-encoded 32-byte AES key, injected through hush |
| `MAKEET_APNS_TEAM_ID`, `MAKEET_APNS_KEY_ID` | empty | Public APNs signing identifiers |
| `MAKEET_APNS_KEY` | empty | PKCS#8 P-256 APNs key injected through hush |
| `MAKEET_APNS_ENVIRONMENT` | empty | `development` or `production`; requires matching key/provisioning |
| `MAKEET_APNS_TOPICS` | empty | Explicit comma-separated bundle IDs allowed for push |
| `MAKEET_PRIVACY_CONTROLLER` | empty | Approved controller line, private runtime config, privacy route only |
| `MAKEET_HOSTING_COUNTRY` | empty | Primary hosting country code; required before enabling accounts |
| `MAKEET_TRUST_RELAY` | false | Accept stamped client IP only from a loopback relay; origin must enforce Cloudflare ingress |

Unconfigured providers reject authentication. Public client IDs are not secrets. Keep signing keys/provider secrets in hush, never source control. Do not add fixture issuers or development-token bypasses to runtime configuration.

SQLite uses foreign keys, WAL, a busy timeout, and a single connection. Database directories are created with mode 0700 and the main database with mode 0600. Keep data on the Mac Pro's local disk and back up SQLite using an online backup or a stopped service, including its journal state. Do not copy only the main database file while the service writes.

## Identity and sessions

1. `POST /v1/auth/challenges` with `provider` returns a one-use challenge ID, nonce, and five-minute expiry.
2. Pass that nonce to the native identity provider request. The signed ID token must contain exactly that nonce.
3. `POST /v1/auth/exchange` with `provider`, `challenge_id`, and `id_token` verifies signature, issuer, allowed audience, expiry, subject, and nonce, then consumes the challenge atomically. Apple requests must also include `authorization_code`; the backend exchanges it with Apple and verifies the returned identity belongs to the same subject, audience, and nonce before issuing a Makeet session.
4. A verified provider/subject pair creates an account on first use. Email is contact metadata, never an account-linking key. Apple and Google identities currently create separate accounts; explicit linking is a future feature.
5. Makeet returns an opaque 15-minute access token and a rotating refresh token with a fixed 30-day session lifetime. Only SHA-256 token hashes are persisted. The app must serialize refresh requests and store tokens in Keychain.
6. Replaying a previously rotated refresh token revokes that session family. Logout revokes the current session immediately.

Routes:

| Method | Path | Access |
| --- | --- | --- |
| GET | `/healthz` | Database health |
| GET | `/v1/config` | Configured identity providers |
| POST | `/v1/auth/challenges` | Provider challenge |
| POST | `/v1/auth/exchange` | Signed identity exchange |
| POST | `/v1/auth/refresh` | Refresh token |
| POST | `/v1/auth/logout` | Bearer access token |
| GET | `/v1/me` | Bearer access token |
| DELETE | `/v1/me` | Bearer token and `{"confirmation":"DELETE"}` |
| POST | `/v1/sync` | Bearer access token |
| PUT / DELETE | `/v1/devices/{id}` | Bearer token and installation proof |
| POST | `/v1/devices/{id}/test` | Bearer token, installation proof and stable message UUID |
| POST | `/v1/devices/{id}/receipts` | Bearer token, installation proof and received message UUID |

Account deletion first revokes each stored Apple authorization through Apple's token revocation endpoint, then atomically deletes identities, encrypted provider grants, sessions, access-token hashes, habits, activities, changes, and cached mutation responses. A provider failure returns 503 and preserves the account and data for a retry; the app must not report deletion as complete. These database lifecycle operations are serialized so a simultaneous login cannot insert an unrevoked grant between revocation and deletion.

Apple refresh tokens are encrypted with AES-256-GCM, a random nonce and authenticated account/provider/audience binding in `provider_grants`. Signing keys and the encryption root stay in hush; the database never receives them. Preserve the encryption root in encrypted operational backups, since losing it prevents provider-token recovery. Client assertions use ES256 and expire after five minutes. Provider HTTP redirects are refused so client secrets and user tokens cannot be forwarded to another destination.

The production process refuses to start with Apple audiences configured but missing/invalid signing or encryption configuration. Apple is not advertised by `/v1/config` when its revocation client is unavailable. Live provider credentials and real Apple sign-in/revocation checks remain required before opening registration.

## Synchronization

`POST /v1/sync` accepts an integer `cursor`, a UUID `mutation_id` for writes, and up to 100 `changes`. Each change carries `kind` (`habit` or `activity`), UUID `id`, last-seen `revision` (zero when creating), `deleted`, and `data`. Ownership is always derived from the bearer session.

The service normalizes UUIDs, validates quantities and timestamps, orders habits before activities, and checks that an activity references the same account's non-deleted habit. Every mutation batch is atomic. A stale revision returns HTTP 409 with the current records for that account; no part of the batch is applied. The caller must resolve conflicts explicitly.

Repeating an identical mutation ID/request returns the original response. Reusing the same mutation ID with different content returns HTTP 409. Keep pending mutation payloads durable and unchanged until acknowledged. Sync history is retained, so a new device can start at cursor zero.

The response includes `applied` revisions, up to 200 incremental `changes`, the next `cursor`, and `has_more`. Continue pulling until `has_more` is false. Records may appear multiple times in history; apply their latest revision. Deletions produce tombstones. Deleting a habit does not erase its activity history automatically. Archive habits to preserve history; permanent removal must explicitly delete the associated records.

Quantitative logging uses a new UUID per activity, so simultaneous independent logs remain separate entries. Clients must not overwrite a daily total.

## Verification and deployment boundaries

Tests use generated RSA keys, a real local JWKS HTTP server, signed JWTs, an actual API HTTP server, and temporary on-disk SQLite databases. Coverage includes signature/audience/issuer/nonce/expiry rejection, challenge replay, account separation, refresh replay revocation, logout, access/session expiry, atomic conflicts, idempotent retries, tombstones, pagination, durability, and deletion cascades. `go test -race ./...` passes.

HTTP requests have body/header/time limits. Auth routes permit 30 requests per minute per client address. Explicit trusted-relay mode accepts `X-Makeet-Client-IP` only from a loopback peer. The Makeet-only ingress module requires a Cloudflare network peer, validates one `CF-Connecting-IP`, strips spoofed forwarding headers and stamps the address. Direct origin access to Makeet returns 403; unrelated hosts retain their original relay behavior. Never enable relay trust behind an unvalidated public origin. Live provider/revocation and multi-device verification remain release checks.

## Embedded website

`internal/site` embeds its templates, CSS, native screenshot, app icon and five translation catalogs into the Go executable. The site serves language-specific home/support pages, preserves the current page when changing language, and uses native details controls for the language menu and FAQs. It has no third-party scripts, font requests, analytics or sign-up form.

Legal pages are published only with complete runtime controller/hosting configuration. Incomplete configuration returns 503/noindex and prevents the process from enabling accounts. The controller line is excluded from source and all non-privacy routes. Cloudflare email obfuscation is disabled on this zone so public support links work with the strict script-free CSP.

HTTP integration tests exercise all page/language combinations, security headers, language navigation/negotiation, unavailable legal content, assets, missing routes, HEAD, and rejected write methods.

## Push and backup operations

Device tokens are AES-GCM encrypted with account/device/topic/environment binding. A random installation secret is hashed on the server; a device-only Keychain item stores it on the client. Device ownership derives from the current session. Logout removes registrations, invalid sessions cannot send, and account/token transfers remove old delivery records.

The APNs sender uses cached ES256 assertions and fixed Apple endpoints. Pending messages retry at most five times within ten minutes; rejection removes only the matching old token, preserving concurrent refreshes. Explicit test UUIDs are idempotent, with one new test per minute per device. Apple acceptance and app-confirmed receipt are separate states. Daily reminders default off, respect the selected time zone, skip fully completed synchronized habits and deduplicate each device/local day. Delivery history expires after 30 days.

`ops/backup.py` creates online SQLite snapshots, checks integrity and rotates restricted backups within 30 days. The deployment runs an isolated daily launchd job and passed a restore integrity/foreign-key/table-count drill. Keep rollback binaries and private runtime configuration outside source control. Production APNs credentials and live device delivery are not yet verified.


## Private account profile

Schema4 adds an account-owned `profiles` row with a display name, normalized photo and revision. Authenticated `GET /v1/me/profile` returns the current private profile; `PUT /v1/me/profile` saves `{name,image,revision}`, where image is base64 JPEG/PNG or null. Names are limited to80 Unicode characters without controls; input photos are limited to128KiB and512pixels per side, decoded and reencoded as JPEG without metadata. The server never fetches image URLs. Stale revisions return409 `profile_conflict`; successful writes increment the revision. There is no public profile route or user-selectable owner. Account deletion cascades to the profile.

## Free release and retained billing implementation

Tracking, planning and private account synchronization are free. `Config.AllowSubscriptions` is false and has no production environment mapping; transaction submission and signed notification processing return `billing_unavailable`. Native purchase observers and entry points are also disabled. The remaining billing implementation is retained for a future explicitly authorized paid release, with isolated tests. `/v1/config` reports `billing_enabled`; authenticated `GET /v1/me/entitlement` reports account access, and `POST /v1/me/transactions` accepts an App Store `signed_transaction`. Purchases bind `appAccountToken` to the authenticated Makeet UUID. Signed App Store Server Notifications V2 use `POST /v1/app-store/notifications`. The subscription table is account-scoped and indexed by user/revocation/expiry. Whole-account deletion, profile access and `GET /v1/me/export` remain available without Plus.

With the current free-release guard, `MAKEET_BILLING_ENABLED=true` cannot enable purchases or sync gating. In the retained billing implementation, `MAKEET_BILLING_SANDBOX=true` additionally accepts Apple Sandbox signatures. Neither accepts Xcode/local-test data. Keep public charging disabled until the [release checks](../docs/release-readiness.md) pass, including real Sandbox checkout/restore and signed notification delivery. Do not infer payment readiness from generated-fixture tests.

For a controlled test, `MAKEET_BILLING_PREVIEW_USERS` accepts up to ten comma-separated account UUIDs. A nonempty list enables per-account billing only for those users while public configuration continues to report billing disabled. Unlisted accounts retain the free preview; their Sandbox transactions cannot be stored. Remove the list only when preparing the reviewed public service. Stored Sandbox purchases do not grant entitlement when Sandbox acceptance is disabled.

The public trust anchor `internal/billing/AppleRootCA-G3.cer` comes from [Apple PKI](https://www.apple.com/certificateauthority/AppleRootCA-G3.cer). It contains no private key. Production construction checks the ES256 signature, current certificate validity, Apple purpose OIDs and online OCSP for both leaf and intermediate certificates, then verifies identifiers, ownership, environment and expiry. OCSP responders are restricted to Apple's hosts, redirects are refused and only fresh, signed GOOD responses are briefly cached. Delegated responders require explicit OCSP signing authority. Network/status-service outages return retryable503 rather than granting access or declaring a purchase invalid. Generated fixture roots remain confined to tests. Production notifications require app Apple ID6823557479; Sandbox may omit it, as in Apple's server library. Refund ordering prevents replaying an older purchase to revive access.

Expired subscribers can still export their records or explicitly delete their account and server data. Account deletion also removes subscriptions and prevents delayed notifications from recreating the account. Expiry alone does not erase an archive; synchronized records follow the published retention policy.

Historical unsubmitted products are `org.turinglabs.makeet.plus.monthly` and `org.turinglabs.makeet.plus.yearly`, with Italy reference prices EUR 1.99/month and EUR 11.99/year. Prices shown in the client come from StoreKit. No introductory trial or Family Sharing is enabled.


## Flexible goal sync

Habit JSON adds optional `goal` (`at_least` by default or `at_most`) and `allows_negative` (false by default). A limit target may be zero; minimum targets stay positive. Activity amounts may be finite signed values or an explicit zero confirmation. No schema migration is required. Updated clients send `X-Makeet-Sync-Version: 2`. Before any mutation/retry response, account-indexed checks reject older clients when advanced goal data exists, preventing silent loss of limits or signed progress. Legacy default fields are normalized for immutable pending-batch retry compatibility. Reminder eligibility honors weekdays/start dates; a limit day needs a reminder only while unlogged.
