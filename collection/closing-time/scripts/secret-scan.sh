#!/usr/bin/env bash
# secret-scan.sh — grep-based sensitivity scanner for the closing-time sweep.
# Reads a list of file paths on stdin (one per line), scans each for
# patterns in the patterns file, exits 0 if clean, 1 if any match found.
# Writes matches to stdout as: FILE:LINE:PATTERN:MATCH

set -u

# Self-locating: default patterns file lives beside this script in the sibling
# config/ dir, so the copy references closing-time-facts's OWN config, not
# closing-time's. PATTERNS_FILE env override still honored.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="${PATTERNS_FILE:-$DIR/../config/sensitivity-patterns.txt}"

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "error: patterns file missing at $PATTERNS_FILE" >&2
    exit 2
fi

HITS=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    # Skip binary files
    file --mime "$file" 2>/dev/null | grep -q "charset=binary" && continue

    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        case "$pattern" in \#*) continue ;; esac
        if match=$(grep -niE "$pattern" "$file" 2>/dev/null | head -3); then
            if [ -n "$match" ]; then
                while IFS= read -r line; do
                    echo "$file:$line:[pattern=$pattern]"
                    HITS=$((HITS + 1))
                done <<< "$match"
            fi
        fi
    done < "$PATTERNS_FILE"
done

[ "$HITS" -gt 0 ] && exit 1
exit 0
