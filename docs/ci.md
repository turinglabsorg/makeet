# Native CI and TestFlight

Makeet uses repository hooks for Xcode Cloud. Cloud activation and the first uploaded build must be verified in App Store Connect before describing TestFlight delivery as available.

## Repository checks

`ci_scripts/ci_post_clone.sh` requires the iOS 27 SDK, validates all five language catalogs and runs the domain, account-client and persistence package tests. It does not read or upload credentials.

`ci_scripts/ci_post_xcodebuild.sh` preserves native-action failures and validates compiler-extracted app/widget strings against the translated catalogs. Missing extracted strings fail build actions. Separate test-without-building workers validate their iOS27 destination and preserve test failures without expecting unavailable compilation intermediates.

The checked-in Xcode project and pinned Swift package resolution are the cloud build inputs. Keep `project.yml` and the generated project consistent. Never enable a production test-token sign-in path for cloud tests.

## Distribution workflow

Configure the Makeet iOS product (`org.turinglabs.makeet`) from the Xcode Cloud navigator, using only `turinglabsorg/makeet` and its `main` branch. Keep pull-request distribution disabled. Use Xcode 27 and an iPhone 16 Pro Simulator running iOS 27 for the test action, followed by an App Store Connect archive action and a successful-build TestFlight internal distribution postaction. The archive uses automatic Apple-managed signing. Xcode Cloud manages monotonically increasing build numbers; its next number must exceed any existing uploaded build for the same version.

The Makeet scheme includes Simulator UI and archive-lifetime regressions. The physical-only existing-account check skips Simulator. Calendar tests use a disposable fixture calendar and retain their permission/device guards. Provider confirmations, real calendar accounts, Home Screen widgets and actual APNs receipts remain distinct device checks.

Distribute only to the owner's approved internal testing group. Do not add external testers, other repositories, paid plans or broader account permissions as part of routine builds. Repository-access or service-agreement approval is completed at the relevant provider screen. Keep any future explicit credentials in hush; repository hooks do not require an App Store Connect private API key.

## Release evidence

A successful local archive is not a TestFlight upload. Record the cloud build number, completed test action, processed App Store Connect build and internal TestFlight availability when each is verified. Retain release archives and dSYMs beyond the provider's artifact-retention period so field crashes can be symbolicated.
