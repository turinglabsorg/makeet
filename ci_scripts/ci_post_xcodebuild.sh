#!/bin/sh
set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    printf '%s\n' 'This hook requires an Xcode Cloud build environment.' >&2
    exit 1
fi

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
    printf '%s\n' 'The native action failed; preserving its failure status.' >&2
    exit 1
fi

case "${CI_XCODEBUILD_ACTION:?Missing native action}" in
    test-without-building)
        case "${CI_TEST_DESTINATION_RUNTIME:-}" in
            'iOS 27'*) exit 0 ;;
            *) printf '%s\n' 'Makeet native tests require an iOS 27 Simulator.' >&2; exit 1 ;;
        esac
        ;;
    analyze|archive|build|build-for-testing) ;;
    *) printf '%s\n' 'Unrecognized Xcode Cloud native action.' >&2; exit 1 ;;
esac

cd "${CI_PRIMARY_REPOSITORY_PATH:?Missing primary repository path}"
python3 scripts/ValidateLocalizations.py \
    --extracted-root "${CI_DERIVED_DATA_PATH:?Missing derived data path}"
