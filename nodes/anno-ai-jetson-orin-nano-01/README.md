# anno-ai-jetson-orin-nano-01: AI/ML Workload Node

> **Now `ai-jacaranda` (Tailscale name). What actually runs here is documented in
> [`docker/ai-jetson-orin/README.md`](../../docker/ai-jetson-orin/README.md)**: host Ollama →
> LiteLLM + Postgres → Open WebUI, plus the voice-AI stack in [`arlo/`](../../arlo/) and node
> metrics from [`docker/shared/monitoring/`](../../docker/shared/monitoring/). This node is scoped to
> AI + monitoring only. The `docker-compose.yml` in this directory is a legacy template — do **not**
> `docker compose up` it: it defines a second `node-exporter` that collides with the live one.
> Deploy with `make deploy-ai` (or `docker/ai-jetson-orin/litellm/setup.sh`).

**Hardware**: NVIDIA Jetson Orin Nano  
**Role**: GPU-accelerated machine learning workloads  
**GPU**: 40-core CUDA with 128 tensor cores  
**Status**: 🟢 Active

---

## Quick Start

```bash
# SSH into node (ubuntu user, not pi)
ssh ubuntu@anno-ai-jetson-orin-nano-01.local

# Verify GPU
nvidia-smi

# Deploy services
docker compose up -d

# Check GPU utilization
tegrastats --interval 1000
```

---

## GPU Environment

### Verify GPU Support

```bash
# Check CUDA availability
nvcc --version

# Check GPU status
nvidia-smi

# Jetson-specific stats (power, temperature)
tegrastats
```

### GPU Memory Management

```bash
# Check GPU memory usage
nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv,nounits

# Monitor in real-time
watch -n 1 nvidia-smi
```

---

## Deploying ML Models

### TensorFlow

```python
import tensorflow as tf

# Verify GPU acceleration
gpus = tf.config.list_physical_devices('GPU')
print(f"GPUs detected: {len(gpus)}")

# Use GPU for inference
model = tf.keras.models.load_model('model.h5')
predictions = model.predict(data)  # Runs on GPU
```

### PyTorch

```python
import torch

# Verify CUDA
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"CUDA devices: {torch.cuda.device_count()}")

# Move model to GPU
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = model.to(device)
output = model(input_tensor)  # Runs on GPU
```

---

## Container Configuration

All containers should have GPU support enabled:

```yaml
# In docker-compose.yml
services:
  ml-inference:
    image: your-ml-image:latest
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
```

---

## Performance Monitoring

**GPU Metrics**: http://localhost:9100/metrics (includes GPU stats)

**Key Metrics**:
- GPU utilization (%)
- GPU memory used (MB)
- GPU temperature (°C)
- Model inference time (ms)

---

## Troubleshooting

### GPU Not Detected

```bash
# Check NVIDIA Docker support
docker run --rm --runtime=nvidia nvidia/cuda:12.2.0-base nvidia-smi

# Verify nvidia-docker installation
which nvidia-docker

# Check Docker daemon config
cat /etc/docker/daemon.json | grep -i nvidia
```

### Out of GPU Memory

```bash
# Check current usage
nvidia-smi

# Solutions:
# 1. Reduce batch size
# 2. Use quantized models (INT8)
# 3. Use gradient checkpointing
# 4. Use memory-efficient frameworks (TFLite)
```

### High GPU Temperature

```bash
# Check temperature
tegrastats | grep -i temp

# If >75°C, reduce:
# - Model complexity
# - Batch size
# - Inference concurrency
# - Check cooling fan status
```

---

## Useful Commands

```bash
# Monitor GPU in real-time
nvidia-smi dmon

# Detailed GPU info
nvidia-smi -q

# Power consumption
tegrastats | grep "Power"

# All metrics with history
watch -n 0.5 'nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv,nounits'
```

---

## Deployment Tips

1. **Use TensorRT** for model optimization
   ```bash
   # Convert TensorFlow model to TensorRT
   trtexec --onnx=model.onnx --saveEngine=model.plan
   ```

2. **Quantization** reduces model size and memory
   ```python
   # TensorFlow quantization
   converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
   converter.optimizations = [tf.lite.Optimize.DEFAULT]
   tflite_model = converter.convert()
   ```

3. **Batch Processing** for efficiency
   - Process multiple samples together
   - Better GPU utilization
   - Lower latency per sample

---

**For detailed documentation see**: [../../docs/architecture/nodes-inventory.md](../../docs/architecture/nodes-inventory.md)
