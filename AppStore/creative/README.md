# Store creative artwork

Run `swift AppStore/creative/render.swift` from the repository root on macOS.
The renderer writes five localized header PNGs at 5244 × 2950 and five search
PNGs at 3840 × 2560 to `artifacts/StoreCreative/`. Both formats are opaque.
It uses AppKit's system font, the original app icon and genuine
native Makeet screenshots. It does not generate or reconstruct application UI.

Required inputs are the app icon at
`App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the `01-today.png` and
`02-calendar.png` captures under
`artifacts/StoreScreens/{it,en,fr,de,es}/iphone-medium/`. Capture only isolated,
clearly identified demonstration data. These inputs and generated screenshots
remain outside version control.

Inspect every rendered language before upload. Keep the primary composition
inside the central header region and verify Apple's placement previews.
The header renderer insets its composition and moves the text column inward
to preserve readable margins in Apple's additional phone crop. The dedicated
3:2 search composition fills its placement with larger content rather than
reusing the complete universal header canvas. Uploading a file or seeing
`1 of 1` is not proof of successful ingestion.
Verify its Asset Library row has the expected aspect ratio, eligible placement
and asset-details link, with no upload-error badge. A failed upload can still
occupy a version slot and block review. Check the placement preview and run
the version's Add for Review validation before claiming submission readiness.
Ordinary native screenshots belong in the
separate App Previews and Screenshots tab. Do not use marketing artwork as a
subscription purchase-screen review attachment.

Apple references:

- [Creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)

This workflow prepares listing assets. It does not submit the app for review,
publish a product page or enable subscription billing.
