# Design system

## Direction

A calm native tool for personal momentum. Warm surfaces, forest ink, precise colored marks, and clean system typography. Use native system typography throughout. The product is about sustainable progress and adapting a day, not punishment for broken chains. The identity is original; everyday is a functional reference only.

## Tokens

- Canvas: #F7F5EF, card: #FFFFFF, ink: #233B32, secondary ink: #68746A.
- Accent: #376B50; habit colors: forest #4C8061, blue #658CAC, amber #C69343, clay #B87358.
- Pale accent surface: #E8EDE2; border: #E4E6DE.
- Dark appearance: charcoal green canvas with light ink and muted green surfaces.
- Headings: native San Francisco, semibold, using the largeTitle and title Dynamic Type styles. Body: San Francisco, 15–17 pt using semantic styles. Numerical values use monospaced digits. Use the default system design throughout the app, widgets, and app icon; avoid serif, editorial, or display typefaces.
- Spacing scale: 4, 8, 12, 16, 20, 24, 32.
- Cards: 16 pt radius with 10–12 pt insets. Small marks: 4–6 pt. Buttons: 14 pt.
- Touch targets: at least 44 pt. Use Dynamic Type and VoiceOver labels. Colors always accompany values or symbols.

## Screens

- Today: date, native heading, daily progress, quantitative habit cards, and 14-day intensity marks.
- Trends: per-habit metrics, a daily quantity chart, an hourly distribution, and a 12-week intensity grid. Denominators exclude future and pre-creation days.
- Planner: explicit calendar source state, explainable free-slot proposals, and a review step before writing an event.
- Connections: actual calendar access, explicit notification opt-in, and honest service integration states. Keep OS notification permission, APNs device registration, and server delivery visibly distinct.

## Interaction

Place minus on the left and plus on the right of habit content. Each plus records one timestamped entry using the habit's chosen step. Minus subtracts that step from today's newest entries, stops at zero, and is disabled when empty. Detail undo still removes an individual entry. Reaching a target never prevents additional logging. A planned calendar block never marks a habit complete. Widgets share these rules, with three 44-point rows in medium widgets, one habit in small widgets and up to six in large widgets. Medium widgets omit a decorative header and use 8-point margins. Zero confirmation occupies the leading control, stays checked after confirmation and never implicitly records another entry; retain a separate decrement when signed quantities are enabled.

Habit appearance offers SF Symbols or a single emoji, including composed emoji and flags. Preserve native emoji colors. Keep all app-owned text in the five-language catalogs and allow translated labels to wrap; dates and quantities follow the system locale. User-entered habit names and units remain unchanged. Blank state offers creation; demo data is opt-in and visibly labeled.

## Public website

Use the same warm canvas, forest ink and native system sans typography. The home page combines a large action-led heading, a labeled native app screenshot and a small intensity grid, followed by numbered feature rows and native expandable FAQs. Keep navigation and language switching keyboard accessible; stack the hero and feature columns on narrow screens. All visible copy supports the same five languages. Clearly label pre-release availability and illustrative data; show a download link only after verified availability.

## First-run onboarding

A guided native onboarding opens with a clearly labeled miniature day preview, then asks where progress should live. A three-segment progress line and a persistent bottom action make the route visible. Short explanations introduce quantities, statistics and confirmed calendar planning. The account and local-only choices start unselected. Account mode shows Apple/Google access with policy links and honest errors; local mode requires an explicit continue action and explains the absence of cross-device sync. Language is available from the first screen. Calendar and notification permission requests are deferred until a user chooses their respective features. Preserve existing archives and do not upload demo or local data implicitly.


## Identity and profile

Version2 of onboarding is shown once after updating as well as on a fresh install; it preserves archives, language and active sessions. Welcome, explicit account/local choice, provider access and a final first-habit guide use a shared 520-point content column, generous spacing, 26-point preview cards and 56-point bottom actions. Existing authenticated users retain their session and move from welcome to the final guide. Keep the current onboarding step outside the archive identity boundary so successful authentication does not restart the guide.

Apple and Google access share equal width, 54-point height and a 15-point corner radius. Google uses its unmodified official multicolor mark with a neutral light/dark surface and a five-language Continue with Google label; its authorization browser remains provider-owned. The Google mark is distributed under the pinned SDK's Apache2 license in Resources/GoogleSignIn-LICENSE.txt.

An authenticated account opens with a centered circular photo, display name, email and a private-account label. The same photo appears in Today's Account button. Initials or a person symbol are an explicit fallback when no image exists. The editor uses the system photo picker, a name field and explicit Save; no broad photo-library permission prompt is required. Google profile images are imported only for an empty Makeet profile. Apple does not supply an image; the owner can choose one. All profile data remains private to the account.


## Calendar and habit management

