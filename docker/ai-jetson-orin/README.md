# ai-jetson-orin — `ai-jacaranda` AI node

Jetson Orin Nano (`MAXN_SUPER`), **8 GB RAM shared between CPU, GPU and every container** — that
ceiling drives most decisions here. Tailscale `100.85.193.49` / `ai-jacaranda.tail8d608.ts.net`.
Scoped to **AI + monitoring only**.

```
 clients ── Open WebUI :8080 (chat, RAG, web search, voice)
   │        IDE plugins · scripts · agents
   ▼   OpenAI-compatible API, one scoped key per client
 LiteLLM :4001 ── Postgres (internal)        keys · budgets · spend · admin UI · /metrics
   │   routing · fallbacks · $ cap
   ├──► Ollama :11434   HOST systemd service   21 local models + 1 cloud-hosted
   ├──► speaches        CPU speech server      STT faster-whisper · TTS Kokoro  (internal)
   └──  Open WebUI ──► SearXNG                 private web search (internal)
```

| Path | What | Runs as |
|---|---|---|
| [`ollama/`](ollama/) | systemd drop-in for the host Ollama service | host (`systemctl`) |
| [`litellm/`](litellm/) | LiteLLM + Postgres + SearXNG + speaches + Open WebUI | compose project `litellm` |
| [`monitoring/homelable/`](monitoring/homelable/) | network topology map | compose project `homelable` |
| [`../../arlo/`](../../arlo/) | Wyoming voice services (whisper GPU, piper, wake word) — no consumer since Home Assistant was removed | compose project `arlo` |

Node metrics/log shipping (node-exporter, cAdvisor, promtail) come from
[`../shared/monitoring/`](../shared/monitoring/); Prometheus/Grafana live on `mon-capitao` / `vps-macauba`.

## Deploy

```bash
# 1. Ollama is already installed on the host. Models: `ollama list`
# 2. (optional, needs sudo) apply the memory tuning — see ollama/override.conf
sudo install -D -m 644 ollama/override.conf /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload && sudo systemctl restart ollama

# 3. The whole AI stack. Idempotent. On a first run it creates .env, generates the secrets, starts the
#    gateway, mints the scoped keys, starts everything else and downloads the speech models.
cd litellm && ./setup.sh          # or from a workstation: make deploy-ai
```

Verify (from `litellm/`):

```bash
set -a; . ./.env; set +a
curl -s localhost:4001/health/liveliness
curl -s localhost:4001/v1/models -H "Authorization: Bearer $LITELLM_KEY_SCRIPTS" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]), "models visible to this key")'
```

## Models

[`litellm/config.yaml`](litellm/config.yaml) is the source of truth. Local `model_name` == the Ollama tag,
so chats and presets resolve the same direct or via LiteLLM.

### Role aliases — point clients at these

Swapping the model behind a role is a one-line change in `config.yaml`; no client changes.

| Alias | Today | Use for |
|---|---|---|
| `anno-fast` | `granite4:350m` | titles, routing, classification (4/4 valid title JSON in testing; `qwen3.5:*` gave 0/4) |
| `anno-chat` | `qwen3.5:2b`, thinking **off** | default assistant, tools, multimodal (was `:4b` — see Memory budget). ≈ 3 s per short answer vs ≈ 58 s with thinking on |
| `anno-reason` | `phi4-mini` | math / logic |
| `anno-code` | `qwen2.5-coder:3b` | code |
| `anno-vision` | `qwen3.5:2b`, thinking **off** | image understanding |
| `anno-embed` | `nomic-embed-text` | embeddings (768-d) |
| `anno-stt` / `anno-tts` | faster-whisper base · Kokoro-82M | speech (below) |
| `anno-cloud` | `minimax-m3:cloud` | the one large model that works today — **prompts leave the box** |

### Everything installed

