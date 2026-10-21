# Username and password accounts

The owner authorized username/password authentication on 21 October 2026 in addition to existing provider identities. iOS retains Apple and Google; Android offers Google and password access and no longer exposes the Apple web handoff. The Go service remains the only session and synchronization authority. Existing provider identities, user UUIDs and account archives are unchanged.

## Registration and recovery

Usernames use 3–32 lowercase ASCII letters, digits, dots, hyphens or underscores and start with a letter or digit. Login accepts the username or recovery email without case sensitivity. Passwords contain 15–128 Unicode code points, may include spaces, are never trimmed and are not stored by either native client. The backend stores salted Argon2id hashes with 64 MiB memory, three passes and two lanes; at most two password operations run concurrently.

Registration stores a pending request, not an account. An eight-digit cryptographically generated email code confirms the request within 15 minutes and at most ten failed attempts. Only hashes of codes are persisted. Confirmation creates the account; native clients then use the normal session installation and account archive activation path. Session tokens retain their existing 15-minute access and fixed 30-day rotating-refresh lifetime.

Recovery returns the same accepted response for known and unknown identifiers. A valid recovery code replaces the password, advances the credential version, revokes all sessions, removes push-device registrations and consumes outstanding requests. Existing data remains in the same user account. Clients sign in using the replacement password after confirmation. Expired, replayed, superseded or exhausted codes fail. Incorrect enrollment codes return 400 rather than a session-authentication 401, preserving the authenticated account.

## Existing accounts

An authenticated user chooses **Username and password** in Account, supplies a new unique username, a recovery email and password, then verifies that email. The pending request is bound to that authenticated user UUID and can only be confirmed by the same account. It adds credentials to that user rather than creating or merging accounts. A matching email address never authorizes linking two provider identities. Users who already have password access can inspect their username and use the recovery flow to replace the password.

## HTTP protocol and storage

Public endpoints:

- `POST /v1/auth/password/register`: username, email, password and language; returns 202 and `request_id`.
- `POST /v1/auth/password/login`: identifier and password; returns the existing session/token response.
- `POST /v1/auth/password/recover`: identifier and language; returns 202 and `request_id`.
- `POST /v1/auth/password/confirm`: request_id, code and an optional replacement password; confirms registration or recovery.

Authenticated endpoints:

- `GET /v1/me/password`: this account's enabled status, username and recovery email.
- `POST /v1/me/password`: begins adding credentials to this account.
- `POST /v1/me/password/confirm`: consumes that account's enrollment request.

Schema 7 adds `password_credentials`, `password_requests` and `password_attempts` without changing existing records. User-owned credentials and pending requests cascade on account deletion. Indexed expiry, email and user columns bound request lookup and cleanup. Authentication is limited by trusted client address, persisted identifier attempts and recipient/account email quotas. Pending requests and identifier counters are capped at 10,000. Generic accepted responses do not confirm whether a username or email has password access.

## Resend configuration

The owner selected the dedicated email domain `noreply.makeet.app`. The sender is `Makeet <noreply@noreply.makeet.app>`. `MAKEET_EMAIL_FROM` is an allowed public option in the private runtime configuration; `MAKEET_RESEND_API_KEY` must be injected from hush and is forbidden in that configuration file. The provided send-only key is held as hush `MAKEET_RESEND_API_KEY`.

Both values must be configured together; invalid configuration fails startup. Without a mailer, `/v1/config.password_enabled` is false and native clients omit password entry points. Email uses only the fixed HTTPS Resend endpoint, refuses redirects and accepts a bounded receipt. Messages are localized in Italian, English, French, German and Spanish and contain a temporary code, never passwords or habit data. The privacy notice identifies Resend and these data boundaries.

A live request using the selected sender was accepted by Resend's official `delivered@resend.dev` simulator on 21 October 2026. This establishes provider acceptance for the sender, not receipt in an end user's inbox. The key intentionally cannot read domain configuration. Public DNS already contains the domain's DKIM record; no DNS changes were needed for the accepted smoke test.

## Validation boundaries

Actual HTTP integration tests cover verification before login, username/email ownership, independent account data, recovery revocation, expiry/replay, failed delivery, bounded code attempts, persisted brute-force limits and authenticated enrollment. Native fixtures use intercepted `.invalid` hosts and isolated storage, are restricted to Debug Simulator/emulator builds and must be absent from distribution binaries. Native UI checks exercise explicit entry, cancellation, error correction, session reopening and recovery. Real user inbox receipt and signed-device validation remain separate from fixtures and provider acceptance. The already-approved iOS 1.0 build 14 does not contain this feature; a new native build must complete its required release pipeline.
