#!/bin/bash
# Keep SDK workarounds local to this process, never in the user's environment.
set -euo pipefail
cd "$(dirname "$0")/.."

sdk="${MDVIEW_SDK:-}"
if [[ -z "$sdk" ]]; then
    sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
    fallback="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    if [[ "$sdk_version" == 27.* && -d "$fallback" ]]; then
        sdk="$fallback"
        echo "mdview: using installed macOS 26.5 SDK (SDK 27 SwiftUI macro workaround)." >&2
    fi
fi
if [[ -n "$sdk" && ! -d "$sdk" ]]; then
    echo "MDVIEW_SDK is not an SDK directory: $sdk" >&2
    exit 1
fi

command="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
if [[ "$command" == test ]]; then
    developer_dir="$(xcode-select -p)"
    frameworks="$developer_dir/Library/Developer/Frameworks"
    testing_plugins="$developer_dir/usr/lib/swift/host/plugins/testing"
    if [[ -d "$frameworks/Testing.framework" && ! -d "$frameworks/XCTest.framework" && -d "$testing_plugins" ]]; then
        # Command Line Tools ship Swift Testing but do not add its framework or
        # macro plugin search paths automatically. Xcode needs no such override.
        set -- -Xswiftc "-F$frameworks" \
            -Xswiftc -plugin-path -Xswiftc "$testing_plugins" \
            -Xlinker -rpath -Xlinker "$frameworks" "$@"
    fi
fi
if [[ -n "$sdk" ]]; then
    case "$command" in
        build|test|run)
            exec env SDKROOT="$sdk" xcrun swift "$command" --sdk "$sdk" --build-system native "$@"
            ;;
        *) exec env SDKROOT="$sdk" xcrun swift "$command" "$@" ;;
    esac
fi
exec xcrun swift "$command" "$@"
