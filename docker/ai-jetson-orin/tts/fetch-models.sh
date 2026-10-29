#!/usr/bin/env bash
# Download the Pocket TTS weights into ./hf-cache using the service image (so versions match).
#
#   HF_TOKEN=hf_xxx ./fetch-models.sh     # a Hugging Face *Read* token; account must have accepted
#                                         # the terms at https://huggingface.co/kyutai/pocket-tts
#
# The token is only used here; the running service is offline (HF_HUB_OFFLINE=1).
set -euo pipefail
cd "$(dirname "$0")"

: "${HF_TOKEN:?set HF_TOKEN to a Hugging Face Read token (see the header of this script)}"
IMAGE="${TTS_IMAGE:-annogrid/pocket-tts:jetson}"

docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "build the image first: docker compose build pocket-tts (in ../litellm)"; exit 1; }
mkdir -p hf-cache
docker run --rm --runtime nvidia \
  -e HF_TOKEN -e HF_HOME=/models/hf \
  -v "$PWD/hf-cache:/models/hf" \
  --entrypoint python3 "$IMAGE" /app/fetch_models.py
