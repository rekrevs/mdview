#!/bin/bash
# Bundle an explicitly selected SwiftPM configuration; never choose by mtime.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
configuration=debug
case "${1:-}" in
    "") ;;
    --configuration)
        configuration="${2:-}"
        if [[ $# -ne 2 ]]; then echo "Usage: $0 [--configuration debug|release]" >&2; exit 2; fi
        ;;
    *) echo "Usage: $0 [--configuration debug|release]" >&2; exit 2 ;;
esac
case "$configuration" in debug|release) ;; *) echo "Invalid build configuration: $configuration" >&2; exit 2 ;; esac
BUILD_DIR="$("$SCRIPT_DIR/scripts/swift-tool.sh" build -c "$configuration" --show-bin-path)"
if [[ ! -x "$BUILD_DIR/mdview" ]]; then
    echo "Build $configuration first: make build CONFIGURATION=$configuration" >&2
    exit 1
fi
if [[ ! -d "$BUILD_DIR/mdview_mdview.bundle" ]]; then
    echo "Missing renderer resource bundle; rebuild $configuration before packaging." >&2
    exit 1
fi
staging="$(mktemp -d "$SCRIPT_DIR/.mdview-bundle.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
APP_DIR="$staging/mdview.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/mdview" "$APP_DIR/Contents/MacOS/"
# Explicit current-package inventory avoids shipping obsolete dependencies left
# in .build by an earlier version (for example SwiftMath_SwiftMath.bundle).
for resource in "$BUILD_DIR/mdview_mdview.bundle"; do
    ditto "$resource" "$APP_DIR/Contents/Resources/$(basename "$resource")"
done
cp "$SCRIPT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
# Copy icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>mdview</string>
	<key>CFBundleIdentifier</key>
	<string>com.mdview.app</string>
	<key>CFBundleName</key>
	<string>mdview</string>
	<key>CFBundleDisplayName</key>
	<string>mdview</string>
	<key>CFBundleVersion</key>
	<string>20001</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0.1</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Markdown Document</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>net.daringfireball.markdown</string>
			</array>
		</dict>
	</array>
	<key>UTImportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.plain-text</string>
			</array>
			<key>UTTypeDescription</key>
			<string>Markdown Document</string>
			<key>UTTypeIdentifier</key>
			<string>net.daringfireball.markdown</string>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>md</string>
					<string>markdown</string>
				</array>
			</dict>
		</dict>
	</array>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Sign only after all resources are in place, then verify the staged result.
codesign --sign - --force --deep "$APP_DIR"
"$SCRIPT_DIR/scripts/validate-bundle.sh" "$APP_DIR"
# mdview.app is a generated build artifact. Stage first so failures leave it intact.
if [[ -e "$SCRIPT_DIR/mdview.app" ]]; then
    mv "$SCRIPT_DIR/mdview.app" "$staging/previous.app"
fi
if ! mv "$APP_DIR" "$SCRIPT_DIR/mdview.app"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$SCRIPT_DIR/mdview.app"; fi
    exit 1
fi
echo "Created $SCRIPT_DIR/mdview.app ($configuration, version 2.0.1)"
