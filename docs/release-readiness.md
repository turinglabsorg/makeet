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
| Subscription billing | Approved EUR 1.99/month or 11.99/year; StoreKit2 and Go account-bound JWS entitlements implemented; local StoreKit/backend tests | Keep billing disabled until product metadata/availability, signed notifications, real App Store Sandbox flows, certificate-revocation policy and individual cloud erasure after subscription expiry are verified. Charging is not enabled |
| Hosting | Dedicated service, health routes, rate-limit/ownership tests, backup and isolated restore drill | Final production configuration and account-lifecycle operational check |

Automated fixtures use generated test identities and isolated storage. They do not substitute for real provider or multi-device validation. Never use a real owner's account for destructive lifecycle checks.

## App Store Connect audit

The record is `Makeet`, iOS version1.0, Prepare for Submission. Current TestFlight version is0.1.0, so the release build and store version must be aligned before submission.

- Product description, keywords, support/marketing URLs and copyright are unset. Store localizations and screenshots still need preparation; the audited Italian iPhone screenshot slot contains zero images.
- No release build is selected. Review contact, access instructions and reviewer notes are unset. The app supports local use and provider login; do not supply the owner's Apple password to reviewers.
- App Privacy has no policy URL and its data-collection questionnaire has not been started, although the five-language public website policies are live.
- Primary category, content rights and age rating are unset.
- Pricing and territory availability are not configured. Public distribution is selected; compatible Mac/Vision distribution defaults need a conscious release decision and validation.
- The account is marked as a trader. Review the public seller/contact information before publication, preserving the owner's restrictions on personal data. Do not infer authorization to publish addresses or personal contact details from this existing selection.
- Submit only after the release checks pass, then track Apple's review and the chosen release action. A successful TestFlight upload does not publish the app.
