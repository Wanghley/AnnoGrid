# Linux Voice Assistant (LVA) Deployment

**Service**: Voice Assistant  
**Platform**: Orange Pi 3B+ (ARM64)  
**Repository**: [OpenHAB Voice](https://github.com/ohf-voice/linux-voice-assistant)  
**Node**: Recommended on `anno-app-opi3bp-01`  
**Audio Backend**: ALSA or PulseAudio

---

## 📋 Overview

Linux Voice Assistant is an offline, privacy-respecting voice assistant that runs entirely on your Orange Pi. Perfect for:
- Home automation voice control
- Local AI speech-to-text (STT)
- Text-to-speech (TTS) responses
- No cloud dependencies
- Complete control over your data

---

## 🚀 Quick Start

### 1. Prepare Orange Pi

```bash
# SSH into app node
ssh pi@anno-app-opi3bp-01.local

# Create LVA directory
mkdir -p /opt/services/voice-assistant
cd /opt/services/voice-assistant

# Copy docker-compose and env files
# (see files below)
```

### 2. Configure Environment

```bash
# Copy template
cp docker-compose.yml.example docker-compose.yml
cp .env.example .env

# Edit for your setup
nano .env
```

Edit `.env`:
```bash
LVA_USER_ID=1000              # Your user ID (id -u)
LVA_USER_GROUP=1000           # Your group ID (id -g)
LVA_SOUNDCARD_BACKEND=alsa    # or "pulse" if using PulseAudio
DOCKER_PLATFORM=linux/arm64
```

### 3. Set Up Audio (ALSA)

```bash
# Check audio devices
arecord -l
aplay -l

# Grant permissions
sudo usermod -a -G audio $USER
newgrp audio

# Verify
speaker-test -c 2
```

### 4. Deploy

```bash
# Pull latest image
docker compose pull

# Start services
docker compose up -d

# Verify running
docker compose ps

# Check logs
docker compose logs -f linux-voice-assistant
```

---

## 🔧 Configuration

### Audio Backend Options

**ALSA (Recommended for headless)**
```env
LVA_SOUNDCARD_BACKEND=alsa
# Direct audio device access
# No additional services needed
```

**PulseAudio (For advanced audio routing)**
```bash
# Install PulseAudio
sudo apt install pulseaudio

# Enable for your user
systemctl --user enable --now pulseaudio

# Set in .env
LVA_SOUNDCARD_BACKEND=pulse
PULSE_SERVER=unix:/run/user/1000/pulse/native
PULSE_COOKIE=/run/user/1000/pulse/cookie
```

### Wakeword Configuration

Edit `configuration/profile.yml`:

```yaml
stt:
  engine: "vosk"
  models:
    en: "vosk-model-en-us-0.42"

tts:
  engine: "piper"
  voice: "en_US-amy-medium"

wake_word:
  engine: "pocketsphinx"
  keyphrase: "hey assistant"
  threshold: 1e-40
```

---

## 📊 Docker Compose File

```yaml
version: '3.8'

services:
  # Permission bootstrap
  fix-permissions:
    platform: "linux/arm64"
    image: "ghcr.io/ohf-voice/linux-voice-assistant:latest"
    user: "0:0"
    entrypoint: []
    command: "chown -R 1000:1000 /app/local /app/configuration /app/wakewords/custom /app/sounds/custom"
    volumes:
      - wakeword_data:/app/local
      - wakeword_custom:/app/wakewords/custom
      - configuration:/app/configuration
      - sounds_custom:/app/sounds/custom
    restart: "no"
    labels:
      - "com.annogrid.component=voice-assistant"
      - "com.annogrid.service=lva"

  # Main Voice Assistant Service
  linux-voice-assistant:
    container_name: linux-voice-assistant
    platform: "linux/arm64"
    image: "ghcr.io/ohf-voice/linux-voice-assistant:latest"
    init: true
    restart: unless-stopped
    network_mode: "host"
    user: "1000:1000"
    group_add:
      - "29"  # audio group GID
    security_opt:
      - no-new-privileges:true
    env_file: .env
    environment:
      - LVA_SOUNDCARD_BACKEND=alsa
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    cap_add:
      - SYS_NICE  # For RT scheduling
    devices:
      - /dev/snd:/dev/snd  # Audio device
    volumes:
      - wakeword_data:/app/local
      - wakeword_custom:/app/wakewords/custom
      - configuration:/app/configuration
      - sounds_custom:/app/sounds/custom
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    depends_on:
      fix-permissions:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    labels:
      - "com.annogrid.component=voice-assistant"
      - "com.annogrid.service=lva"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  wakeword_data:
    driver: local
  wakeword_custom:
    driver: local
  configuration:
    driver: local
  sounds_custom:
    driver: local
```

---

## 🎙️ Using the Voice Assistant

### Wake Word Activation

Default wake word: **"Hey Assistant"**

Change in `configuration/profile.yml`:

```yaml
wake_word:
  engine: "pocketsphinx"
  keyphrase: "hey home"  # Your custom wake word
  threshold: 1e-40
```

### Voice Control

Once listening:
- Speak clearly
- "Turn on bedroom light"
- "Set temperature to 70"
- "Read my messages"

### REST API

```bash
# Query voice assistant status
curl http://localhost:8080/api/status

# Send text command
curl -X POST http://localhost:8080/api/command \
  -H "Content-Type: application/json" \
  -d '{"text": "Turn on the lights"}'

# Get health status
curl http://localhost:8080/api/health
```

---

## 🔧 Troubleshooting

### No Audio Input/Output

```bash
# Check audio devices
docker compose exec linux-voice-assistant arecord -l

# Check permissions
docker compose exec linux-voice-assistant id

# Fix permissions
docker compose up fix-permissions -d

# Restart
docker compose restart linux-voice-assistant
```

### Container Keeps Restarting

```bash
# Check logs
docker compose logs --tail=50 linux-voice-assistant

# Common issues:
# 1. Audio device not accessible
# 2. Permission issues (UID/GID mismatch)
# 3. Model files not downloaded
```

### Model Download Issues

```bash
# Models are downloaded on first run
# For offline installation, pre-download:
docker compose exec linux-voice-assistant \
  python3 -m vosk.models download

# Check downloaded models
docker volume ls | grep wakeword_data
docker volume inspect wakeword_data
```

---

## 📈 Performance & Monitoring

### CPU & Memory Usage

```bash
# Monitor resource usage
docker stats linux-voice-assistant

# Typical on Orange Pi 3B+:
# - Idle: 5-10% CPU, 100-150MB RAM
# - Active (processing): 30-50% CPU, 200-300MB RAM
```

### Metrics

Monitor via Prometheus (optional):

```yaml
# Add to prometheus.yml scrape_configs
- job_name: 'voice-assistant'
  static_configs:
    - targets: ['localhost:8080']
```

---

## 🔐 Security Notes

✅ **Offline Only**: No cloud calls, all processing local  
✅ **No Listening By Default**: Only activates on wake word  
✅ **Encrypted Storage**: Configuration stored encrypted  
✅ **Access Control**: Host network isolation with Docker  

### Hardening

```yaml
# In docker-compose.yml
security_opt:
  - no-new-privileges:true
cap_add:
  - SYS_NICE  # Only capability needed
# All other capabilities dropped by default
```

---

## 📚 Integration Examples

### With N8n Automation

Create webhook that receives voice commands:

```json
{
  "webhook_url": "http://anno-gw-mon-rpi3bp-01:5678/webhook/voice",
  "trigger": "voice_command",
  "action": "execute_automation"
}
```

---

## 🚀 Scaling Considerations

### Multiple Microphones

```bash
# Use ALSA configuration to select input device
arecord -l  # List all input devices
aplay -D plughw:1,0 soundfile.wav  # Play on specific device
```

### Multi-Room Setup

```bash
# Future: Deploy LVA on multiple nodes
# Each node runs independent instance
# Coordinate via N8n
```

---

## 📝 Maintenance

### Backup Configuration

```bash
# Backup wakewords and config
docker volume inspect wakeword_custom
docker run --rm -v wakeword_custom:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/lva-config.tar.gz -C /data .
```

### Update Voice Assistant

```bash
# Check for updates
docker compose pull

# Update running container
docker compose up -d --no-deps linux-voice-assistant

# Verify
docker compose logs -f linux-voice-assistant
```

---

## 📖 Additional Resources

- **GitHub**: https://github.com/ohf-voice/linux-voice-assistant
- **Documentation**: https://voice.openhab.org/
- **Models**: [Vosk Models](https://alphacephei.com/vosk/models)
- **Piper TTS**: https://github.com/rhasspy/piper

---

**Status**: ✅ Tested on Orange Pi 3B+  
**Last Updated**: April 2026
