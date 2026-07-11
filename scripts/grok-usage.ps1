# Check whether the grok CLI (Grok Build beta, SuperGrok / X Premium Plus) still
# has usage quota remaining. Sends a trivial single-turn prompt in headless mode
# and inspects the response for the known usage-limit error message.
#
# Usage:  pwsh scripts/grok-usage.ps1
#
# Exit codes:
#   0  grok is usable (quota remaining)
#   1  grok is out of quota (usage limit reached)
#   2  grok CLI not found / other error
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$grokCmd = Get-Command grok -ErrorAction SilentlyContinue
if (-not $grokCmd) {
  [Console]::Error.WriteLine("grok CLI not found on PATH. Install: https://x.ai/cli/install.sh")
  exit 2
}

# Trivial prompt that should return instantly with near-zero token cost.
$arguments = @("--no-auto-update", "-p", "Reply with exactly: ok", "--output-format", "json")
try {
  $response = & grok @arguments 2>$null | Out-String
} catch {
  $response = ""
}

if ([string]::IsNullOrWhiteSpace($response)) {
  [Console]::Error.WriteLine("grok-usage: no response from grok (timeout or error). It may be out of quota or not authenticated.")
  exit 2
}

# The known limit-exhausted error message (found in the grok binary):
#   "You've reached your free Grok Build usage limit for now."
# Also check for the SuperGrok upsell URL that accompanies it.
if ($response -match '(?i)usage limit|grok build usage limit|supergrok\?referrer=grok-build') {
  [Console]::Error.WriteLine("grok-usage: OUT OF QUOTA - Grok Build usage limit reached.")
  [Console]::Error.WriteLine("  Fall back to the 'cursor' (composer-2.5-fast) or 'cursor-deep' (gpt-5.6-sol-high) subagent.")
  [Console]::Error.WriteLine("  Upgrade at: https://grok.com/supergrok?referrer=grok-build")
  exit 1
}

# If we got a text field with actual content, grok is working.
if ($response -match '"text"') {
  Write-Host "grok-usage: OK - grok is responding (quota remaining)."
  exit 0
}

# Unknown response shape - treat as error to be safe.
[Console]::Error.WriteLine("grok-usage: unexpected response, could not determine quota status:")
[Console]::Error.WriteLine($response)
exit 2
