# Release readiness

Last audited: 2026-10-18. The website/API are online and internal TestFlight distribution is active. The iOS app has not been submitted to App Review.

## Required product validation

| Area | Established evidence | Remaining release check |
| --- | --- | --- |
| Apple identity | Owner confirmed fresh Apple authentication on TestFlight0.1.0(2); archive lifetime regressions run in CI | Full signed-device lifecycle, revocation and deletion using a disposable test account |
| Google identity | Provider configured; SDK callback covers onboarding and main UI | Complete real Google consent, return, logout/relogin and initial profile import |
| Profile | HTTP ownership/revisions/image validation and native normalization/cache tests | Simulator UI now covers navigation/save/cancel/reopen, failure/conflict, onboarding and system photo selection/removal; signed-device verification of the corrected build remains |
| Account sync | HTTP/database and durable retry/conflict tests | Two signed devices exchanging real habit/activity changes, offline recovery and account isolation |
| Habits/statistics | Creation, quantity controls, undo, archive/restore and five-language UI tests; domain/persistence tests | Final signed release smoke test, iPad layout and accessibility review |
| Calendar | Explainable local proposals and isolated EventKit integration | Real permission, selected calendar, confirmed creation, conflict and duplicate handling. Google calendars currently use accounts configured in iOS; direct Google Calendar OAuth/incremental reconciliation is unimplemented |
| Notifications | Encrypted device registration, APNs sender and receipt/retry tests; Sandbox credential | Provision production APNs and verify TestFlight receipt/reminder behavior on a device |
| Widgets/macOS | Shared model/intent logic and iOS/macOS compilation | Home Screen and desktop interaction, timeline/account-switch behavior and native macOS authentication |
| Subscription billing | Approved EUR 1.99/month or 11.99/year; StoreKit2 and Go account-bound JWS entitlements implemented; local StoreKit/backend tests | Keep billing disabled until product metadata/availability, signed notifications, real App Store Sandbox flows, signed notification delivery and real expiry/account-erasure checks are verified. Charging is not enabled |
| Hosting | Dedicated service, health routes, rate-limit/ownership tests, backup and isolated restore drill | Final production configuration and account-lifecycle operational check |

Automated fixtures use generated test identities and isolated storage. They do not substitute for real provider or multi-device validation. Never use a real owner's account for destructive lifecycle checks.

## App Store Connect audit

The record is `Makeet`, iOS version1.0, Prepare for Submission. Current delivered TestFlight is0.1.0(10). Source is aligned to1.0for the next candidate; no release build is selected and no App Review submission has been made.

- Descriptions, promotional text, keywords, subtitles and support/marketing URLs are saved in Italian, English, French, German and Spanish; copyright is2026Meaningtech. Native screenshots are prepared and visually reviewed for the required iPhone6.3-inch and iPad13-inch slots, plus optional iPhone6.9-inch in all five languages; Store uploads are in progress.
- Reviewer instructions explain optional local use and Apple/Google access. Sign-in is not required for core local features. Manual release is selected. Private reviewer contact details still need an approved contact; never supply an owner's provider password.
- Policy and privacy-choice URLs are saved for all five locales. The App Privacy questionnaire includes both Makeet and the pinned Google sign-in SDK's declared collection, including provider analytics. It is configured but not yet published; the updated notice must be verified in deployment first.
- Primary category isProductivity, content rights are configured and the saved age questionnaire produces9+for self-care/wellness topics, with no medical guidance, social distribution, ads or mature content.
- Plus monthly/yearly products and five-language product/group localizations are configured at the same service level. Approved Italy reference prices remainEUR1.99/month andEUR11.99/year. Both use individual App Store purchases; multiseat/Business/School Manager purchases are disabled, and the annual uses upfront billing. Current175territories are selected for subscriptions; future-territory expansion is off. The free app's price/territory and compatible Mac/Vision distribution settings still require final review.
- Production and Sandbox notification URLs point to the implemented HTTPS endpoint. This is URL registration, not delivery proof.
- Free Apps Agreement isActive; Paid Apps Agreement isNew. Acceptance is pending the account holder's explicit confirmation. Banking/tax completion must then be verified.
- Streamlined outside-app purchasing is currently on. Apple refuses to turn it off until a supporting binary is approved. The candidate handlesPurchaseIntent; after approval, turn off streamlined purchasing before the manual public release because purchases require a Makeet account binding.
- The account is marked as a trader. Public professional address/phone details still require the owner's approval; do not publish previously supplied personal contacts from the existing account.
- The production APNs key is staged for specific Makeet topics, with creation/custody approval pending. Real receipt/reminder checks remain mandatory.
- Submit only after release checks and business/contact requirements pass. A successful TestFlight upload does not publish the app.