| Role | Models |
|---|---|
| General / multimodal | `qwen3.5:4b` `qwen3.5:2b` `qwen3.5:0.8b` `gemma4:e2b-it-qat` `llama3.2` `nemotron-3-nano:4b` |
| Tool use | `hermes3:3b` (the Nous Hermes 3 model) |
| Structured output | `granite4.1:3b` `granite3.1-moe` |
| Reasoning | `phi4-mini` `deepseek-r1:1.5b` `lfm2.5-thinking` |
| Code | `qwen2.5-coder:3b` |
| Tiny / fast | `granite4:350m` `qwen2.5:1.5b` |
| Vision | `moondream` (+ the multimodal ones above) |
| Embeddings | `nomic-embed-text` `granite-embedding:278m` `granite-embedding:30m` |
| Guardrail / utility | `granite3-guardian:2b` (safety classifier) · `reader-lm:1.5b` (HTML→Markdown) |
| Ollama cloud (leaves the box) | `minimax-m3:cloud` |

`qwen3.5:*` are **thinking** models: they spend hundreds of tokens reasoning even on trivial prompts, so
don't use them for short structured tasks. `anno-chat` / `anno-vision` switch thinking off by default (`reasoning_effort: none` in
`config.yaml`); send `reasoning_effort: low|medium|high` in a request to turn it back on, or use the raw `qwen3.5:2b` name.

Fallbacks are local→local, cloud→cloud/local, role→local — **never local→cloud** (would silently send prompts out).
To add a model: `ollama pull <tag>`, add a block to `config.yaml`, `docker compose restart litellm`.
Cost fields are electricity estimates ([`litellm/COST.md`](litellm/COST.md)); models without them count as $0.

### Speech

`speaches` (CPU) serves the OpenAI audio API; LiteLLM fronts it as `anno-stt` / `anno-tts`.
Measured here: STT ≈ 0.55× realtime, TTS ≈ 1.2× realtime (so long replies can gap between sentences);
round-trip accuracy 100% English / 99% Portuguese. Kokoro voices include pt-BR (`pf_dora`, `pm_alex`,
`pm_santa`) and English (`af_heart`, `am_michael`, …); change `AUDIO_TTS_VOICE` in the compose file and
Admin → Settings → Audio. **Browser mic input needs HTTPS (or localhost)** — plain `http://<tailscale-ip>:8080`
is blocked by the browser; see "Not done" below.

## Keys

The master key is for admin work only. Clients get scoped virtual keys ([`new-key.sh`](litellm/new-key.sh)):

| Key (`.env` var) | Allowed | Limits |
|---|---|---|
| `OPENWEBUI_LITELLM_KEY` | every model, no admin routes | — |
| `LITELLM_KEY_IDE` | `anno-code/fast/chat/embed`, `qwen2.5-coder:3b`, `nomic-embed-text` | 60 rpm, no cloud |
| `LITELLM_KEY_SCRIPTS` | local roles + speech, no cloud | $5 / 30d, 30 rpm |
| `LITELLM_KEY_PROMETHEUS` | `/metrics` only | can't call a model |

```bash
./new-key.sh laptop-ide '"models":["anno-code","anno-chat"],"rpm_limit":60'   # mint another; printed once
```

## Open WebUI

Version 0.11.x. Most settings live in its own DB (env vars only apply to a fresh DB), so the compose file
holds the desired state **and** the live DB was updated to match on 2026-09-29 (backup:
`litellm/open-webui-data/webui.db.bak-*`, git-ignored). Configured: everything through LiteLLM with its scoped
key, direct Ollama **off**, task model `anno-fast`, embeddings `anno-embed` via LiteLLM (no in-container MiniLM),
SearXNG web search, STT/TTS via LiteLLM. To turn direct Ollama back on (fallback if LiteLLM is down):
Admin → Settings → Connections → Ollama.

## Observability

- **LiteLLM `/metrics/`** (per-model requests, latency, tokens, spend, failures) — needs the Prometheus key.
  Scrape job `litellm` is in [`nodes/mon-capitao/prometheus-config/prometheus.yml`](../../nodes/mon-capitao/prometheus-config/prometheus.yml);
  it is **not deployed yet** — see "Not done".
- **cAdvisor** (in `shared/monitoring`): its `docker stats` figure was >1 GB but ~all of it was reclaimable kernel
  dentry cache from scanning container filesystems (real RSS ≈ 16 MB). The `disk` metric group is now off
  (that scan), plus a 384 MB cap. Nothing in this repo queries `container_fs_*`.
- Nothing in the repo scrapes this node's cAdvisor (`:8082`) or Netdata — only node-exporter (`:9100`).

## Memory budget (measured, no LLM loaded)

