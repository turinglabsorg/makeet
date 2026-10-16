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
- Connections: actual calendar access and honest CloudKit/Google integration states.

## Interaction

Increment buttons record one timestamped entry using the habit's chosen step. Undo removes the most recent entry for that day. Reaching a target never prevents additional logging. A planned calendar block never marks a habit complete. Widgets use the same model store and logging rules as the app. Blank state offers creation; demo data is opt-in and visibly labeled.
