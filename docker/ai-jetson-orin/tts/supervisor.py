"""Thin front for the Pocket TTS GPU worker (server.py): starts it on demand, proxies, stops it when idle.

Why: on the Orin Nano an idle CUDA process still holds ~1.3 GB (CUDA context + torch libraries) that only a
process exit gives back, and that RAM is what the LLMs need. This front (no torch, ~60 MB) is what listens on
:8000; the first speech request after a quiet period pays a ~10-15 s worker start, everything else is served by
the warm worker. TTS_WORKER_IDLE_EXIT_S=0 keeps the worker running forever.
"""
import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("pocket-tts-front")

PORT = int(os.environ.get("TTS_WORKER_PORT", "8001"))
BASE = f"http://127.0.0.1:{PORT}"
IDLE_EXIT_S = int(os.environ.get("TTS_WORKER_IDLE_EXIT_S", "900"))
START_TIMEOUT_S = int(os.environ.get("TTS_WORKER_START_TIMEOUT_S", "120"))
VOICES_DIR = Path(os.environ.get("TTS_VOICES_DIR", "/voices"))
LANGS = [l.strip() for l in os.environ.get("TTS_LANGS", "en,pt,es,fr,de,it,nl").split(",") if l.strip()]
PASS_HEADERS = ("content-type", "x-tts-language", "x-tts-voice", "x-sample-rate")

_proc: subprocess.Popen | None = None
_start_lock = asyncio.Lock()
_inflight = 0
_last_activity = time.time()
_broken_until = 0.0  # after a failed start (no CUDA...) answer 503 at once instead of re-spawning per request
_client: httpx.AsyncClient


def _alive() -> bool:
    return _proc is not None and _proc.poll() is None


async def _stop_worker(reason: str):
    global _proc
    if _proc is None:
        return
    proc, _proc = _proc, None
    if proc.poll() is None:
        log.info("stopping worker (%s)", reason)
        proc.terminate()
        try:
            await asyncio.to_thread(proc.wait, 15)
        except subprocess.TimeoutExpired:
            proc.kill()
            await asyncio.to_thread(proc.wait)


async def _ensure_worker():
    global _proc, _broken_until
    if _alive():
        return
    if time.time() < _broken_until:
        raise HTTPException(503, "TTS worker unavailable (recent start failed)")
    async with _start_lock:
        if _alive():
            return
        t0 = time.time()
        log.info("starting GPU worker")
        _proc = subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "server:app", "--host", "127.0.0.1", "--port", str(PORT),
             "--workers", "1", "--log-level", "warning"])
        while time.time() - t0 < START_TIMEOUT_S:
            if _proc.poll() is not None:
                _proc = None
                _broken_until = time.time() + 30
                raise HTTPException(503, "TTS worker exited during start")
            try:
                r = await _client.get(f"{BASE}/health", timeout=2)
                if r.status_code == 200:
                    log.info("GPU worker ready in %.1fs", time.time() - t0)
                    return
                if r.status_code == 503:  # up, but CUDA / the reference voice is missing: don't retry for a while
                    await _stop_worker("unhealthy")
                    _broken_until = time.time() + 60
                    raise HTTPException(503, f"TTS worker unhealthy: {r.text[:200]}")
            except httpx.HTTPError:
                pass
            await asyncio.sleep(0.5)
        await _stop_worker("start timeout")
        _broken_until = time.time() + 30
        raise HTTPException(504, "TTS worker did not become ready")


async def _watchdog():
    while True:
        await asyncio.sleep(15)
        if (IDLE_EXIT_S > 0 and _alive() and _inflight == 0 and not _start_lock.locked()
                and time.time() - _last_activity > IDLE_EXIT_S):
            await _stop_worker(f"idle {IDLE_EXIT_S}s, returning ~1.3 GB to the system")


@asynccontextmanager
async def lifespan(_app):
    global _client
    _client = httpx.AsyncClient(timeout=httpx.Timeout(180, connect=5))
    task = asyncio.create_task(_watchdog())
    yield
    task.cancel()
    await _stop_worker("shutdown")
    await _client.aclose()


app = FastAPI(title="pocket-tts-front", docs_url=None, redoc_url=None, lifespan=lifespan)


def _passthrough(headers: httpx.Headers) -> dict:
    return {k: v for k, v in headers.items() if k.lower() in PASS_HEADERS and k.lower() != "content-type"}


@app.post("/v1/audio/speech")
async def speech(request: Request):
    global _inflight, _last_activity
    body = await request.body()
    try:
        streaming = json.loads(body).get("response_format", "mp3") == "pcm"
    except Exception:
        streaming = False  # the worker will answer 4xx for a malformed body
    _inflight += 1
    _last_activity = time.time()
    release = True
    try:
        for attempt in (1, 2):
            await _ensure_worker()
            try:
                req = _client.build_request("POST", f"{BASE}/v1/audio/speech", content=body,
                                            headers={"content-type": "application/json"})
                r = await _client.send(req, stream=streaming)
                break
            except httpx.ConnectError:  # worker died between requests: start a fresh one once
                await _stop_worker("connection lost")
                if attempt == 2:
                    raise HTTPException(502, "TTS worker unreachable")
        if streaming:
            async def gen():
                global _inflight, _last_activity
                try:
                    async for chunk in r.aiter_raw():
                        yield chunk
                finally:
                    await r.aclose()
                    _inflight -= 1
                    _last_activity = time.time()
            release = False
            return StreamingResponse(gen(), status_code=r.status_code, media_type=r.headers.get("content-type"),
                                     headers=_passthrough(r.headers))
        return Response(r.content, status_code=r.status_code, media_type=r.headers.get("content-type"),
                        headers=_passthrough(r.headers))
    finally:
        if release:
            _inflight -= 1
            _last_activity = time.time()


@app.get("/v1/audio/voices")
def voices():
    names = sorted(p.stem for p in VOICES_DIR.glob("*.wav")) if VOICES_DIR.is_dir() else []
    return {"voices": [{"voice_id": v, "name": v} for v in names], "languages": LANGS}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": "pocket-tts", "object": "model", "owned_by": "kyutai"}]}


@app.get("/health")
async def health():
    """200 while the front is up. The GPU worker is started lazily, so `worker: stopped` is normal when idle."""
    body = {"ok": True, "worker": "running" if _alive() else "stopped", "idle_exit_s": IDLE_EXIT_S,
            "idle_s": round(time.time() - _last_activity), "inflight": _inflight}
    if _alive():
        try:
            body["gpu"] = (await _client.get(f"{BASE}/health", timeout=2)).json()
        except Exception:
            body["gpu"] = None
    return JSONResponse(body)
