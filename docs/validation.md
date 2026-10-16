# Validation

Validated on 16 October 2026 using Apple Swift 6.4, an iPhone 16 Pro Simulator running iOS 18.5, and the installed macOS SDK.

## Verified behavior

- 15 Swift Package Manager tests cover quantitative logging, extra activity beyond a target, day boundaries around both daylight saving transitions, observed-day denominators, current/best streaks, invalid entries, scheduling collisions, historical preferences, exhausted availability, and persistence between independent model containers.
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
- Provider credentials, authenticated device registration, scheduling, and delivery to a signed installation remain unverified.

## Push foundation verification

- Five Simulator-hosted tests cover no permission prompt during refresh, explicit consent, updated tokens, denied/revoked permission, APNs registration failure/retry, and permission-request errors.
- The Connections UI scenario confirms the notification permission row exists and no system alert appears on opening the screen.
- Both platform applications and widget extensions compile with the APNs configuration. These unsigned builds do not establish provisioning or APNs delivery.
- Provider credentials, authenticated device registration, scheduled delivery, and notification presentation on a signed installation have not been validated.
