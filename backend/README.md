# Makeet backend

Custom Go HTTP service with SQLite storage. Apple and Google provide identity; Makeet owns accounts, sessions, authorization, and the sync log. No hosted authentication platform or email/password login is used.

## Status

The HTTP service and integration tests run locally. The native app currently uses its local SwiftData archive and is not connected to these APIs. Provider clients, Apple grant revocation, account-scoped native caches, and production deployment must be completed before public registration.

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

Unconfigured providers reject authentication. Public client IDs are not secrets. Keep any future signing keys/provider secrets in hush, never source control. Do not add fixture issuers or development-token bypasses to runtime configuration.

SQLite uses foreign keys, WAL, a busy timeout, and a single connection. Database directories are created with mode 0700 and the main database with mode 0600. Keep data on the Mac Pro's local disk and back up SQLite using an online backup or a stopped service, including its journal state. Do not copy only the main database file while the service writes.

## Identity and sessions

1. `POST /v1/auth/challenges` with `provider` returns a one-use challenge ID, nonce, and five-minute expiry.
2. Pass that nonce to the native identity provider request. The signed ID token must contain exactly that nonce.
3. `POST /v1/auth/exchange` with `provider`, `challenge_id`, and `id_token` verifies signature, issuer, allowed audience, expiry, subject, and nonce, then consumes the challenge atomically.
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

Account deletion cascades through identities, sessions, access-token hashes, habits, activities, changes, and cached mutation responses. Revoking Apple authorization still requires its server token-exchange/revocation integration and a signing key. This endpoint alone is not the complete Sign in with Apple deletion lifecycle.

## Synchronization

`POST /v1/sync` accepts an integer `cursor`, a UUID `mutation_id` for writes, and up to 100 `changes`. Each change carries `kind` (`habit` or `activity`), UUID `id`, last-seen `revision` (zero when creating), `deleted`, and `data`. Ownership is always derived from the bearer session.

The service normalizes UUIDs, validates quantities and timestamps, orders habits before activities, and checks that an activity references the same account's non-deleted habit. Every mutation batch is atomic. A stale revision returns HTTP 409 with the current records for that account; no part of the batch is applied. The caller must resolve conflicts explicitly.

Repeating an identical mutation ID/request returns the original response. Reusing the same mutation ID with different content returns HTTP 409. Keep pending mutation payloads durable and unchanged until acknowledged. Sync history is retained, so a new device can start at cursor zero.

The response includes `applied` revisions, up to 200 incremental `changes`, the next `cursor`, and `has_more`. Continue pulling until `has_more` is false. Records may appear multiple times in history; apply their latest revision. Deletions produce tombstones. Deleting a habit does not erase its activity history automatically. Archive habits to preserve history; permanent removal must explicitly delete the associated records.

Quantitative logging uses a new UUID per activity, so simultaneous independent logs remain separate entries. Clients must not overwrite a daily total.

## Verification and deployment boundaries

Tests use generated RSA keys, a real local JWKS HTTP server, signed JWTs, an actual API HTTP server, and temporary on-disk SQLite databases. Coverage includes signature/audience/issuer/nonce/expiry rejection, challenge replay, account separation, refresh replay revocation, logout, access/session expiry, atomic conflicts, idempotent retries, tombstones, pagination, durability, and deletion cascades. `go test -race ./...` passes.

HTTP requests have body/header/time limits; authentication routes are rate-limited using the socket peer IP. Do not trust arbitrary forwarded headers. Behind a shared relay the socket-peer limit is shared by callers, so trusted client-IP routing/rate limits must be finalized before opening registration. Provider token revocation, encrypted provider-credential storage, backup/restore drills, legal publication, native account isolation, and multi-device sync remain release requirements.
