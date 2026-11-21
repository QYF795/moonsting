# One command that answers "is this repo still good?"  (Windows wrapper)
#
#   powershell -ExecutionPolicy Bypass -File script/healthcheck.ps1
#   powershell -ExecutionPolicy Bypass -File script/healthcheck.ps1 -Quick
#
# Mirrors script/healthcheck.sh. Exits non-zero if anything fails.

param([switch]$Quick)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root
$script:fail = 0

function Check($name, [scriptblock]$body) {
  $start = Get-Date
  $output = & $body 2>&1 | Out-String
  $code = $LASTEXITCODE
  $secs = [int]((Get-Date) - $start).TotalSeconds
  if ($code -eq 0) {
    "{0,-34} {1,3}s  PASS" -f $name, $secs
  } else {
    "{0,-34} {1,3}s  FAIL" -f $name, $secs
    ($output -split "`n" | Select-Object -First 6) | ForEach-Object { "      $_" }
    $script:fail = 1
  }
}

"moonsting healthcheck - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
""

Check "check wasm-gc (deny-warn)" { moon check --target wasm-gc --deny-warn }
Check "tests wasm-gc"            { moon test  --target wasm-gc }
Check "tests js"                 { moon test  --target js }

if (-not $Quick) {
  Check "check native (deny-warn)" { moon check --target native --deny-warn }
  Check "tests native"             { moon test  --target native }
}

# Dogfood: targets expected to stay clean. A failure means the engine regressed
# (false positive or crash), not that the target found a bug.
foreach ($target in @("json", "csvstrict", "props", "fixed", "stdjson", "bigint")) {
  $t = $target
  Check "dogfood $t" { moon run cli --target wasm-gc -- run --target $t --max-execs 3000 --fail-on-finding }
}

Check "stdlib @json 50k"   { moon run cli --target wasm-gc -- run --target stdjson --max-execs 50000 }
Check "stdlib @bigint 20k" { moon run cli --target wasm-gc -- run --target bigint   --max-execs 20000 }

""
if ($script:fail -eq 0) { "all checks passed" } else { "at least one check failed" }
Pop-Location
exit $script:fail
