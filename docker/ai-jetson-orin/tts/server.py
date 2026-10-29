"""OpenAI-compatible speech server for Kyutai Pocket TTS: multilingual, one cloned voice, GPU.

POST /v1/audio/speech   {"input": "...", "voice": "arlo", "response_format": "mp3"}
GET  /v1/audio/voices   /health   /v1/models

Pocket TTS ships one ~100M model per language. The language is detected from the text (or forced with
`"language": "pt"` or a `voice` of `arlo:pt`), the matching model is loaded on demand and cloned from the
voice's reference clip, so every language speaks with the same voice. Only TTS_MAX_LOADED language models stay
resident, and all of them are dropped after TTS_IDLE_UNLOAD_S of silence: the Orin Nano shares 8 GB between
the GPU and the LLMs.

Voices are the *.wav files in TTS_VOICES_DIR (add a file, no restart). Any voice name that is not a file
(e.g. the Kokoro `af_heart` Open WebUI sends) maps to TTS_DEFAULT_VOICE, so clients and the Kokoro fallback
keep working unchanged.
"""
import gc
import io
import logging
import os
import threading
import time
from collections import OrderedDict
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, Response, StreamingResponse
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("pocket-tts")

DEVICE = os.environ.get("TTS_DEVICE", "cuda")
VOICES_DIR = Path(os.environ.get("TTS_VOICES_DIR", "/voices"))
DEFAULT_VOICE = os.environ.get("TTS_DEFAULT_VOICE", "arlo")
DEFAULT_LANG = os.environ.get("TTS_DEFAULT_LANG", "en")
MAX_LOADED = int(os.environ.get("TTS_MAX_LOADED", "2"))
IDLE_UNLOAD_S = int(os.environ.get("TTS_IDLE_UNLOAD_S", "600"))
MAX_CHARS = int(os.environ.get("TTS_MAX_INPUT_CHARS", "4000"))
MIN_DETECT_CONF = float(os.environ.get("TTS_MIN_DETECT_CONF", "0.6"))

# ISO code -> Pocket TTS config name.
POCKET_NAME = {"en": "english", "pt": "portuguese", "es": "spanish", "fr": "french",
               "de": "german", "it": "italian", "nl": "dutch"}
LANGS = [l.strip() for l in os.environ.get("TTS_LANGS", ",".join(POCKET_NAME)).split(",") if l.strip() in POCKET_NAME]
if DEFAULT_LANG not in LANGS:
    LANGS.append(DEFAULT_LANG)

CONTENT_TYPES = {"mp3": "audio/mpeg", "wav": "audio/wav", "flac": "audio/flac", "opus": "audio/ogg", "pcm": "audio/pcm"}

CUDA_OK = DEVICE != "cuda" or torch.cuda.is_available()
if not CUDA_OK:
    log.error("TTS_DEVICE=cuda but CUDA is not available; /health and speech will return 503")

# ---- language detection (restricted to the languages we can speak) ---------------------------------------
try:
    from py3langid.langid import MODEL_FILE, LanguageIdentifier
    _ident = LanguageIdentifier.from_pickled_model(MODEL_FILE, norm_probs=True)
    _ident.set_languages(LANGS)
except Exception as exc:  # detection is optional: without it every request uses DEFAULT_LANG
    log.warning("language detection unavailable (%s); using %s for everything", exc, DEFAULT_LANG)
    _ident = None


def detect_language(text: str) -> tuple[str, float]:
    if _ident is None or len(text.strip()) < 3:
        return DEFAULT_LANG, 0.0
    lang, conf = _ident.classify(text)
    if conf < MIN_DETECT_CONF:  # short or ambiguous text: don't guess
        return DEFAULT_LANG, float(conf)
    return lang, float(conf)


# ---- model cache ------------------------------------------------------------------------------------------
class Entry:
    def __init__(self, model):
        self.model = model
        self.states: dict[str, object] = {}  # voice name -> conditioned model state
        self.last_used = time.time()


