"""OpenAI-compatible speech-to-text server: faster-whisper on the Jetson GPU.

POST /v1/audio/transcriptions   multipart: file, [model], [language], [prompt], [response_format], [temperature]
GET  /health   /v1/models

One Whisper model (STT_MODEL, `small` by default) stays resident on the GPU, so the first request is as fast as
the hundredth (~0.7 s for a 5 s utterance on the Orin Nano). The language is auto-detected unless the request
sets `language` ("pt", "en", "pt-BR", ...); `model` is accepted and ignored, so LiteLLM and Open WebUI need no
changes beyond the route. Silero VAD is on: without it Whisper invents text on silence ("you") and can stall for
seconds on pure noise (measured 16 s, language detected as "nn").
"""
import io
import logging
import os
import threading
import time
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse
from faster_whisper import WhisperModel
from faster_whisper.audio import decode_audio

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("stt")

MODEL_NAME = os.environ.get("STT_MODEL", "small")
DEVICE = os.environ.get("STT_DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("STT_COMPUTE_TYPE", "int8_float16")
BEAM_SIZE = int(os.environ.get("STT_BEAM_SIZE", "1"))
VAD = os.environ.get("STT_VAD", "1") != "0"
# Vocabulary hint for clients that cannot send `prompt` (Open WebUI): names, rooms, jargon. Biases decoding toward
# these words, which fixes clipped one-word answers ("Sim." heard as "sing") at no cost. Empty = no bias.
INITIAL_PROMPT = os.environ.get("STT_INITIAL_PROMPT", "")
MAX_UPLOAD_MB = int(os.environ.get("STT_MAX_UPLOAD_MB", "25"))
DOWNLOAD_ROOT = os.environ.get("STT_DOWNLOAD_ROOT", "/models/hf")

FORMATS = ("json", "text", "verbose_json")

_model: WhisperModel | None = None
_lock = threading.Lock()  # one GPU: transcriptions run one at a time
_stats = {"requests": 0, "errors": 0}
_started = time.time()


@asynccontextmanager
async def lifespan(_: FastAPI):
    # A failed load (no network on the first run, bad STT_MODEL) exits the process; the restart policy retries.
    global _model
    t = time.time()
    _model = WhisperModel(MODEL_NAME, device=DEVICE, compute_type=COMPUTE_TYPE, download_root=DOWNLOAD_ROOT)
    log.info("loaded %s (%s, %s) in %.1fs", MODEL_NAME, DEVICE, COMPUTE_TYPE, time.time() - t)
    # The first call allocates the CUDA workspace; do it now so the first real request is not the slow one.
    segments, _info = _model.transcribe(np.zeros(16000, np.float32), beam_size=1)
    list(segments)
    log.info("warm after %.1fs", time.time() - t)
    yield


app = FastAPI(title="stt", lifespan=lifespan)


@app.get("/health")
def health():
    body = {"ok": _model is not None, "model": MODEL_NAME, "device": DEVICE, "compute_type": COMPUTE_TYPE,
            "vad": VAD, "uptime_s": round(time.time() - _started), **_stats}
    return JSONResponse(body, status_code=200 if _model is not None else 503)


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "faster-whisper"}]}


# A plain `def` endpoint: FastAPI runs it in a worker thread, so decoding and inference never block the loop.
@app.post("/v1/audio/transcriptions")
def transcriptions(
    file: UploadFile = File(...),
    model: str | None = Form(None),  # accepted for OpenAI-client compatibility, ignored
    language: str | None = Form(None),
    prompt: str | None = Form(None),
    response_format: str = Form("json"),
    temperature: float = Form(0.0),
):
    if response_format not in FORMATS:
        raise HTTPException(400, f"response_format must be one of {', '.join(FORMATS)}")
    if _model is None:
        raise HTTPException(503, "model not loaded")

    data = file.file.read(MAX_UPLOAD_MB * 1024 * 1024 + 1)
    if len(data) > MAX_UPLOAD_MB * 1024 * 1024:
        raise HTTPException(413, f"audio larger than {MAX_UPLOAD_MB} MB")
    try:
        audio = decode_audio(io.BytesIO(data), sampling_rate=16000)
    except Exception as exc:
        raise HTTPException(400, f"could not decode audio: {exc}")

    lang = None
    if language and language.lower() != "auto":
        lang = language.lower().replace("_", "-").split("-")[0]  # "pt-BR" -> "pt"

    _stats["requests"] += 1
    with _lock:
        t = time.time()
        try:
            segments, info = _model.transcribe(
                audio, language=lang, initial_prompt=prompt or INITIAL_PROMPT or None, temperature=temperature,
                beam_size=BEAM_SIZE, vad_filter=VAD, condition_on_previous_text=False,
            )
            segments = list(segments)
        except ValueError as exc:  # e.g. an unknown language code
            _stats["errors"] += 1
            raise HTTPException(400, str(exc))
        except Exception:
            _stats["errors"] += 1
            log.exception("transcription failed")
            raise HTTPException(500, "transcription failed")
        took = time.time() - t

    text = "".join(s.text for s in segments).strip()
    log.info("%.1fs audio in %.2fs, lang=%s, %d chars", info.duration, took, info.language, len(text))
    headers = {"X-STT-Language": info.language}
    if response_format == "text":
        return PlainTextResponse(text, headers=headers)
    if response_format == "json":
        return JSONResponse({"text": text}, headers=headers)
    return JSONResponse({
        "task": "transcribe", "language": info.language, "duration": round(info.duration, 2), "text": text,
        "segments": [{"id": i, "start": round(s.start, 2), "end": round(s.end, 2), "text": s.text.strip()}
                     for i, s in enumerate(segments)],
    }, headers=headers)
