#!/bin/bash
# Real Quick Look check: register this bundle's preview extension with PlugInKit, preview
# fixtures with qlmanage and assert the statistics line the extension logs after rendering.
# Needs an active desktop session. Leaves the checked extension registered (see README).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
app="$(cd "$(dirname "${1:-$root/mdview.app}")" && pwd -P)/$(basename "${1:-$root/mdview.app}")"
appex="$app/Contents/PlugIns/mdviewQuickLook.appex"
output="$root/.build/quicklook-checks"
mkdir -p "$output"
work="$(mktemp -d "${TMPDIR:-/tmp}/mdview-quicklook-check.XXXXXX")"
log_pid=""; ql_pid=""
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
temporary_copy=""
cleanup() {
    if [[ -n "$temporary_copy" ]]; then
        pluginkit -r "$appex" 2>/dev/null || true
        "$lsregister" -u "$app" 2>/dev/null || true
        echo "Unregistered temporary copy $app"
    fi
    [[ -n "$ql_pid" ]] && kill "$ql_pid" 2>/dev/null || true
    [[ -n "$log_pid" ]] && kill "$log_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; exit 1; }

"$root/scripts/validate-bundle.sh" "$app" >/dev/null
id="$(plutil -extract CFBundleIdentifier raw "$appex/Contents/Info.plist")"

# PlugInKit lists one copy per identifier and version, so another registered copy would
# shadow this one. Only test copies (this checkout, temporary folders) are removed.
tmp_physical="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
while IFS= read -r other; do
    [[ -z "$other" || "$other" == "$appex" ]] && continue
    case "$other" in
        "$root"/*|"$tmp_physical"/*|/private/var/folders/*) echo "Unregistering test copy $other"; pluginkit -r "$other" ;;
        *) fail "another copy of $id is registered and would shadow this one: $other (unregister it with pluginkit -r)" ;;
    esac
done < <(pluginkit -m -v -i "$id" | awk -F'\t' 'NF >= 4 {print $4}')
# pkd accepts an extension only inside an app known to Launch Services ("plug-ins outside
# containing apps must be protected by SIP"). Copies in temporary folders are unregistered
# again on exit; the checked-out build stays registered.
case "$app" in "$tmp_physical"/*|/private/var/folders/*|/private/tmp/*) temporary_copy=1 ;; esac
"$lsregister" -f "$app"
# A freshly replaced bundle can be unregistered asynchronously by pkd after it processes
# the deletion of the previous copy at the same path, so register, wait and confirm.
registered=""
for attempt in 1 2 3; do
    pluginkit -a "$appex"
    sleep 2
    if pluginkit -m -v -i "$id" | grep -qF "$appex"; then registered=1; break; fi
done
[[ -n "$registered" ]] || fail "pluginkit does not list $appex for $id"
pluginkit -m -v -i "$id"
qlmanage -r >/dev/null 2>&1 || true

cat > "$work/window.swift" <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "qlmanage" && window[kCGWindowLayer as String] as? Int == 0 {
    print(window[kCGWindowNumber as String] as? Int ?? 0); break
}
SWIFT

# preview NAME FILE PATTERN: run qlmanage -p and wait up to 30 s for PATTERN in the extension log.
preview() {
    local name="$1" file="$2" pattern="$3" logfile="$output/$1.log" line=""
    /usr/bin/log stream --style compact --level debug --predicate "subsystem == \"$id\"" > "$logfile" 2>&1 &
    log_pid=$!
    sleep 2
    qlmanage -p "$file" > "$output/$name.qlmanage.txt" 2>&1 &
    ql_pid=$!
    for _ in $(seq 60); do
        line="$(grep -m1 -E "$pattern" "$logfile" || true)"
        [[ -n "$line" ]] && break
        sleep 0.5
    done
    sleep 1
    local window
    window="$(swift "$work/window.swift" 2>/dev/null || true)"
    if [[ -n "$window" ]]; then screencapture -x -o -l "$window" "$output/$name.png" || true
    else echo "WARNING: no Quick Look window found for a screenshot" >&2; fi
    kill "$ql_pid" 2>/dev/null || true; wait "$ql_pid" 2>/dev/null || true; ql_pid=""
    kill "$log_pid" 2>/dev/null || true; wait "$log_pid" 2>/dev/null || true; log_pid=""
    [[ -n "$line" ]] || fail "$name: no log line matching '$pattern' (see $logfile)"
    echo "$line"
}
value() { sed -nE "s/.* $1=([^ ]*).*/\1/p" <<< "$2"; }
expect() { # expect LINE KEY OP VALUE
    local actual; actual="$(value "$2" "$1")"
    [[ -n "$actual" ]] || fail "missing $2"
    case "$3" in
        eq) [[ "$actual" == "$4" ]] ;;
        ge) (( actual >= $4 )) ;;
    esac || fail "$2=$actual, expected $3 $4"
    echo "PASS $2=$actual"
}

stats="$(preview fixture "$root/Tests/QuickLook/fixture.md" 'MDVIEW-QL-STATS file=fixture.md')"
echo "$stats"
expect "$stats" bundle eq "$appex"
for check in "katex ge 2" "mathErrors eq 0" "highlighted ge 1" "images ge 1" "imageErrors eq 0" \
             "alerts eq 1" "footnotes eq 1" "frontMatter eq 1" "tasks eq 2" "tables eq 2" \
             "diagrams eq 1" "diagramErrors eq 0" "activeHTML eq 0" "literalScript eq 1" "truncated eq 0"; do
    expect "$stats" $check
done
seconds="$(value renderSeconds "$stats")"
awk -v s="$seconds" 'BEGIN { exit !(s < 10) }' || fail "renderSeconds=$seconds"
echo "PASS renderSeconds=$seconds"

# Over 4 MiB: truncated on a character boundary with a visible note.
python3 - "$work/large.md" <<'PY'
import sys
line = "Paragraph with å, ä, ö and math $x_1$ — " + "lorem ipsum " * 20 + "\n\n"
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# Large document\n\n")
    while f.tell() < 5 * 1024 * 1024: f.write(line)
PY
large="$(preview large "$work/large.md" 'MDVIEW-QL-STATS file=large.md')"
echo "$large"
expect "$large" truncated eq 1
expect "$large" mathErrors eq 0

# Not UTF-8: a clear error instead of mojibake (Quick Look then shows its own fallback).
printf '# Latin-1 \xe5\xe4\xf6\n' > "$work/latin1.md"
failure="$(preview latin1 "$work/latin1.md" 'preview failed')"
echo "$failure"
grep -q 'not UTF-8' <<< "$failure" || fail "non-UTF-8 error message"
echo "PASS non-UTF-8 file reported"
echo "RESULT Quick Look checks passed for $appex (screenshots in $output)"
