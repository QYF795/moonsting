#!/usr/bin/env bash
# One command that answers "is this repo still good?".
#
#   script/healthcheck.sh          # full run (~2 min cold, ~40 s warm)
#   script/healthcheck.sh --quick  # skip the native builds
#
# Exits non-zero if anything fails, so it can be used as a CI job or a cron
# reminder. Every line it prints is a check that either passed or failed; the
# tail of a failing check's output is shown so the reason is on screen.
set -uo pipefail
cd "$(dirname "$0")/.."

quick=0
[ "${1:-}" = "--quick" ] && quick=1

fail=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

check() {
  local name="$1"
  shift
  local start
  start=$(date +%s)
  if "$@" >"$log" 2>&1; then
    printf 'PASS  %-34s %3ss\n' "$name" "$(( $(date +%s) - start ))"
  else
    printf 'FAIL  %-34s %3ss\n' "$name" "$(( $(date +%s) - start ))"
    sed -n '$p;1,6p' "$log" | sed 's/^/      /'
    fail=1
  fi
}

echo "moonsting healthcheck — $(date '+%Y-%m-%d %H:%M')"
echo

check "check wasm-gc (deny-warn)" moon check --target wasm-gc --deny-warn
check "tests wasm-gc"            moon test  --target wasm-gc
check "tests js"                 moon test  --target js

if [ "$quick" -eq 0 ]; then
  check "check native (deny-warn)" moon check --target native --deny-warn
  check "tests native"             moon test  --target native
fi

# Dogfood: targets that are expected to stay clean. A failure here means the
# engine regressed (false positive or crash), not that the target found a bug.
for target in json csvstrict props fixed stdjson bigint; do
  check "dogfood $target" \
    moon run cli --target wasm-gc -- run --target "$target" --max-execs 3000 --fail-on-finding
done

# Cross-backend: the same inputs through native and wasm-gc must agree. Needs
# both builds, so it runs after the native build above.
check "build wasm-gc"  moon build --target wasm-gc
check "cross-backend utf8" \
  moon run cli --target native -- cross --target utf8 --max-execs 40

# The two standard-library targets, at a size that would surface a regression in
# `@json` or `@bigint` quickly.
check "stdlib @json 50k"   moon run cli --target wasm-gc -- run --target stdjson --max-execs 50000
check "stdlib @bigint 20k" moon run cli --target wasm-gc -- run --target bigint   --max-execs 20000

echo
if [ "$fail" -eq 0 ]; then
  echo "all checks passed"
else
  echo "at least one check failed"
fi
exit "$fail"
