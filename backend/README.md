# Makeet backend

Custom Go HTTP service with SQLite storage. Apple and Google provide identity; Makeet owns accounts, sessions, authorization, and the sync log. No hosted authentication platform or email/password login is used.

## Status

The HTTP service and embedded pre-release website are deployed on the dedicated Mac Pro service, behind HTTPS at `makeet.app` and `api.makeet.app`. Authentication providers remain disabled in that deployment. Integration tests also run locally. The native app currently uses its local SwiftData archive and is not connected to these APIs. Provider clients, live Apple authorization/revocation verification, account-scoped native caches, and production account configuration must be completed before public registration.

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

HTTP requests have body/header/time limits; authentication routes are rate-limited using the socket peer IP. Do not trust arbitrary forwarded headers. Behind a shared relay the socket-peer limit is shared by callers, so trusted client-IP routing/rate limits must be finalized before opening registration. Live provider authorization/revocation verification, backup/restore drills, legal publication, native account isolation, and multi-device sync remain release requirements.

## Embedded website

`internal/site` embeds its templates, CSS, native screenshot, app icon and five translation catalogs into the Go executable. The site serves language-specific home/support pages, preserves the current page when changing language, and uses native details controls for the language menu and FAQs. It has no third-party scripts, font requests, analytics or sign-up form.

Legal/account-deletion routes return HTTP 503, `Retry-After` and `X-Robots-Tag: noindex` while public registration is unavailable. Replace that explicit pre-release state with complete policies and verified deletion instructions before enabling accounts. The site does not invent legal operator details.

HTTP integration tests exercise all page/language combinations, security headers, language navigation/negotiation, unavailable legal content, assets, missing routes, HEAD, and rejected write methods.
