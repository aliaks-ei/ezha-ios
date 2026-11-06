#!/bin/bash
# Type-checks, tests, and format-checks Edge Functions with Deno.
# Uses a local `deno` when installed, else the denoland/deno Docker image (Colima).
# Usage: supabase/scripts/test-functions.sh [function ...], e.g. supabase/scripts/test-functions.sh ai-estimate
# With no names, it checks the functions changed against HEAD (all when none changed).
set -euo pipefail
cd "$(dirname "$0")/../functions"
DENO_IMAGE="${DENO_IMAGE:-denoland/deno:2.1.4}"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  changed=$( (git diff --name-only HEAD -- .; git ls-files --others --exclude-standard -- .) |
    sed -n 's|^supabase/functions/\([^/]*\)/.*|\1|p' | sort -u)
  if [ -n "$changed" ]; then names=($changed); else names=($(ls -d */ | tr -d /)); fi
fi
run() {
  local dir="$1"
  shift
  if command -v deno > /dev/null; then
    (cd "$dir" && sh -c "$*")
  else
    export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
    docker run --rm -v "$PWD/$dir":/app -w /app "$DENO_IMAGE" sh -c "$*"
  fi
}
for name in "${names[@]}"; do
  [ -d "$name" ] || { echo "No function: $name"; exit 1; }
  echo "== $name"
  tests=$(cd "$name" && ls *.test.ts 2> /dev/null || true)
  if [ -n "$tests" ]; then
    run "$name" "deno check $tests && deno test --allow-net=none $tests && deno fmt --check"
  else
    run "$name" "deno check *.ts && deno fmt --check"
  fi
done
