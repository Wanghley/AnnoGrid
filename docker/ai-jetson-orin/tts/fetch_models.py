"""Download the Pocket TTS voice-cloning weights into the shared cache (run by fetch-models.sh).

kyutai/pocket-tts is gated: accept the terms at https://huggingface.co/kyutai/pocket-tts and use a *Read*
token (HF_TOKEN). A token from the browser/OAuth `hf auth login` flow gets a 403 on gated repos.
"""
import os
import sys
import time

os.environ["HF_HUB_OFFLINE"] = "0"

from server import LANGS, POCKET_NAME  # noqa: E402  (same language list the service serves)

if not os.environ.get("HF_TOKEN"):
    sys.exit("HF_TOKEN is not set (a Hugging Face *Read* token whose account accepted the Kyutai terms).")

from pocket_tts import TTSModel  # noqa: E402

failed = []
for lang in LANGS:
    t = time.time()
    try:
        # The loader resolves (and downloads) exactly the files the service will later read offline.
        model = TTSModel.load_model(language=POCKET_NAME[lang])
        if not model.has_voice_cloning:
            raise RuntimeError("got the no-cloning weights; the token cannot read kyutai/pocket-tts")
        del model
        print(f"ok   {lang:2s} {POCKET_NAME[lang]:11s} {time.time() - t:5.1f}s", flush=True)
    except Exception as exc:
        failed.append(lang)
        print(f"FAIL {lang:2s} {POCKET_NAME[lang]:11s} {exc}", flush=True)
sys.exit(1 if failed else 0)
