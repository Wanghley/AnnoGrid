# Pocket TTS — `anno-tts` (GPU, multilingual, one voice)

[Kyutai Pocket TTS](https://github.com/kyutai-labs/pocket-tts) (100M parameters) on the Orin Nano's GPU behind an
OpenAI-compatible `/v1/audio/speech`. LiteLLM exposes it as **`anno-tts`**; Kokoro (in `speaches`) stays as the
fallback **`anno-tts-kokoro`**.

- **Languages:** English, Portuguese, Spanish, French, German, Italian, Dutch. The language is detected from the text.
- **One voice everywhere:** every language is cloned from the same 7-second reference clip, [`voices/arlo.wav`](voices/arlo.wav)
  (a synthetic Kokoro `af_heart` sample — the voice Open WebUI already used).
- **Speed (measured on this Nano):** ~1.6× realtime once a language is loaded, first audio ~0.2 s when streaming
  (`response_format: pcm`). Switching to a language that is not loaded adds ~2.5 s; the first request after the worker
  was stopped adds ~10 s.
- **Quality checks:** Whisper round-trip 94–100% on EN/PT/ES/FR; speaker-embedding similarity between languages averages
  0.44 (Kokoro's separate per-language voices: 0.28). Non-English output keeps the voice's character but drifts from the
  reference — it is a clone, not a recording.

## Layout

| File | |
|---|---|
| `supervisor.py` | listens on `:8000`; starts the GPU worker on the first request and stops it after `TTS_WORKER_IDLE_EXIT_S` idle |
| `server.py` | the GPU worker (`:8001`, internal): language detection, model cache, synthesis, encoding |
| `fetch-models.sh` / `fetch_models.py` | download the gated weights into `hf-cache/` (git-ignored) |
| `voices/*.wav` | reference voices — add a file, no restart needed |
| `Dockerfile` | `dustynv/pytorch:2.7-r36.4.0` + pocket-tts (see the comments in it for why that base) |

Compose service: `pocket-tts` in [`../litellm/docker-compose.yml`](../litellm/docker-compose.yml). Routing and the
fallback: [`../litellm/config.yaml`](../litellm/config.yaml) (`anno-tts`, `anno-tts-kokoro`, `fallbacks`).

## Setup

The weights are CC-BY-4.0 but **gated on Hugging Face**, so this cannot run unattended:

1. Accept the terms at <https://huggingface.co/kyutai/pocket-tts> with your account.
2. Create a **Read** token at <https://huggingface.co/settings/tokens>. A token from the browser login
   (`hf auth login` → OAuth) gets a 403 on gated repos even after you accept the terms.
3. From `../litellm`: `docker compose build pocket-tts`, then `HF_TOKEN=hf_xxx ../tts/fetch-models.sh` (~1.9 GB for
   the 7 languages). The token is only used by that one command; the service itself runs offline.
4. `docker compose up -d pocket-tts`, then restart LiteLLM if `config.yaml` changed.

Until step 3 is done, `anno-tts` requests fail and LiteLLM answers from Kokoro.

## API

```bash
curl -s http://pocket-tts:8000/v1/audio/speech -H 'Content-Type: application/json' \
  -d '{"input":"Bom dia! As luzes estão acesas.","voice":"arlo","response_format":"mp3"}' -o out.mp3
```

- `response_format`: `mp3` (default), `wav`, `flac`, `opus`, `pcm` (raw 16-bit 24 kHz, **streamed** as it is generated).
- `voice`: a file name from `voices/`. **Any other name (e.g. Kokoro's `af_heart`) maps to the default voice `arlo`**, so
  clients and the Kokoro fallback need no changes. `arlo:pt` forces Portuguese; so does `"language": "pt"`.
- Short or ambiguous text (below 60% detection confidence, e.g. "Ok.") uses `TTS_DEFAULT_LANG` — set it to `pt` in
  `.env` if most of what you say is Portuguese.
- Response headers `X-TTS-Language` / `X-TTS-Voice` say what was used (LiteLLM does not forward them).
- `GET /health` (worker state, loaded languages, memory), `GET /v1/audio/voices`.

## Memory (this is the constraint)

GPU allocations count against the container's memory on a Jetson. Measured:

| State | Container memory |
|---|---|
| worker stopped (idle > `TTS_WORKER_IDLE_EXIT_S`, 15 min) | ~50 MB |
| worker up, no model loaded (`TTS_IDLE_UNLOAD_S`, 5 min) | ~1.3 GB (CUDA context + libraries) |
| 1 / 2 / 3 languages loaded | ~1.7 / 2.1 / 2.5 GB (+ up to ~1 GB transient while a model loads) |

`TTS_MAX_LOADED=2` (least-recently-used eviction) and a 3.2 GB limit are set in the compose file. With the worker up
there is room for ~2 GB of LLM; prefer `qwen3.5:2b`-class models while using voice (see the node README).
`TTS_WORKER_IDLE_EXIT_S=0` keeps the worker resident (no 10 s restart, but the 1.3 GB never comes back).

## Voices and consent

Add a voice by dropping a clean 5–10 s mono WAV into `voices/`. Kyutai's terms prohibit cloning a real person's voice
without their explicit, lawful consent — use your own voice, a synthetic one, or a recording you have permission for.

## Troubleshooting

- **`anno-tts` always answers with Kokoro** (check `docker logs pocket-tts`): weights not staged, CUDA not visible
  (`runtime: nvidia`), or a worker crash. `curl pocket-tts:8000/health` inside the compose network shows the worker state.
- **"could not download the weights for the model with voice cloning"** is pocket-tts hiding a 401/403: wrong token type
  or terms not accepted (see Setup). Test with `huggingface_hub.hf_hub_download("kyutai/pocket-tts", "languages/portuguese/model.safetensors")`
  to see the real error.
- **Do not** swap the base image for `nvidia/cuda` or pip-install `torch` from PyPI here: their aarch64 CUDA libraries are
  the server-class builds, which load and then fail at the first cuBLAS call on the Orin. The base image is ~20 GB on disk.
- **Do not** raise `numpy` above 1.26: this torch build was compiled against numpy 1.x (pocket-tts declares `numpy>=2`
  but works on 1.26, which is why it is installed with `--no-deps`).
- Half precision (`model.half()`) fails inside Pocket TTS (input/bias dtype mismatch) — fp32 only.
