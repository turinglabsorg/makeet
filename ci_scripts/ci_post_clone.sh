#!/bin/sh
set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    printf '%s\n' 'This hook requires an Xcode Cloud build environment.' >&2
    exit 1
fi

cd "${CI_PRIMARY_REPOSITORY_PATH:?Missing primary repository path}"
xcodebuild -version
sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
case "$sdk_version" in
    27.*) ;;
    *) printf '%s\n' 'Makeet CI requires Xcode with the iOS 27 SDK.' >&2; exit 1 ;;
esac

python3 scripts/ValidateLocalizations.py
swift test --disable-sandbox
