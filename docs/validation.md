# Validation

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
- Provider credentials, authenticated device registration, scheduling, and delivery to a signed installation remain unverified.

## Quantity controls, appearance, and languages

Four Simulator UI scenarios verify left-minus/right-plus ordering, decrement to zero, disabled empty-state controls, creation using an emoji, existing detail undo/archive/restore, and localized navigation/creation in Italian, English, French, German, and Spanish. Screenshots of all five languages were rendered; the German layout and emoji creation were visually inspected.

Native catalogs contain 203 keys across the interface and permission descriptions. Validation checks all five translations, interpolation types, and coverage against compiler-extracted app/widget strings. User-authored names and units are preserved. Additional languages can be added in Xcode's string catalogs without new runtime branching.

Development-signed build 0.1.0 (2), containing these changes, was installed as an update and launched on the owner's physical iPhone. The existing app data container was retained. Physical widget placement, widget button interaction, and complete device permission/calendar flows remain separate checks.

## Push foundation verification

- Five Simulator-hosted tests cover no permission prompt during refresh, explicit consent, updated tokens, denied/revoked permission, APNs registration failure/retry, and permission-request errors.
- The Connections UI scenario confirms the notification permission row exists and no system alert appears on opening the screen.
- Both platform applications and widget extensions compile with the APNs configuration. These unsigned builds do not establish provisioning or APNs delivery.
- Provider credentials, authenticated device registration, scheduled delivery, and notification presentation on a signed installation have not been validated.
