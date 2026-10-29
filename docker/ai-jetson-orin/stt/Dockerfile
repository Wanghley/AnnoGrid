# Speech-to-text (faster-whisper) on the Jetson Orin Nano GPU, served over an OpenAI-compatible API.
#
# Base: the Wyoming whisper image already used in ../../../arlo. It is the only one here with a CUDA build of
# ctranslate2 for JetPack 6 (cuBLAS/cuDNN that actually work on the Orin's iGPU, not the server-class SBSA
# builds that `nvidia/cuda` ships). We only add the web layer; the Wyoming entrypoint is replaced.
FROM dustynv/wyoming-whisper:r36.2.0

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HOME=/models/hf

WORKDIR /app

# Pin everything the base image already ships so the web layer cannot swap the CUDA-linked wheels.
RUN pip3 freeze | grep -i -E '^(numpy|ctranslate2|faster-whisper|av|onnxruntime|tokenizers|huggingface-hub)==' > /tmp/constraints.txt \
 && cat /tmp/constraints.txt \
 && pip3 install --index-url https://pypi.org/simple -c /tmp/constraints.txt fastapi uvicorn python-multipart \
 && python3 -c "import ctranslate2, faster_whisper; print('ctranslate2', ctranslate2.__version__, '| cuda devices', ctranslate2.get_cuda_device_count())"

COPY server.py /app/

ENTRYPOINT []
EXPOSE 8000
CMD ["python3", "-m", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
