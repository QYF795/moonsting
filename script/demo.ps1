# A five-act tour of moonsting, ~30 seconds.
#
#   powershell -ExecutionPolicy Bypass -File script/demo.ps1
#
# Every act prints the command it runs, so the output is self-explanatory even
# when nobody is narrating. Nothing here writes outside the working directory.

$ErrorActionPreference = "Continue"
$exe = "_build/native/debug/build/cli/cli.exe"

function Act($title) {
  Write-Host ""
  Write-Host "=== $title ===" -ForegroundColor Cyan
}

Act "1/6 tests: two backends"
moon test --target native
moon test --target wasm-gc

Act "2/6 a real finding, minimized to 5 bytes"
moon build --target native | Out-Null
& $exe run --target varint --seed 1 --max-execs 50000

Act "3/6 the same finding replays, and can be shrunk further"
& $exe replay   --target varint --hex 92ffffff0f
& $exe minimize --target varint --hex 92ffffff0f00010203

Act "4/6 a crash no longer kills the run"
& $exe run --target boom --seed 1 --max-execs 1500 --isolate

Act "5/6 coverage report, and a corpus that persists"
Remove-Item -Recurse -Force .demo-corpus -ErrorAction SilentlyContinue
& $exe run --target protobuf --seed 1 --max-execs 4000 --cov-report --corpus-dir .demo-corpus
& $exe run --target protobuf --seed 9 --max-execs 4000 --corpus-dir .demo-corpus
Remove-Item -Recurse -Force .demo-corpus -ErrorAction SilentlyContinue

Act "6/6 the same tool, pointed at MoonBit's own JSON parser"
& $exe run --target stdjson --seed 1 --max-execs 50000

Write-Host ""
Write-Host "Second run started from the saved corpus instead of the seeds:" -ForegroundColor Green
Write-Host "it continued where the first run stopped, instead of starting over." -ForegroundColor Green
