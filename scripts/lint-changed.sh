#!/bin/bash
# Lints the Swift files changed against a base (default HEAD), including untracked files.
# Fails only on files with more lint errors than at the base, so old errors do not block you.
# Usage: scripts/lint-changed.sh [base], e.g. scripts/lint-changed.sh main
set -uo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-HEAD}"
files=$( (git diff --name-only --diff-filter=d "$BASE" -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift') | sort -u)
if [ -z "$files" ]; then
  echo "No changed Swift files."
  exit 0
fi
status=0
for f in $files; do
  now=$(swift format lint --strict "$f" 2>&1)
  now_count=$(printf "%s" "$now" | grep -c "error:" || true)
  base_count=0
  if git cat-file -e "$BASE:$f" 2>/dev/null; then
    # Same folder, so swift-format finds the same .swift-format file.
    tmp="$(dirname "$f")/.lint-base-$$.swift"
    git show "$BASE:$f" > "$tmp"
    base_count=$(swift format lint --strict "$tmp" 2>&1 | grep -c "error:" || true)
    rm -f "$tmp"
  fi
  if [ "$now_count" -gt "$base_count" ]; then
    echo "$f: $now_count lint errors (base $base_count)"
    printf "%s\n" "$now" | grep "error:"
    status=1
  fi
done
[ $status -eq 0 ] && echo "Lint OK: $(echo "$files" | wc -l | tr -d ' ') changed Swift files."
exit $status
