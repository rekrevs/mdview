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
