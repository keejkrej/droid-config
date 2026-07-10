# Check whether the cursor-agent CLI still has usage quota remaining.
# Cursor has two independent usage pools:
#
#   1. First-party pool  — Cursor's own models (e.g. composer-2.5-fast).
#      Used by the 'fast' droid's cursor fallback (composer-2.5-fast).
#   2. API pool           — Third-party models routed through Cursor
#      (e.g. claude-fable-5-high). Used by the 'deep' droid.
#
# The pools are independent: exhausting the API pool means you can't spawn
# Deep agents, but Fast agents may still work (and vice versa).
#
# This script tests both pools by sending a trivial prompt to each model and
# inspecting the responses for limit/quota error signals.
#
# Usage:  pwsh scripts/cursor-usage.ps1
#
# Exit codes (bitmask of exhausted pools):
#   0  both pools OK
#   1  first-party pool exhausted (fast droid cursor fallback down)
#   2  API pool exhausted (deep droid down)
#   3  both pools exhausted
#   4  cursor-agent CLI not found / other error
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$cursorAgent = Get-Command cursor-agent -ErrorAction SilentlyContinue
if (-not $cursorAgent) {
  [Console]::Error.WriteLine("cursor-agent CLI not found on PATH. Install: https://cursor.com/install")
  exit 4
}

$FirstPartyModel = "composer-2.5-fast"
$ApiModel       = "claude-fable-5-high"

# test_model returns "ok", "out", or "error"
function Test-Model([string]$Model) {
  $arguments = @("-p", "Reply with exactly: ok", "--output-format", "json", "--model", $Model)
  try {
    $response = & cursor-agent @arguments 2>&1 | Out-String
  } catch {
    $response = ""
  }

  if ([string]::IsNullOrWhiteSpace($response)) { return "error" }

  if ($response -match '(?i)"is_error"\s*:\s*true') {
    if ($response -match '(?i)slow.pool|hard.limit|quota|rate.limit|usage.limit|spend.limit|exceeded|too many') {
      return "out"
    }
    return "error"
  }

  if ($response -match '(?i)slow.pool|hard.limit|hit_hard_limit|is_in_slow_pool|usage.limit|spend.limit|quota.exceeded|rate.limit.exceeded|too many request') {
    return "out"
  }

  if ($response -match '"result"') { return "ok" }

  return "error"
}

Write-Host "`n==> Testing first-party pool ($FirstPartyModel)"
$firstPartyStatus = Test-Model $FirstPartyModel
switch ($firstPartyStatus) {
  "ok"    { Write-Host "  OK - first-party pool responding (quota remaining)." }
  "out"   { [Console]::Error.WriteLine("  OUT OF QUOTA - first-party pool exhausted.")
            [Console]::Error.WriteLine("  The fast droid cannot fall back to cursor (composer-2.5-fast).") }
  "error" { [Console]::Error.WriteLine("  ERROR - could not determine first-party pool status.") }
}

Write-Host "`n==> Testing API pool ($ApiModel)"
$apiStatus = Test-Model $ApiModel
switch ($apiStatus) {
  "ok"    { Write-Host "  OK - API pool responding (quota remaining)." }
  "out"   { [Console]::Error.WriteLine("  OUT OF QUOTA - API pool exhausted.")
            [Console]::Error.WriteLine("  The deep droid (claude-fable-5-high) cannot be spawned.") }
  "error" { [Console]::Error.WriteLine("  ERROR - could not determine API pool status.") }
}

# Compute bitmask exit code.
$exitCode = 0
if ($firstPartyStatus -eq "out") { $exitCode = $exitCode -bor 1 }
if ($apiStatus     -eq "out") { $exitCode = $exitCode -bor 2 }

# If either pool had a non-quota error (and neither was definitively "out"), treat as error.
if (($firstPartyStatus -eq "error") -and ($firstPartyStatus -ne "out") -and ($apiStatus -ne "out")) {
  $exitCode = 4
} elseif (($apiStatus -eq "error") -and ($apiStatus -ne "out") -and ($firstPartyStatus -ne "out")) {
  $exitCode = 4
}

Write-Host "`n==> Summary:"
switch ($exitCode) {
  0 { Write-Host "  Both pools OK. Fast and deep droids can use cursor." }
  1 { Write-Host "  First-party pool exhausted. Fast droid must use grok only; deep droid unaffected." }
  2 { Write-Host "  API pool exhausted. Deep droid unavailable; fast droid unaffected." }
  3 { Write-Host "  Both pools exhausted. Neither cursor-backed droid can spawn."
      Write-Host "  Consider waiting for reset or using grok for fast tasks." }
  4 { Write-Host "  Could not determine pool status (CLI error or unauthenticated)." }
}

exit $exitCode
