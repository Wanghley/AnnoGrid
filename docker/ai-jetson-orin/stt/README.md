# STT — `anno-stt` (GPU, multilingual)

[faster-whisper](https://github.com/SYSTRAN/faster-whisper) `small` on the Orin Nano's GPU behind an OpenAI-compatible
`/v1/audio/transcriptions`. LiteLLM exposes it as **`anno-stt`**; whisper-small on the CPU (`speaches`) stays as the
fallback **`anno-stt-cpu`**.

- **Languages:** everything Whisper knows; the language is auto-detected per request (Portuguese and English tested).
- **Speed (measured on this Nano):** ≈ 0.9 s for a 4–6 s utterance end to end (≈ 0.7 s of that is the model), ≈ 0.6 s
  for one word. The model stays resident, so there is no warm-up after the first request.
- **Accuracy:** word error rate ≈ 7% clean / ≈ 8% with added noise on 7 Portuguese/English test sentences (Kokoro audio),
  against ≈ 12% / 13% for `base` and ≈ 6% / 7% for `large-v3-turbo`. Turbo is 2× slower (1.8 s) and needs 1.7 GB, so it was not
  worth it. Small test, synthetic voices: treat the numbers as a comparison between models, not as a promise for your mic.
- **VAD is on.** Without it Whisper invents text on silence ("you") and took 16 s on 4 s of pure noise. With it both
  return empty text in ≈ 0.5 s.

## Layout

| File | |
|---|---|
| `server.py` | FastAPI app; loads the model at startup, one transcription at a time (`/health`, `/v1/models`) |
| `Dockerfile` | `dustynv/wyoming-whisper:r36.2.0` + FastAPI. That image is the one here with a working CUDA ctranslate2 for JetPack 6 |

Compose service: `stt` in [`../litellm/docker-compose.yml`](../litellm/docker-compose.yml). Routing and the fallback:
[`../litellm/config.yaml`](../litellm/config.yaml) (`anno-stt`, `anno-stt-cpu`, `fallbacks`, `model_group_retry_policy`).
The model downloads into the `stt-models` volume on the first start (≈ 0.5 GB, ≈ 2 min); after that it loads in 2 s.

## API

```bash
curl -s http://stt:8000/v1/audio/transcriptions -F file=@clip.wav          # {"text": "..."}
curl -s http://stt:8000/v1/audio/transcriptions -F file=@clip.wav -F language=pt -F response_format=verbose_json
```

- `file`: anything ffmpeg decodes (wav, mp3, webm/opus from the browser, ...), up to `STT_MAX_UPLOAD_MB` (25).
- `language`: optional; `pt`, `pt-BR`, `en`... Auto-detected when absent. Unknown codes answer 400.
- `prompt`: optional vocabulary hint (names, rooms, jargon). `STT_INITIAL_PROMPT` sets a default for clients that cannot
  send one (Open WebUI). It fixed a clipped one-word "Sim." that was heard as "sing".
- `response_format`: `json` (default), `text`, `verbose_json` (segments with timestamps). `srt`/`vtt` are not supported.
- `model` is accepted and ignored. The detected language comes back in the `X-STT-Language` header.
- `GET /health`: model, device, request and error counts.

## Configuration (environment of the `stt` service)

| Variable | Default | |
|---|---|---|
| `STT_MODEL` | `small` | any faster-whisper name or Hugging Face repo, e.g. `deepdml/faster-whisper-large-v3-turbo-ct2` (set it in `.env`) |
| `STT_COMPUTE_TYPE` | `int8_float16` | |
| `STT_BEAM_SIZE` | `1` | 5 costs ≈ 0.1 s and did not help on the test set |
| `STT_VAD` | `1` | `0` turns Silero VAD off (don't) |
| `STT_INITIAL_PROMPT` | empty | default vocabulary hint |

## Memory

The container sits at ≈ 0.6 GB by `docker stats` (process RSS ≈ 0.85 GB, ≈ 1.4 GB peak while the model loads; GPU
allocations count against it on a Jetson) and does not unload, which is what keeps the latency flat. Next to
`pocket-tts` (≈ 2 GB with two languages loaded) there was ≈ 0.7 GB of RAM available with no LLM loaded; loading an LLM
beside a hot `stt` + `pocket-tts` was not tested. Prefer `qwen3.5:2b`-class models while using voice, as the main README
says. If memory gets tight, give `stt` the same start-on-demand / exit-when-idle front that `pocket-tts` has
(`../tts/supervisor.py`); the first request after idle would then cost a few seconds. `large-v3-turbo` was only benchmarked, not run as
a service: it cost ≈ 1.7 GB of RAM by itself there, so the container's 1.8 GB limit would have to go up.

## Limits

- **Clips under a second can be misheard or mislabelled** ("Sim." as "sing", or detected as English at 0.72). Forcing
  `language` does not fix that; a `prompt` does.
- **One request at a time**: concurrent requests queue (three at once finish in ≈ 1.1 / 1.9 / 2.8 s).
- **Fallback is slow.** `anno-stt-cpu` gives the same transcripts but takes ≈ 11–12 s for a short clip, and when `stt` was
  stopped on purpose the first request took 15–70 s to get its answer, up to 60 s of it before the fallback even started
  (suspected: the proxy keeps dialling the dead container's cached address until the route's 60 s timeout; a fresh
  process failed over in under 2 s). Not fully diagnosed; a shorter route `timeout` would cut it but also cap long recordings. Keys with an explicit `models` list must include `anno-stt-cpu`, or LiteLLM
  refuses the fallback.
- The process prints a `double free` / `corrupted size` trace when it exits (native library teardown in the base image).
  It comes after "Finished server process"; `docker stop` completes normally.

## Troubleshooting

- **`anno-stt` answers from the CPU** (≈ 11 s): check `docker logs stt` and `docker compose ps stt`. A failed model load
  (no network on the first start) exits the process and the restart policy retries.
- **Do not** `pip install faster-whisper`/`ctranslate2` over the base image's: the PyPI aarch64 wheels have no CUDA.
  The Dockerfile pins what the base ships for that reason.
