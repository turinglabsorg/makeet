# Product foundation

## Intent

Help people build sustainable daily habits with a clear visual history and a schedule that adapts to real availability. Everyday is a reference for immediate visual comprehension, not a source of copied interface assets or branding.

## Public audience and accounts

Makeet is intended to be a publicly available product. Anyone must be able to register through self-service sign-up without an invitation or an administrator-created account. Each account has its own private habits, activity history, statistics, calendar connections, and assistant context.

Native archives support local use and isolated account stores. Apple/Google providers and the Go sync service are configured; the owner confirmed fresh Apple login through TestFlight. Real Google login and signed multi-device sync remain release checks.

The custom Go backend is required and will run on the owner's Mac Pro. The Makeet service and its persistent data must remain isolated from other projects on that machine.

## A richer completion model

A habit owns a daily target, measurement unit, logging increment, home time zone, preferred hour, and session duration. Each activity records its own identifier, habit identifier, positive quantity, timestamp, and source. Completion is derived from the sum of that day's activity quantities. A target of one represents a conventional yes/no habit without requiring a separate completion flag.

Examples: water 8 glasses with a step of 1; reading 20 pages with a step of 5; movement 30 minutes with a step of 10. Additional activity beyond a target remains visible in totals. Intensity visualization caps at 100 percent; the underlying quantity does not.

Daily boundaries use the habit's stored time zone and calendar-day arithmetic, including 23-hour and 25-hour daylight saving days. Habit editing supports appearance, measurement, preferred time/duration, start date and selected weekdays. Current target/weekday definitions apply to historical statistics, explicitly disclosed in the editor; quantities remain unchanged. Effective-dated target/schedule history is a future enhancement.

## Analytics

Daily quantity and registration frequency are distinct. Statistics expose total quantity, average per observed day, days reaching the target, completion rate, days with any activity, current streak, best streak, intensity, and logging hour distribution. Windows exclude days before the habit was created and future days. Today is included in the completion-rate denominator; an unfinished today does not break yesterday's current streak until the day ends.

Hourly patterns describe logging behavior. They do not establish causal recommendations or prove the most effective time for an activity.

## Assistant behavior

The engine proposes one session per selected day for each incomplete, unplanned habit across1/7/14/28 days. Sessions stay between 07:00 and 22:00 in the habit's home time zone, use a 15-minute search grid, avoid busy intervals, and do not overlap one another. The closest free slot to the preferred hour wins; ties select the earlier slot.

After at least five historical registrations, the preferred hour is replaced by the most frequently logged hour during the previous 28 days. Ties select the earlier hour. Every proposal explains whether it used preference or recorded history. A session is a suggested opportunity, not an assertion that it will satisfy the remaining daily quantity.

Calendar access is optional. Without it, proposals explicitly say availability is unknown. With it, the user selects considered calendars and a write destination. Every event requires review and confirmation. Busy state and future time are checked again immediately before saving. Existing Makeet blocks suppress duplicate same-day proposals. There is no external language model in this version.

## Next product milestones

1. Implement open self-service registration, login/logout, account management, and per-account data isolation. Use the custom Go backend on the Mac Pro.
2. Implement account-based synchronization and safe local-cache migration across iPhone, Mac, and widgets. Decide the role of the prepared CloudKit path before enabling another sync authority.
3. Validate widget increments against the foreground app and after relaunch on each platform.
4. Complete calendar lifecycle reconciliation: move, cancel, recurrence, external edits, stable mappings, provider failures, and time-zone travel policies.
5. Add direct Google OAuth and incremental synchronization for accounts not configured on the device.
6. Add effective-dated goal/schedule history and weekly targets. Selected weekdays, monthly heatmap, historical quantity correction and JSON export are implemented.
7. Expand insights to weekday comparisons, trends against previous periods, goal consistency, and user-approved adaptive preferences.
8. Add notification controls and opt-in background assistance with a visible activity history.

The first release must state actual sync freshness and failures. It must not promise instantaneous delivery from iCloud or WidgetKit scheduling.


## Local and Plus access

Local habit tracking is unlimited and free, including weekdays, progress correction, statistics, calendar planning, archive/restore and permanent deletion. Approved Plus pricing is EUR 1.99/month or EUR 11.99/year in Italy. Account synchronization across devices is the only Plus feature; it becomes paid only when billing is deliberately enabled after store validation. The current TestFlight preview keeps billing off. Expiry preserves cached data and all account/data-export/deletion controls. Purchase prices come from StoreKit and disclose the full annual amount; no mandatory trial is configured.
