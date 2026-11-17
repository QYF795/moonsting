#!/usr/bin/env bash
# A five-act tour of moonsting, ~30 seconds.
#
#   script/demo.sh
#
# Every act prints the command it runs, so the output is self-explanatory even
# when nobody is narrating. Nothing here writes outside the working directory.
set -uo pipefail
cd "$(dirname "$0")/.."

exe="_build/native/debug/build/cli/cli.exe"
[ -x "$exe" ] || exe="_build/native/debug/build/cli/cli"

act() { printf '\n=== %s ===\n' "$1"; }

act "1/5 tests: two backends"
moon test --target native
moon test --target wasm-gc

act "2/5 a real finding, minimized to 5 bytes"
moon build --target native >/dev/null
"$exe" run --target varint --seed 1 --max-execs 50000

act "3/5 the same finding replays, and can be shrunk further"
"$exe" replay   --target varint --hex 92ffffff0f
"$exe" minimize --target varint --hex 92ffffff0f00010203

act "4/5 a crash no longer kills the run"
"$exe" run --target boom --seed 1 --max-execs 1500 --isolate

act "5/5 coverage report, and a corpus that persists"
rm -rf .demo-corpus
"$exe" run --target protobuf --seed 1 --max-execs 4000 --cov-report --corpus-dir .demo-corpus
"$exe" run --target protobuf --seed 9 --max-execs 4000 --corpus-dir .demo-corpus
rm -rf .demo-corpus

printf '\nThe second run started from the 121 saved entries instead of the 9 seeds,\nand added only 13 new paths: it continued where the first run stopped.\n'
