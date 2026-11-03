#!/bin/bash
# Stage and verify before replacing; retain the previous app as a backup.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
destination="${1:-$HOME/Applications}"
mkdir -p "$destination"
staging="$(mktemp -d "$destination/.mdview-install.XXXXXX")"
backup=""
target="$destination/mdview.app"
cleanup() {
    status=$?
    if [[ $status -ne 0 && -n "$backup" && ! -e "$target" ]]; then
        mv "$backup" "$target"
    fi
    rm -rf "$staging"
    exit "$status"
}
trap cleanup EXIT
ditto "$root/mdview.app" "$staging/mdview.app"
"$root/scripts/validate-bundle.sh" "$staging/mdview.app"
if [[ -e "$target" ]]; then
    backup="$destination/mdview.app.backup-$(date +%Y%m%d-%H%M%S)-$$"
    mv "$target" "$backup"
fi
mv "$staging/mdview.app" "$target"
echo "Installed to $target"
if [[ -n "$backup" ]]; then echo "Previous app preserved at $backup"; fi
echo "Quit any running mdview before opening the new version."

# Quick Look: register the installed extension and retire the ones inside backups, so
# Finder does not pick an older copy with the same identifier. Failures only warn.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
appex="$target/Contents/PlugIns/mdviewQuickLook.appex"
"$lsregister" -f "$target" || echo "WARNING: Launch Services registration failed for $target" >&2
for old in "$destination"/mdview.app.backup-*/Contents/PlugIns/mdviewQuickLook.appex; do
    if [[ -d "$old" ]]; then pluginkit -r "$old" 2>/dev/null || echo "WARNING: could not unregister $old" >&2; fi
done
if pluginkit -a "$appex"; then
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    echo "Quick Look preview registered. If Space in Finder still shows plain text, enable mdview under"
    echo "System Settings > General > Login Items & Extensions > Quick Look, then check with:"
    echo "  pluginkit -m -v -i $(plutil -extract CFBundleIdentifier raw "$appex/Contents/Info.plist")"
else
    echo "WARNING: Quick Look extension registration failed for $appex" >&2
fi