Total 7.4 GB. Idle baseline ≈ 4.3 GB used / ≈ 3 GB available; an LLM loads into that.

| | idle | notes |
|---|---|---|
| Open WebUI | 360–750 MB | fluctuates |
| LiteLLM | ≈ 640 MB | |
| speaches | 125 MB fresh · 182 MB after use · ≈ 740 MB while speaking | models unload ~4.5 min after last use; `MALLOC_*` settings cut post-use idle from 457 MB |
| SearXNG | ≈ 110 MB | |
| Postgres | ≈ 30 MB | |
| Netdata / Wyoming whisper (GPU) / voice-match | ≈ 335 / 270 / 110 MB | Wyoming pair has no consumer now |

LLM sizes: `qwen3.5:4b` 3.4 GB, `phi4-mini` 2.5 GB, `qwen3.5:2b` 2.7 GB, `granite4:350m` 0.85 GB.
A 4B model **plus** voice output at the same time will push into swap; prefer ≤ 2.7 GB models while using voice.

**Measured 2026-09-29 with the whole stack running (idle ≈ 5 GB used, ≈ 2.3 GB available):** on the Jetson a model's GPU memory shows up as
the runner's resident memory (the `qwen3.5:2b` runner holds ≈ 3.9 GB), so `qwen3.5:4b` no longer fits: Ollama loaded it ≈ 50 % on the
CPU and it could not produce 600 tokens in 280 s. `qwen3.5:2b` decodes at 8–10 tok/s (thinking off, ≈ 27 % on the CPU). That is why
`anno-chat` and `anno-vision` point at the 2B. To move them back to the 4B, first free ≈ 1.5 GB: retire the Wyoming voice stack
(≈ 0.45 GB), stop Netdata (≈ 0.2–0.3 GB), and/or set `OLLAMA_MAX_LOADED_MODELS=1` (needs sudo). LiteLLM retries a hung request up to
4 × 300 s plus fallbacks, so a stuck model also piles load onto Ollama — another reason not to leave the default on a model that can't load.

## Known issues / decisions

- **Gemini was removed** (2026-09-29): AI Studio returned HTTP 402 ("prepayment credits are depleted"). `config.yaml`
  has a commented block showing how to restore it. **OpenRouter key returns 401** — not wired (commented block in `config.yaml`).
  **`glm-5.2:cloud` returns 402** (not on Ollama's free plan) — removed; re-add after adding credits at ollama.com/settings.
- **DB moved local (2026-09-29).** LiteLLM's old Postgres/Redis were on `100.67.194.10`, not in the tailnet (OCI migration
  unfinished), so LiteLLM couldn't start and — models living only in that DB — had none. Postgres is now a local sidecar and
  models are declared in `config.yaml`. Old virtual keys/spend history were not carried over. Previous `.env` copies:
  `litellm/.env.pre-*.bak` (git-ignored; contain old secrets).
- **Watchtower** auto-updates every container at 04:00 including `litellm:main-latest`, `open-webui:main`,
  `searxng:latest`, `speaches:latest-cpu` (moving tags). Pin them if an update ever breaks the stack.
- **Exposure:** Ollama (`:11434`), Netdata (`:19999`), LiteLLM (`:4001`) and Open WebUI (`:8080`) listen on all interfaces.

## Not done (deliberately skipped, or needs you)

- **Prometheus scrape of LiteLLM** — the config is in the repo; deploy on `mon-capitao`:
  follow "AI node scrape" in [`nodes/mon-capitao/README.md`](../../nodes/mon-capitao/README.md) (secret file **mode 644**, validate, then
  `docker compose up -d prometheus`). Then copy `annogrid-ai-node.json` (and the updated `annogrid-gateway-services.json`) into
  `nodes/vps-macauba/grafana-provisioning/dashboards/` on vps-macauba — Grafana rescans every 60 s, no restart.
- **HTTPS via Tailscale** (`tailscale serve`, needed for browser mic; HTTPS certs are already enabled on the tailnet) and
  binding the raw ports to the tailnet only.
- **Backups** of the LiteLLM Postgres and `open-webui-data`; **pinning** image versions.
- **Retiring the Wyoming voice stack** (`arlo/`): ≈ 450 MB RAM and ≈ 37 GB disk for a pipeline nothing uses.
- **Ollama tuning** needs `sudo` (command above).
