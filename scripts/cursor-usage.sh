#!/usr/bin/env bash
# Check whether the cursor-agent CLI still has usage quota remaining.
# Cursor has two independent usage pools:
#
#   1. First-party pool  — Cursor's own models (e.g. composer-2.5-fast).
#      Used by the 'fast' droid's cursor fallback (composer-2.5-fast).
#   2. API pool           — Third-party models routed through Cursor
#      (e.g. gpt-5.6-sol-high). Used by the 'deep' droid.
#
# The pools are independent: exhausting the API pool means you can't spawn
# Deep agents, but Fast agents may still work (and vice versa).
#
# This script tests both pools by sending a trivial prompt to each model and
# inspecting the responses for limit/quota error signals.
#
# Usage:  bash scripts/cursor-usage.sh
#
# Exit codes (bitmask of exhausted pools):
#   0  both pools OK
#   1  first-party pool exhausted (fast droid cursor fallback down)
#   2  API pool exhausted (deep droid down)
#   3  both pools exhausted
#   4  cursor-agent CLI not found / other error
set -euo pipefail

if ! command -v cursor-agent >/dev/null 2>&1; then
  echo "cursor-agent CLI not found on PATH. Install: curl https://cursor.com/install -fsS | bash" >&2
  exit 4
fi

FIRST_PARTY_MODEL="composer-2.5-fast"
API_MODEL="gpt-5.6-sol-high"

# test_model <model> -> echoes "ok" or "out" or "error", returns 0/1/2
test_model() {
  local model="$1"
  local response
  response=$(timeout 60 cursor-agent -p "Reply with exactly: ok" --output-format json --model "$model" --trust 2>&1 || true)

  if [ -z "$response" ]; then
    echo "error"
    return 2
  fi

  if echo "$response" | grep -qiE '"is_error"\s*:\s*true'; then
    if echo "$response" | grep -qiE 'slow.pool|hard.limit|quota|rate.limit|usage.limit|spend.limit|exceeded|too many'; then
      echo "out"
      return 1
    fi
    echo "error"
    return 2
  fi

  if echo "$response" | grep -qiE 'slow.pool|hard.limit|hit_hard_limit|is_in_slow_pool|usage.limit|spend.limit|quota.exceeded|rate.limit.exceeded|too many request'; then
    echo "out"
    return 1
  fi

  if echo "$response" | grep -q '"result"'; then
    echo "ok"
    return 0
  fi

  echo "error"
  return 2
}

printf '\n==> Testing first-party pool (%s)\n' "$FIRST_PARTY_MODEL"
FIRST_PARTY_STATUS=$(test_model "$FIRST_PARTY_MODEL")
FIRST_PARTY_RC=$?
case "$FIRST_PARTY_STATUS" in
  ok)   printf '  OK — first-party pool responding (quota remaining).\n' ;;
  out)  printf '  OUT OF QUOTA — first-party pool exhausted.\n' >&2
        printf '  The fast droid cannot fall back to cursor (composer-2.5-fast).\n' >&2 ;;
  error) printf '  ERROR — could not determine first-party pool status.\n' >&2 ;;
esac

printf '\n==> Testing API pool (%s)\n' "$API_MODEL"
API_STATUS=$(test_model "$API_MODEL")
API_RC=$?
case "$API_STATUS" in
  ok)   printf '  OK — API pool responding (quota remaining).\n' ;;
  out)  printf '  OUT OF QUOTA — API pool exhausted.\n' >&2
        printf '  The deep droid (gpt-5.6-sol-high) cannot be spawned.\n' >&2 ;;
  error) printf '  ERROR — could not determine API pool status.\n' >&2 ;;
esac

# Compute bitmask exit code.
EXIT_CODE=0
if [ "$FIRST_PARTY_STATUS" = "out" ]; then EXIT_CODE=$((EXIT_CODE | 1)); fi
if [ "$API_STATUS" = "out" ]; then EXIT_CODE=$((EXIT_CODE | 2)); fi

# If either pool had a non-quota error (and neither was definitively "out"), treat as error.
if [ "$FIRST_PARTY_STATUS" = "error" ] && [ "$FIRST_PARTY_STATUS" != "out" ] && [ "$API_STATUS" != "out" ]; then
  EXIT_CODE=4
elif [ "$API_STATUS" = "error" ] && [ "$API_STATUS" != "out" ] && [ "$FIRST_PARTY_STATUS" != "out" ]; then
  EXIT_CODE=4
fi

printf '\n==> Summary:\n'
case $EXIT_CODE in
  0) printf '  Both pools OK. Fast and deep droids can use cursor.\n' ;;
  1) printf '  First-party pool exhausted. Fast droid must use grok only; deep droid unaffected.\n' ;;
  2) printf '  API pool exhausted. Deep droid unavailable; fast droid unaffected.\n' ;;
  3) printf '  Both pools exhausted. Neither cursor-backed droid can spawn.\n  Consider waiting for reset or using grok for fast tasks.\n' ;;
  4) printf '  Could not determine pool status (CLI error or unauthenticated).\n' ;;
esac

exit $EXIT_CODE
