# Google Play product assets

`metadata/` contains the five localized Makeet listings, with the Google Play limits of 30 characters for the title, 80 for the short description and 4,000 for the full description. Text describes the free Android product and device-managed calendar synchronization; it does not advertise a subscription, Android remote push or a public release before availability is verified.

`screenshots/<language>/` contains unmodified 1080 × 2400 native Android captures of Today, Calendar, Trends and Plan in the explicit labeled demo mode. They contain no real user account or calendar data. Capture them from `StoreScreenshotsTest` only after functional native verification; wait for the native frame to settle and inspect every locale before replacing assets. Do not reconstruct application screens in artwork.

App creation, Play App Signing, provider certificate registration, required declarations, Android-specific Data safety and the account's testing/production-access gates are separate from these assets. See [the Android release procedure](../docs/android.md). No app record, upload or public listing is implied by this directory.
