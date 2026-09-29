#!/usr/bin/env bash
# Bring up the AI stack on ai-jacaranda: LiteLLM + Postgres + SearXNG + speaches + Open WebUI.
# Idempotent: safe to re-run — existing secrets and keys are never regenerated.
# Ollama itself is a host service (see ../ollama/).
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example — fill in the <placeholders>, then re-run." >&2
  exit 1
fi

hex() { python3 -c "import secrets; print(secrets.token_hex($1))"; }

# Generate the local secrets once (missing, or still a placeholder).
if ! grep -qE '^POSTGRES_PASSWORD=[0-9a-f]{16,}' .env; then
  sed -i '/^POSTGRES_PASSWORD=/d' .env; printf '\nPOSTGRES_PASSWORD=%s\n' "$(hex 24)" >> .env
  echo "Generated POSTGRES_PASSWORD"
fi
if ! grep -qE '^SEARXNG_SECRET=[0-9a-f]{16,}' .env; then
  sed -i '/^SEARXNG_SECRET=/d' .env; printf '\nSEARXNG_SECRET=%s\n' "$(hex 32)" >> .env
  echo "Generated SEARXNG_SECRET"
fi

set -a; . ./.env; set +a

if ! curl -fsS -m 5 http://localhost:11434/api/version >/dev/null; then
  echo "WARNING: Ollama is not answering on :11434 — local models will fail (systemctl status ollama)." >&2
fi

# Stage 1: the gateway alone. compose insists OPENWEBUI_LITELLM_KEY is set (it is required for
# Open WebUI), and on a first run the key can't exist until LiteLLM is up — so pass a placeholder
# for this stage only. It is not used by postgres/litellm.
OPENWEBUI_LITELLM_KEY="${OPENWEBUI_LITELLM_KEY:-bootstrap}" docker compose up -d postgres litellm
echo -n "Waiting for LiteLLM"
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' litellm-proxy 2>/dev/null)" = healthy ] && break
  echo -n "."; sleep 5
done
echo

# Scoped virtual keys — one per client, least privilege. Minted once, stored in .env.
mint() {  # <ENV_VAR> <alias> <extra JSON fields>
  grep -qE "^$1=sk-" .env && return 0
  local key; key="$(./new-key.sh "$2" "$3")"
  printf '%s=%s\n' "$1" "$key" >> .env; echo "Minted key '$2' -> $1"
}
mint OPENWEBUI_LITELLM_KEY  open-webui ''
mint LITELLM_KEY_IDE        ide        '"models":["anno-code","anno-fast","anno-chat","anno-embed","qwen2.5-coder:3b","nomic-embed-text"],"rpm_limit":60'
mint LITELLM_KEY_SCRIPTS    scripts    '"models":["anno-fast","anno-chat","anno-reason","anno-code","anno-vision","anno-embed","anno-stt","anno-tts"],"max_budget":5,"budget_duration":"30d","rpm_limit":30'
mint LITELLM_KEY_PROMETHEUS prometheus '"allowed_routes":["/metrics","/metrics/"]'

# Stage 2: everything (picks up the real Open WebUI key from .env).
set -a; . ./.env; set +a
docker compose up -d

# Speech models are pulled from Hugging Face on first use (~140 MB whisper + ~330 MB Kokoro).
# Only fetch what speaches doesn't already list; a stalled transfer is retried on the next run.
echo -n "Waiting for speaches"
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' speaches 2>/dev/null)" = healthy ] && break
  echo -n "."; sleep 4
done
echo
for model in Systran/faster-whisper-base speaches-ai/Kokoro-82M-v1.0-ONNX; do
  docker exec -i speaches python3 - "$model" <<'PY' || echo "WARNING: could not fetch $model — re-run setup.sh" >&2
import sys, json, urllib.request
model, base = sys.argv[1], "http://localhost:8000/v1/models"
have = {m["id"] for m in json.load(urllib.request.urlopen(base, timeout=30))["data"]}
if model in have:
    print(f"speech model present: {model}")
else:
    print(f"downloading {model} ...", flush=True)
    urllib.request.urlopen(urllib.request.Request(f"{base}/{model}", method="POST"), timeout=900)
    print(f"downloaded {model}")
PY
done

echo
echo "LiteLLM:    http://localhost:${LITELLM_PORT:-4001}   (health: /health/liveliness, metrics: /metrics/)"
echo "Open WebUI: http://localhost:${OPEN_WEBUI_PORT:-8080}"
