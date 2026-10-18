# Native CI and TestFlight

The Makeet TestFlight workflow is configured in Xcode Cloud. It runs on changes to `main` and permits manual builds of that branch only. Pull-request and tag distribution are disabled. A completed cloud run and a processed build in the internal group are required before describing a particular version as available.

## Repository checks

`ci_scripts/ci_post_clone.sh` requires the iOS 27 SDK, validates all five language catalogs and runs the domain, account-client and persistence package tests. It does not read or upload credentials.

`ci_scripts/ci_post_xcodebuild.sh` preserves native-action failures and validates compiler-extracted app/widget strings against the translated catalogs. Missing extracted strings fail build actions. Separate test-without-building workers validate their iOS27 destination and preserve test failures without expecting unavailable compilation intermediates.

The checked-in Xcode project and pinned Swift package resolution are the cloud build inputs. Keep `project.yml` and the generated project consistent. Never enable a production test-token sign-in path for cloud tests.

`TestFlight/WhatToTest.<locale>.txt` supplies tester notes in Italian, English, French, German and Spanish through Apple's native Xcode Cloud import. Keep these focused on current changes, device checks and truthful integration boundaries.

## Distribution workflow

The configured iOS product is `org.turinglabs.makeet`, using `turinglabsorg/makeet`. Xcode 27 is pinned, with a required test action on an iPhone 16 Pro Simulator running iOS 27.0 and an App Store Connect archive action. Internal TestFlight distribution uses the archive only after the required actions succeed. The archive uses automatic Apple-managed signing. Xcode Cloud manages monotonically increasing build numbers; its next number must exceed any existing uploaded build for the same version.

The Makeet scheme runs its UI target, then `MakeetStoreKitSetupTests`, then `MakeetCalendarTests`, serially on the same destination. The setup target configures the public StoreKit test catalog and verifies an Xcode transaction for the app bundle before the purchase-test host launches. This avoids the cold iOS27 first-process environment cache directing a test purchase to Sandbox. Keep purchase/error/restore/refund assertions required; do not substitute a previously used Simulator for cold exported-package verification. Test catalogs are copied only into the two test bundles, never the distributable application.

The scheme includes Simulator UI and archive-lifetime regressions. The physical-only existing-account check skips Simulator. Calendar tests use a disposable fixture calendar and retain their permission/device guards. Provider confirmations, real calendar accounts, Home Screen widgets and actual APNs receipts remain distinct device checks.

The Makeet Internal group contains only the owner's existing App Store Connect account. The workflow controls build delivery; the group's general automatic-upload option is disabled. Do not add external testers, other repositories, paid plans or broader account permissions as part of routine builds. Repository-access or service-agreement approval is completed at the relevant provider screen. Keep any future explicit credentials in hush; repository hooks do not require an App Store Connect private API key.

The checked-in Xcode Cloud manifest contains product/container identifiers, not credentials. The GitHub app installation predates Makeet and is shared with other projects; do not change its global repository scope while maintaining this workflow.

## Encryption declaration

The native apps and pinned sign-in dependencies use Apple operating-system networking and security facilities, including CommonCrypto hashing. They do not implement independent encryption. Their generated Info plists set `ITSAppUsesNonExemptEncryption` to `false`, following Apple's [encryption declaration guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption). Reassess the declaration if app or SDK cryptography changes. Backend encryption is separate from the distributed native binary.

## Release evidence

A successful local archive is not a TestFlight upload. Record the cloud build number, completed test action, processed App Store Connect build and internal TestFlight availability when each is verified. Retain release archives and dSYMs beyond the provider's artifact-retention period so field crashes can be symbolicated.

On 2026-10-17, cloud build 2 completed the required iOS27 test and archive actions. Its processed TestFlight build 0.1.0 (2) is available with Testing status in Makeet Internal, and the sole owner's tester status is Invited. Its one-time export questionnaire was completed using the native binary's OS-only encryption classification; later builds carry the Info declaration and localized notes. Cloud build 3 was withheld after its detached-card fixture release assertion failed. The test gate remains required.