_lock = threading.Lock()  # one synthesis at a time: the GPU and the memory budget are both tiny
_entries: "OrderedDict[str, Entry]" = OrderedDict()
_stats = {"requests": 0, "errors": 0, "loads": 0, "last_request": None}


def _free_memory():
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    try:  # hand freed arenas back to the OS (same reason speaches sets MALLOC_TRIM_THRESHOLD_)
        import ctypes
        ctypes.CDLL("libc.so.6").malloc_trim(0)
    except Exception:
        pass


def _get_entry(lang: str) -> Entry:
    """Caller holds _lock."""
    if lang in _entries:
        _entries.move_to_end(lang)
        return _entries[lang]
    from pocket_tts import TTSModel
    while len(_entries) >= MAX_LOADED:
        old = next(iter(_entries))
        del _entries[old]  # drop the only reference *before* freeing, or the model stays resident
        log.info("evicting %s model", old)
        _free_memory()
    t = time.time()
    model = TTSModel.load_model(language=POCKET_NAME[lang])
    if DEVICE == "cuda":
        model = model.to("cuda")
    _stats["loads"] += 1
    _entries[lang] = Entry(model)
    _free_memory()  # loading peaks ~1 GB above the steady state; give the transient garbage back now
    log.info("loaded %s model on %s in %.1fs", lang, DEVICE, time.time() - t)
    return _entries[lang]


def _voice_state(entry: Entry, voice: str):
    if voice not in entry.states:
        t = time.time()
        entry.states[voice] = entry.model.get_state_for_audio_prompt(VOICES_DIR / f"{voice}.wav")
        log.info("conditioned voice %s in %.2fs", voice, time.time() - t)
    return entry.states[voice]


def _unload_all():
    if _entries:
        log.info("idle for %ss: unloading %s", IDLE_UNLOAD_S, list(_entries))
        _entries.clear()
        _free_memory()


def _idle_watcher():
    while True:
        time.sleep(30)
        last = _stats["last_request"]
        if IDLE_UNLOAD_S > 0 and _entries and last and time.time() - last > IDLE_UNLOAD_S:
            if _lock.acquire(blocking=False):
                try:
                    _unload_all()
                finally:
                    _lock.release()


threading.Thread(target=_idle_watcher, daemon=True).start()


# ---- request handling -------------------------------------------------------------------------------------
def list_voices() -> list[str]:
    return sorted(p.stem for p in VOICES_DIR.glob("*.wav")) if VOICES_DIR.is_dir() else []


def resolve(voice: str | None, language: str | None, text: str) -> tuple[str, str, str]:
    """-> (voice file stem, language code, how the language was chosen)."""
    voice = (voice or "").strip().lower()
    forced = None
    for sep in (":", "@"):
        if sep in voice:
            voice, forced = voice.split(sep, 1)
            break
    forced = (language or forced or "").strip().lower().replace("_", "-").split("-")[0] or None
    voices = list_voices()
    if voice not in voices:
        if DEFAULT_VOICE not in voices:
            raise HTTPException(503, f"no reference voice: put {DEFAULT_VOICE}.wav in {VOICES_DIR}")
        voice = DEFAULT_VOICE
    if forced:
        if forced not in LANGS:
            raise HTTPException(400, f"language '{forced}' not supported; use one of {LANGS}")
        return voice, forced, "forced"
    lang, conf = detect_language(text)
    return voice, lang, f"detected({conf:.2f})"


