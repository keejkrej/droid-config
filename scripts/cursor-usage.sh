#!/usr/bin/env bash
# Check whether the cursor-agent CLI still has usage quota remaining.
# Sends a trivial single-turn prompt in print mode and inspects the response
# for known limit/quota error signals.
#
# Cursor uses a "slow pool" / "hard limit" model: when usage exceeds the plan
# limit, requests are either throttled (slow pool) or rejected with a
# hard-limit error. The error response includes fields like hit_hard_limit,
# is_in_slow_pool, error_title, error_detail.
#
# Usage:  bash scripts/cursor-usage.sh [model]
#   model defaults to composer-2.5-fast
#
# Exit codes:
#   0  cursor is usable (quota remaining)
#   1  cursor is out of quota (hard limit hit / slow pool)
#   2  cursor-agent CLI not found / other error
set -euo pipefail

MODEL="${1:-composer-2.5-fast}"

if ! command -v cursor-agent >/dev/null 2>&1; then
  echo "cursor-agent CLI not found on PATH. Install: curl https://cursor.com/install -fsS | bash" >&2
  exit 2
fi

# Trivial prompt that should return instantly with near-zero token cost.
RESPONSE=$(timeout 60 cursor-agent -p "Reply with exactly: ok" --output-format json --model "$MODEL" 2>&1 || true)

if [ -z "$RESPONSE" ]; then
  echo "cursor-usage: no response from cursor-agent (timeout or error). It may be out of quota or not authenticated." >&2
  exit 2
fi

# Check for error indicators in the JSON response.
# Cursor returns is_error: true on failures, and may include slow pool / hard
# limit / quota / rate limit signals in the text or error fields.
if echo "$RESPONSE" | grep -qiE '"is_error"\s*:\s*true'; then
  echo "cursor-usage: ERROR — cursor-agent returned an error response."
  echo "$RESPONSE" | head -5 >&2
  # Check if it's specifically a quota/limit issue
  if echo "$RESPONSE" | grep -qiE 'slow.pool|hard.limit|quota|rate.limit|usage.limit|spend.limit|exceeded|too many'; then
    echo "  Quota/limit issue detected. Fall back to 'grok' or 'cursor-deep'."
    exit 1
  fi
  exit 2
fi

# Check for slow pool / hard limit / quota text even in non-error responses.
if echo "$RESPONSE" | grep -qiE 'slow.pool|hard.limit|hit_hard_limit|is_in_slow_pool|usage.limit|spend.limit|quota.exceeded|rate.limit.exceeded|too many request'; then
  echo "cursor-usage: OUT OF QUOTA — cursor-agent hit a usage limit."
  echo "  Fall back to 'grok' or 'cursor-deep' (note: cursor-deep uses the same Cursor account)."
  exit 1
fi

# If we got a successful result with actual content, cursor is working.
if echo "$RESPONSE" | grep -q '"result"'; then
  echo "cursor-usage: OK — cursor-agent ($MODEL) is responding (quota remaining)."
  exit 0
fi

# Unknown response shape — treat as error to be safe.
echo "cursor-usage: unexpected response, could not determine quota status:" >&2
echo "$RESPONSE" >&2
exit 2
