# Google Play product assets

`metadata/` contains the five localized Makeet listings, with the Google Play limits of 30 characters for the title, 80 for the short description and 4,000 for the full description. Text describes the free Android product and device-managed calendar synchronization; it does not advertise a subscription, Android remote push or a public release before availability is verified.

`screenshots/<language>/` contains unmodified 1080 × 1920 native Android captures of Today, Calendar, Trends and Plan in the explicit labeled demo mode. They contain no real user account or calendar data. Capture them from `StoreScreenshotsTest` only after functional native verification; wait for the native frame to settle and inspect every locale before replacing assets. Do not reconstruct application screens in artwork.

`graphics/` contains the original 512 × 512 app icon and five opaque 1024 × 500 feature graphics composed from the unmodified Android captures and system typography. Regenerate on macOS with `swift PlayStore/creative/render.swift`. Captions and per-asset alt text are localized; run `python3 scripts/ValidatePlayStore.py` before upload. These checks follow [Google's preview-asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151).

For new native captures, set only the dedicated emulator to 1080 × 1920 with `adb -s <dedicated-emulator> shell wm size 1080x1920`, run `StoreScreenshotsTest` with `makeet_store_assets=true`, retain its original PNGs and restore the emulator with `wm size reset`. The test asserts the real captured pixel size; never stretch or crop a taller screen to satisfy the ratio. Use an isolated archive and a neutral system status bar.

App creation, Play App Signing, provider certificate registration, required declarations, Android-specific Data safety and the account's testing/production-access gates are separate from these assets. See [the Android release procedure](../docs/android.md). No app record, upload or public listing is implied by this directory.
