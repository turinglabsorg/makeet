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
- Cards: 20 pt radius. Small marks: 4–6 pt. Buttons: 14 pt.
- Touch targets: at least 44 pt. Use Dynamic Type and VoiceOver labels. Colors always accompany values or symbols.

## Screens

- Today: date, native heading, daily progress, quantitative habit cards, and 14-day intensity marks.
- Trends: per-habit metrics, a daily quantity chart, an hourly distribution, and a 12-week intensity grid. Denominators exclude future and pre-creation days.
- Planner: explicit calendar source state, explainable free-slot proposals, and a review step before writing an event.
- Connections: actual calendar access, explicit notification opt-in, and honest service integration states. Keep OS notification permission, APNs device registration, and server delivery visibly distinct.

## Interaction

Place minus on the left and plus on the right of habit content. Each plus records one timestamped entry using the habit's chosen step. Minus subtracts that step from today's newest entries, stops at zero, and is disabled when empty. Detail undo still removes an individual entry. Reaching a target never prevents additional logging. A planned calendar block never marks a habit complete. Widgets share these rules, with two rows in medium widgets to preserve 44-point controls.

Habit appearance offers SF Symbols or a single emoji, including composed emoji and flags. Preserve native emoji colors. Keep all app-owned text in the five-language catalogs and allow translated labels to wrap; dates and quantities follow the system locale. User-entered habit names and units remain unchanged. Blank state offers creation; demo data is opt-in and visibly labeled.

## Public website

Use the same warm canvas, forest ink and native system sans typography. The home page combines a large action-led heading, a labeled native app screenshot and a small intensity grid, followed by numbered feature rows and native expandable FAQs. Keep navigation and language switching keyboard accessible; stack the hero and feature columns on narrow screens. All visible copy supports the same five languages. Clearly label pre-release availability and illustrative data; show a download link only after verified availability.

## First-run onboarding

A guided native onboarding opens with a clearly labeled miniature day preview, then asks where progress should live. A three-segment progress line and a persistent bottom action make the route visible. Short explanations introduce quantities, statistics and confirmed calendar planning. The account and local-only choices start unselected. Account mode shows Apple/Google access with policy links and honest errors; local mode requires an explicit continue action and explains the absence of cross-device sync. Language is available from the first screen. Calendar and notification permission requests are deferred until a user chooses their respective features. Preserve existing archives and do not upload demo or local data implicitly.


## Identity and profile

Version2 of onboarding is shown once after updating as well as on a fresh install; it preserves archives, language and active sessions. Welcome, explicit account/local choice, provider access and a final first-habit guide use a shared 520-point content column, generous spacing, 26-point preview cards and 56-point bottom actions. Existing authenticated users retain their session and move from welcome to the final guide. Keep the current onboarding step outside the archive identity boundary so successful authentication does not restart the guide.

Apple and Google access share equal width, 54-point height and a 15-point corner radius. Google uses its unmodified official multicolor mark with a neutral light/dark surface and a five-language Continue with Google label; its authorization browser remains provider-owned. The Google mark is distributed under the pinned SDK's Apache2 license in Resources/GoogleSignIn-LICENSE.txt.

An authenticated account opens with a centered circular photo, display name, email and a private-account label. The same photo appears in Today's Account button. Initials or a person symbol are an explicit fallback when no image exists. The editor uses the system photo picker, a name field and explicit Save; no broad photo-library permission prompt is required. Google profile images are imported only for an empty Makeet profile. Apple does not supply an image; the owner can choose one. All profile data remains private to the account.
