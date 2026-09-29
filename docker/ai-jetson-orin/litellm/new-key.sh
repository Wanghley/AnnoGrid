#!/usr/bin/env bash
# Mint a scoped LiteLLM virtual key and print it once (it cannot be read back later).
#
#   ./new-key.sh <alias> [extra JSON fields]
#   ./new-key.sh laptop-ide '"models":["anno-code","anno-chat","anno-embed"],"rpm_limit":60'
#   ./new-key.sh batch-jobs '"models":["anno-fast","anno-chat"],"max_budget":2,"budget_duration":"30d"'
#
# Omit "models" for a key that may use every model. Use the master key only for admin work.
set -euo pipefail
cd "$(dirname "$0")"
alias="${1:?usage: $0 <alias> [extra JSON fields]}"; extra="${2:-}"
set -a; . ./.env; set +a
body="{\"key_alias\":\"$alias\"${extra:+,$extra}}"
curl -fsS "http://localhost:${LITELLM_PORT}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H 'Content-Type: application/json' -d "$body" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["key"])'