Today has a 44-point plus control on the left and a circular 34-point avatar inside a 44-point control on the right; omit visible Account text. Archive is reached through Connections. Keep language immediately after the account section. Habit creation/editing places a date and seven localized weekday pills immediately below appearance, with at least one selected day required. Explain that target/weekday changes apply to historical statistics while recorded quantities are preserved.

Calendar uses a seven-column month with intensity, numeric completed/expected goals, a selected-day outline, date detail and separate calendar events. Future dates show calendar planning rather than failed completion. Past/today edits use a draft with minus left, plus right and explicit Save/Cancel. Permanent deletion has a named review sheet, irreversible-progress warning and a separate optional Makeet-event cleanup toggle. Show an immutable success state after deleting.

Planner uses natural-language Today/next-days headings, a1/7/14/28-day horizon and a complete batch review before calendar writes. Hide the connected-calendar success banner. Connections explains that tracking, planning and private account synchronization are free. Omit Plus entry points and purchase prompts in the current release.

The public landing includes a labeled illustrative month panel alongside localized weekday selections (Monday, Tuesday and Thursday); static samples must never look interactive or use real account data. Display numeric completed/expected goals alongside intensity, plus a less/more legend. The hero uses the current native iPhone demo screenshot, explicitly identified as Italian in every locale. Explain the internal TestFlight preview, device-configured calendars, confirmed 28-day planning and free access in localized copy; avoid public download or purchase buttons before verified availability.

Account deletion uses the stable native confirmation dialog with a clear permanent-erasure warning and immediate destructive action; retain native outside dismissal where the system presents a popover.

## App Store creative assets

Header and search artwork use the existing warm canvas, forest ink, pale accent circle, original app icon, system sans typography and unmodified native demo captures. Keep short localized copy and the Today/Calendar composition inside the inset safe region of the 5244 × 2950 opaque header PNG. Use a separate 3840 × 2560 search composition with larger content. Verify both placement previews in Apple before delivery. The separate screenshot gallery shows the application in use; never substitute reconstructed interfaces or include private account data.

## Flexible goals and signed quantities

Place the goal-direction segment and optional negative-values switch with the quantitative controls. Minimum goals retain the familiar positive target; limit goals allow zero and explain explicit confirmation. Unlogged limit days use a neutral “To confirm” status. Confirmed zero is green; excess above a limit or a negative minimum balance uses the clay warning color and a textual malus amount. Keep numeric values visible alongside color. Minus remains left and plus right, including the calendar correction draft; only explicitly enabled habits can go below zero. Limit habits do not show calendar action scheduling controls. Provide a keyboard Done action so the whole form remains reachable on a phone.


## Android native client

Use Jetpack Compose with Android system sans typography and the same warm/forest tokens, 20-dp cards, 54-dp provider buttons and 48-dp touch controls. Preserve platform photo/document pickers, permission dialogs and Home Screen widgets. The plus/avatar toolbar, explicit account/local onboarding, Monday-first weekday pills, quantity/limit controls and confirmed calendar planning follow the shared product rules. Keep demo status visible above every main tab and label disconnected planning as illustrative. RemoteViews widgets show two habits with numeric progress and the same minus/plus/zero behavior. Request a four-column/two-row default on modern launchers, retain at least 208 dp for both 48-dp controls and use pale forest button surfaces. Android reminders use an explicit local-notification description; do not reuse APNs registration wording.

## Password access

Offer a 54-point password-access action alongside the available identity providers. Android offers Google and password access; iOS retains Apple as well. Password access opens in a dedicated sheet hosted by the stable Connections or Onboarding root; do not expand changing-height credential forms inside a Form row. Registration asks for username, recovery email, password and confirmation, then an explicit email-code confirmation. Explain username and password bounds before submission. Passwords stay in transient view state and use native secure fields and autofill hints. Recovery has its own explicit identifier/code/new-password route. Generic request acceptance does not disclose account existence. Show actionable retry messages without dismissing a draft or changing the archive on failure.

Existing-account enrollment belongs in Account, presented from the stable Connections navigation container. Bind enrollment to the original account and show confirmation before returning. Registration explains how existing provider users can add credentials without creating a second account. Never merge accounts based only on a matching email.


## Compact progress overview

Today uses 16-point page margins, 8-point gaps between habit rows and a 44-point daily summary ring. Each habit row retains 44-point leading/trailing controls, a name/quantity/status stack and a six-point 14-day history strip. Zero-limit confirmation appears as a square checkbox in the leading-control position and remains visibly checked after explicit confirmation. Do not remove signed decrement controls.

Trends presents one compact row per habit with monthly daily strips for the last three complete calendar months and the current month. Empty and pre-creation periods remain visible as empty outlines, without invented activity or statistical denominators. Future days remain empty. Retain quantity totals, streaks, malus coloring and navigation to the existing detailed statistics. Month values are available to accessibility.

Planner actions fill the content width; day events and all shared journal cards stretch to that same width. Use 12-point section spacing rather than large decorative gaps, while preserving full confirmation before calendar writes.
