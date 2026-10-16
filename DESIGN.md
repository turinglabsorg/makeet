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
