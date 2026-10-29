# Pocket TTS (Kyutai, 100M) on the Jetson Orin Nano GPU, served over an OpenAI-compatible API.
#
# Base: jetson-containers' PyTorch for JetPack 6 / L4T r36.4 (CUDA 12.6, cuDNN 9, Jetson-built torch).
# Do NOT build on nvidia/cuda or install torch from PyPI here: their aarch64 CUDA libraries are the
# server-class (SBSA) builds, which load fine on the Orin's iGPU and then fail at the first cuBLAS call.
FROM dustynv/pytorch:2.7-r36.4.0

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Weights are staged on disk by fetch-models.sh; the running service never needs a Hugging Face token.
    HF_HOME=/models/hf \
    HF_HUB_OFFLINE=1

WORKDIR /app

# pocket-tts declares numpy>=2, but this torch build was compiled against numpy 1.x and crashes with 2.x.
# Install it with --no-deps (it works fine on numpy 1.26) and pin torch/numpy to what the base image ships.
RUN pip3 freeze | grep -i -E '^(torch|torchaudio|torchvision|numpy)==' > /tmp/constraints.txt \
 && cat /tmp/constraints.txt \
 && pip3 install --index-url https://pypi.org/simple -c /tmp/constraints.txt \
      einops fastapi "huggingface-hub>=0.13" pydantic python-multipart requests safetensors scipy \
      sentencepiece tokenizers typer typing-extensions uvicorn soundfile py3langid httpx \
 && pip3 install --index-url https://pypi.org/simple --no-deps pocket-tts==3.3.0 \
 && python3 -c "import numpy, torch; print('numpy', numpy.__version__, '| torch', torch.__version__, '| cuda', torch.cuda.is_available())"

COPY server.py supervisor.py fetch_models.py /app/

EXPOSE 8000
# supervisor.py listens on :8000 and runs server.py (the GPU worker, :8001) only while it has work to do.
CMD ["python3", "-m", "uvicorn", "supervisor:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
