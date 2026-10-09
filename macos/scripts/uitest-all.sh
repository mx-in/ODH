#!/bin/sh
# Runs baron-uitest one app at a time. Each app gets up to 3 attempts of at most
# 150 s; an app that still fails is left out of the table and listed as omitted.
# Results: UITests/results/all.md
#
# Usage: scripts/uitest-all.sh [App ...]   (default: every app in the harness)
set -u

cd "$(dirname "$0")/.."
apps="${*:-TextEdit Safari Chrome Arc Mail Notes Pages Preview Xcode VS-Code Terminal Slack Obsidian}"
out="UITests/results"
mkdir -p "$out"
swift build --product baron-uitest >/dev/null || exit 1
bin="$(swift build --show-bin-path)/baron-uitest"

rows=""
notes=""
omitted=""
for app in $apps; do
    name=$(echo "$app" | tr '-' ' ')
    passed=no
    for attempt in 1 2 3; do
        echo "▶ $name (attempt $attempt)" >&2
        dir="$out/$app"
        rm -rf "$dir"
        timeout 150 "$bin" --only "$name" --out "$dir" >/dev/null 2>"$out/$app.log"
        row=$(grep "^| $name |" "$dir/latest.md" 2>/dev/null)
        note=$(grep "^- \*\*$name:\*\*" "$dir/latest.md" 2>/dev/null)
        # A skip is final; a row whose selected text was read is a result worth keeping.
        if echo "$note" | grep -q "skipped:"; then
            omitted="$omitted\n- **$name:** $(echo "$note" | sed 's/.*skipped: //')"
            passed=skip
            break
        fi
        if [ -n "$row" ] && ! echo "$row" | grep -q "^| $name | ✗ |"; then
            rows="$rows\n$row"
            notes="$notes\n$note (attempt $attempt)"
            passed=yes
            break
        fi
        echo "  attempt $attempt failed: $(echo "$note" | sed 's/.*:\*\* //')" >&2
    done
    if [ "$passed" = no ]; then
        omitted="$omitted\n- **$name:** failed 3 attempts; last: $(echo "$note" | sed 's/.*:\*\* //')"
    fi
done

{
    echo "# baron-uitest results ($(date -u +%Y-%m-%dT%H:%MZ))"
    echo
    echo "| App | Selected text | Context from | Sentence | Paragraph | Page URL | Page title | Window title | Document | Bounds | Menu copy | ⌘C | Bar shown | Slowest AX read |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    printf "%b\n" "$rows" | sed '/^$/d'
    echo
    echo "## Notes"
    printf "%b\n" "$notes" | sed '/^$/d'
    echo
    echo "## Omitted"
    printf "%b\n" "$omitted" | sed '/^$/d'
} > "$out/all.md"
cat "$out/all.md"
