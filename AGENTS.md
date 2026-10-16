# Project instructions

Read `~/.agents/AGENTS.md` for global instructions.

This is a native SwiftUI habit tracker for iOS, with a macOS companion and WidgetKit extensions. The owner selected the product name Avvi and the public repository turinglabsorg/avvi.

- Read `DESIGN.md` before changing UI.
- Use default system typography throughout app, widgets, and icon. Do not introduce serif or editorial typefaces.
- Keep the pure domain and scheduling logic in `Core/`; it must run under Swift Package Manager tests.
- App and widget share their SwiftData schema in `Shared/`.
- Never label simulated, disconnected, or unverified integrations as synchronized.
- Calendar completion and habit completion are separate concepts. Only explicit user logging changes progress.
- Calendar writes require a visible user confirmation and must be idempotent.
- All documentation and code are in English. The initial app interface is Italian.

## Architecture and current capabilities

- `Core/HabitEngine.swift` derives daily quantities and streaks from timestamped activity entries using the habit's stored time zone. Quantities can exceed the target; only the visual fraction is capped. An unfinished today preserves yesterday's current streak.
- `Core/ScheduleEngine.swift` is an explainable local scheduler. It searches 07:00–22:00 in 15-minute intervals, avoids busy periods and other proposals, and uses historical logging hours only with at least five prior-day samples from the previous 28 days. There is no LLM service or HTTP backend.
- `Shared/Models.swift` defines `Habit` (target, step, unit, preferred hour, duration, time zone, archive/demo flags) and `Activity` (UUID, habit UUID, amount, timestamp, source). App and widgets use App Group `group.org.turinglabs.avvi`. Insert activity records rather than overwriting daily totals.
- `CloudSyncEnabled` is an explicit Boolean Info.plist property for each target in `project.yml`. It is false by default. The private CloudKit path is prepared but unverified; do not enable it or claim cloud sync without provisioning and multi-device checks.
- `App/CalendarService.swift` handles EventKit permissions, selected availability calendars, a writable destination, event-store change observation, and confirmed block creation. `avvi://plan/<habit-uuid>-<start-epoch>` identifies app-created events. Preserve idempotency and recheck conflicts at save time. Direct Google OAuth and complete calendar lifecycle reconciliation are not implemented.
- `App/` provides Today, Trends/detail, Planner, Connections, habit creation, and archive/restore. After archiving, detail shows confirmation and an explicit return action; avoid combining automatic source-list removal with an additional navigation dismissal.
- `Widget/AvviWidget.swift` provides small and medium iOS/macOS widgets with `LogHabitIntent`. Both extensions share the model schema and logging operation. Timeline reloads are requests to the OS, not guarantees of instant delivery.
- `--demo` seeds only an empty archive; demo data must remain labeled. `--ui-testing` uses an in-memory archive. Never seed production launches automatically.

## Project generation and verification

- `project.yml` is the source of truth for the checked-in Xcode project. Regenerate with `xcodegen generate` after target/configuration changes.
- Apple targets are `Avvi`, `AvviWidget`, `AvviMac`, and `AvviMacWidget`. Minimum deployment targets are iOS 17 and macOS 14. No personal signing team is stored in the project.
- `swift test --disable-sandbox` runs domain and shared-store persistence tests. The iOS `AvviUITests` target exercises creation, logging, undo, archive/restore, screens, and integration status.
- `AvviCalendarTests` runs only in Simulator with calendar permission. It creates and removes an isolated temporary calendar to verify real event creation, idempotency, and conflict rejection. Never redirect it to personal calendars or remove its physical-device guard.
- See `docs/validation.md` for tested behavior and unresolved device/cloud boundaries. Update those claims when integration coverage changes.
