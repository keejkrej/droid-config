# Check whether the cursor-agent CLI still has usage quota remaining.
# Sends a trivial single-turn prompt in print mode and inspects the response
# for known limit/quota error signals.
#
# Cursor uses a "slow pool" / "hard limit" model: when usage exceeds the plan
# limit, requests are either throttled (slow pool) or rejected with a
# hard-limit error. The error response includes fields like hit_hard_limit,
# is_in_slow_pool, error_title, error_detail.
#
# Usage:  pwsh scripts/cursor-usage.ps1 [-Model composer-2.5-fast]
#   -Model defaults to composer-2.5-fast
#
# Exit codes:
#   0  cursor is usable (quota remaining)
#   1  cursor is out of quota (hard limit hit / slow pool)
#   2  cursor-agent CLI not found / other error
[CmdletBinding()]
param(
  [string]$Model = "composer-2.5-fast"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$cursorAgent = Get-Command cursor-agent -ErrorAction SilentlyContinue
if (-not $cursorAgent) {
  [Console]::Error.WriteLine("cursor-agent CLI not found on PATH. Install: https://cursor.com/install")
  exit 2
}

# Trivial prompt that should return instantly with near-zero token cost.
$arguments = @("-p", "Reply with exactly: ok", "--output-format", "json", "--model", $Model)
try {
  $response = & cursor-agent @arguments 2>&1 | Out-String
} catch {
  $response = ""
}

if ([string]::IsNullOrWhiteSpace($response)) {
  [Console]::Error.WriteLine("cursor-usage: no response from cursor-agent (timeout or error). It may be out of quota or not authenticated.")
  exit 2
}

# Check for error indicators in the JSON response.
# Cursor returns is_error: true on failures, and may include slow pool / hard
# limit / quota / rate limit signals in the text or error fields.
if ($response -match '(?i)"is_error"\s*:\s*true') {
  [Console]::Error.WriteLine("cursor-usage: ERROR - cursor-agent returned an error response.")
  [Console]::Error.WriteLine(($response -split "`n" | Select-Object -First 5) -join "`n")
  if ($response -match '(?i)slow.pool|hard.limit|quota|rate.limit|usage.limit|spend.limit|exceeded|too many') {
    [Console]::Error.WriteLine("  Quota/limit issue detected. Fall back to 'grok' or 'cursor-deep'.")
    exit 1
  }
  exit 2
}

# Check for slow pool / hard limit / quota text even in non-error responses.
if ($response -match '(?i)slow.pool|hard.limit|hit_hard_limit|is_in_slow_pool|usage.limit|spend.limit|quota.exceeded|rate.limit.exceeded|too many request') {
  [Console]::Error.WriteLine("cursor-usage: OUT OF QUOTA - cursor-agent hit a usage limit.")
  [Console]::Error.WriteLine("  Fall back to 'grok' or 'cursor-deep' (note: cursor-deep uses the same Cursor account).")
  exit 1
}

# If we got a successful result with actual content, cursor is working.
if ($response -match '"result"') {
  Write-Host "cursor-usage: OK - cursor-agent ($Model) is responding (quota remaining)."
  exit 0
}

# Unknown response shape - treat as error to be safe.
[Console]::Error.WriteLine("cursor-usage: unexpected response, could not determine quota status:")
[Console]::Error.WriteLine($response)
exit 2