def to_pcm16(audio: np.ndarray) -> bytes:
    return (np.clip(audio, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()


def encode(audio: np.ndarray, sr: int, fmt: str) -> bytes:
    if fmt == "pcm":
        return to_pcm16(audio)
    buf = io.BytesIO()
    if fmt == "wav":
        sf.write(buf, audio, sr, format="WAV", subtype="PCM_16")
    elif fmt == "mp3":
        sf.write(buf, audio, sr, format="MP3")
    elif fmt == "flac":
        sf.write(buf, audio, sr, format="FLAC")
    elif fmt == "opus":
        sf.write(buf, audio, sr, format="OGG", subtype="OPUS")
    else:
        raise HTTPException(400, f"response_format '{fmt}' not supported; use one of {sorted(CONTENT_TYPES)}")
    return buf.getvalue()


def synthesize(text: str, voice: str, lang: str) -> tuple[np.ndarray, int]:
    with _lock:
        entry = _get_entry(lang)
        state = _voice_state(entry, voice)
        audio = entry.model.generate_audio(state, text)
        entry.last_used = _stats["last_request"] = time.time()
        return audio.detach().float().cpu().numpy().reshape(-1), int(entry.model.sample_rate)


def stream_pcm(text: str, voice: str, lang: str):
    with _lock:
        entry = _get_entry(lang)
        state = _voice_state(entry, voice)
        for chunk in entry.model.generate_audio_stream(state, text):
            yield to_pcm16(chunk.detach().float().cpu().numpy().reshape(-1))
        entry.last_used = _stats["last_request"] = time.time()


class SpeechRequest(BaseModel):
    model: str | None = None
    input: str
    voice: str | None = None
    response_format: str = "mp3"
    speed: float | None = None  # accepted for API compatibility; Pocket TTS has no speed control
    language: str | None = None  # extension: force a language code instead of detecting it
    stream: bool | None = None


app = FastAPI(title="pocket-tts", docs_url=None, redoc_url=None)


@app.post("/v1/audio/speech")
async def speech(req: SpeechRequest):
    if not CUDA_OK:
        raise HTTPException(503, "CUDA unavailable")
    text = " ".join(req.input.split())
    if not text:
        raise HTTPException(400, "input is empty")
    if len(text) > MAX_CHARS:
        raise HTTPException(413, f"input is {len(text)} chars; the limit is {MAX_CHARS}")
    fmt = req.response_format.lower()
    if fmt not in CONTENT_TYPES:
        raise HTTPException(400, f"response_format '{fmt}' not supported; use one of {sorted(CONTENT_TYPES)}")
    voice, lang, how = resolve(req.voice, req.language, text)
    _stats["requests"] += 1
    headers = {"X-TTS-Language": lang, "X-TTS-Voice": voice}
    t0 = time.time()
    try:
        if fmt == "pcm":
            log.info("stream lang=%s (%s) voice=%s chars=%d", lang, how, voice, len(text))
            return StreamingResponse(stream_pcm(text, voice, lang), media_type=CONTENT_TYPES["pcm"],
                                     headers={**headers, "X-Sample-Rate": "24000"})
        audio, sr = await run_in_threadpool(synthesize, text, voice, lang)
        body = await run_in_threadpool(encode, audio, sr, fmt)
    except HTTPException:
        raise
    except Exception as exc:
        _stats["errors"] += 1
        log.exception("synthesis failed")
        raise HTTPException(500, f"synthesis failed: {exc}")
    dur, wall = len(audio) / sr, time.time() - t0
    log.info("lang=%s (%s) voice=%s chars=%d audio=%.1fs wall=%.1fs rtf=%.2fx fmt=%s",
             lang, how, voice, len(text), dur, wall, dur / max(wall, 1e-6), fmt)
    return Response(body, media_type=CONTENT_TYPES[fmt], headers=headers)


@app.get("/v1/audio/voices")
def voices():
    return {"voices": [{"voice_id": v, "name": v} for v in list_voices()], "languages": LANGS}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": "pocket-tts", "object": "model", "owned_by": "kyutai"}]}


def _rss_mb() -> int:
    with open("/proc/self/status") as f:
        return next(int(l.split()[1]) // 1024 for l in f if l.startswith("VmRSS"))


@app.get("/health")
def health():
    body = {"ok": CUDA_OK and DEFAULT_VOICE in list_voices(), "device": DEVICE, "cuda": torch.cuda.is_available(),
            "loaded": list(_entries), "voices": list_voices(), "languages": LANGS, "rss_mb": _rss_mb(),
            "cuda_alloc_mb": round(torch.cuda.memory_allocated() / 2**20) if torch.cuda.is_available() else 0,
            **_stats}
    return JSONResponse(body, status_code=200 if body["ok"] else 503)
