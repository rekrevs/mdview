#!/bin/bash
# Validate the installed layout, without consulting SwiftPM's build directory.
set -euo pipefail
app="${1:-mdview.app}"
bundle="$app/Contents/Resources/mdview_mdview.bundle"
resources="$bundle/Resources/Web"
# SwiftPM's native and Swift Build backends use different bundle layouts.
if [[ -d "$bundle/Contents/Resources/Resources/Web" ]]; then
    resources="$bundle/Contents/Resources/Resources/Web"
fi
for required in \
    "$app/Contents/MacOS/mdview" \
    "$app/Contents/Info.plist" \
    "$resources/index.html" \
    "$resources/reader.css" \
    "$resources/renderer.js" \
    "$resources/vendor/markdown-it.min.js" \
    "$resources/vendor/katex.min.js" \
    "$resources/vendor/katex.min.css" \
    "$resources/vendor/highlight.min.js" \
    "$resources/vendor/manifest.json" \
    "$resources/vendor/licenses/markdown-it.txt" \
    "$resources/vendor/licenses/katex.txt" \
    "$resources/vendor/licenses/cdn-assets.txt"; do
    if [[ ! -s "$required" ]]; then
        echo "Bundle is missing a required nonempty file: $required" >&2
        exit 1
    fi
done
[[ -x "$app/Contents/MacOS/mdview" ]]
if [[ -z "$(find "$resources/vendor/fonts" -name '*.woff2' -type f -print -quit)" ]]; then
    echo "Bundle is missing offline KaTeX fonts." >&2
    exit 1
fi
if [[ -z "$(find "$resources/vendor/licenses" -type f -print -quit)" ]]; then
    echo "Bundle is missing third-party licenses." >&2
    exit 1
fi
if [[ -n "$(find "$app/Contents/Resources" -type l -print -quit)" ]]; then
    echo "Bundle resources must be copied files, not links into a build tree." >&2
    exit 1
fi
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
echo "Validated self-contained app layout: $app"
