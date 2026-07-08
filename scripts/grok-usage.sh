#!/usr/bin/env bash
# Check whether the grok CLI (Grok Build beta, SuperGrok / X Premium Plus) still
# has usage quota remaining. Sends a trivial single-turn prompt in headless mode
# and inspects the response for the known usage-limit error message.
#
# Usage:  bash scripts/grok-usage.sh   (or ./scripts/grok-usage.sh after chmod +x)
#
# Exit codes:
#   0  grok is usable (quota remaining)
#   1  grok is out of quota (usage limit reached)
#   2  grok CLI not found / other error
set -euo pipefail

if ! command -v grok >/dev/null 2>&1; then
  echo "grok CLI not found on PATH. Install: curl -fsSL https://x.ai/cli/install.sh | bash" >&2
  exit 2
fi

# Trivial prompt that should return instantly with near-zero token cost.
RESPONSE=$(timeout 30 grok --no-auto-update -p "Reply with exactly: ok" --output-format json 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
  echo "grok-usage: no response from grok (timeout or error). It may be out of quota or not authenticated." >&2
  exit 2
fi

# The known limit-exhausted error message (found in the grok binary):
#   "You've reached your free Grok Build usage limit for now."
# Also check for the SuperGrok upsell URL that accompanies it.
if echo "$RESPONSE" | grep -qiE "usage limit|grok build usage limit|supergrok\?referrer=grok-build"; then
  echo "grok-usage: OUT OF QUOTA — Grok Build usage limit reached."
  echo "  Fall back to the 'cursor' (composer-2.5-fast) or 'cursor-deep' (claude-fable-5-high) subagent."
  echo "  Upgrade at: https://grok.com/supergrok?referrer=grok-build"
  exit 1
fi

# If we got a text field with actual content, grok is working.
if echo "$RESPONSE" | grep -q '"text"'; then
  echo "grok-usage: OK — grok is responding (quota remaining)."
  exit 0
fi

# Unknown response shape — treat as error to be safe.
echo "grok-usage: unexpected response, could not determine quota status:" >&2
echo "$RESPONSE" >&2
exit 2
