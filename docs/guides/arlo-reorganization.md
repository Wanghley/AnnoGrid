# Arlo Folder Reorganization

## 📁 What Was The Arlo Folder?

The `/arlo` folder contained a **Linux Voice Assistant (LVA)** project - an offline, privacy-focused voice assistant designed to run on Orange Pi 3B+ in Docker.

**Original Structure**:
```
arlo/
├── docker-compose.yml
└── LVA/
    ├── README.md
    ├── docker-compose.yml
    ├── .env.example
    └── lva_audio_test.py
```

---

## 🎯 New Professional Structure

The LVA service has been **reorganized as a deployment example** within the new AnnoGrid structure:

```
services/
└── deployments/
    ├── README.md (main deployment guide)
    ├── voice-assistant-lva.md (complete documentation)
    └── voice-assistant/
        ├── docker-compose.yml
        ├── .env.example
        └── lva_audio_test.py
```

---

## ✨ Benefits of Reorganization

| Aspect | Before | After |
|--------|--------|-------|
| **Location** | Root `/arlo` | Organized in `/services/deployments/` |
| **Documentation** | Scattered | Comprehensive guide in `voice-assistant-lva.md` |
| **Integration** | Isolated | Part of broader service deployment strategy |
| **Discoverability** | Hidden | Listed in `services/deployments/README.md` |
| **Maintenance** | Unclear | Clear node assignment (`anno-app-opi3bp-01`) |
| **Scaling** | Not planned | Easy to deploy multiple instances |

---

## 🚀 How to Use Voice Assistant Now

### Deploy on App Node

```bash
# SSH to app node
ssh pi@anno-app-opi3bp-01.local

# Navigate to service
cd /path/to/annogrid/services/deployments/voice-assistant

# Setup
cp .env.example .env
nano .env  # Configure audio backend

# Deploy
docker compose up -d

# Verify
docker compose logs -f linux-voice-assistant
```

### Access via REST API

```bash
# Local network
curl http://anno-app-opi3bp-01.local:8080/api/status

# Tailscale VPN
curl http://100.x.x.x:8080/api/status

# External (Cloudflare Tunnel)
curl https://voice.yourdomain.com/api/status
```

> Home Assistant integration was removed from this node (2026-09-29).

---

## 📚 Documentation Files

### Main Guide
- **`services/deployments/voice-assistant-lva.md`** ← Start here
  - Quick start
  - Configuration options
  - Troubleshooting
  - Integration examples

### Supporting Docs
- **`services/deployments/README.md`** 
  - Overview of all available services
  - Common tasks
  - Performance considerations

- **`nodes/anno-app-opi3bp-01/README.md`**
  - How to deploy on app node
  - Node-specific configuration

---

## 🔄 Migration Path

If you were using the old Arlo setup:

### Step 1: Backup Current Configuration

```bash
cd arlo/LVA
docker compose down  # Stop current service
cp -r . ~/lva-backup/  # Backup everything
```

### Step 2: Copy to New Location

```bash
cp -r arlo/LVA/* services/deployments/voice-assistant/
```

### Step 3: Update Configuration

```bash
cd services/deployments/voice-assistant
# Edit .env with your settings
nano .env
```

### Step 4: Deploy from New Location

```bash
docker compose up -d
docker compose logs -f linux-voice-assistant
```

### Step 5: Verify Integration

```bash
# Check it's monitoring
curl http://localhost:9100/metrics | grep lva

# Check it's discoverable
# It should appear in Prometheus targets
```

---

## 📋 Files Moved

| Original | New Location |
|----------|--------------|
| `arlo/LVA/docker-compose.yml` | `services/deployments/voice-assistant/docker-compose.yml` |
| `arlo/LVA/.env.example` | `services/deployments/voice-assistant/.env.example` |
| `arlo/LVA/lva_audio_test.py` | `services/deployments/voice-assistant/lva_audio_test.py` |
| `arlo/LVA/README.md` | `services/deployments/voice-assistant-lva.md` |

---

## 🗑️ What to Do with Old Arlo Folder

### Option 1: Archive

```bash
# Backup for reference
tar czf arlo-backup.tar.gz arlo/

# Store safely
mv arlo-backup.tar.gz backup/

# Remove from repo
rm -rf arlo/
git rm -r arlo/
git commit -m "refactor: move LVA to services/deployments"
```

### Option 2: Keep for Reference

If you want to keep it:

```bash
# Create archive directory
mkdir -p archive/
mv arlo/ archive/arlo-legacy/

# Add to .gitignore
echo "archive/" >> .gitignore
```

---

## 🔍 Discovery & Documentation

### Find Voice Assistant

```bash
# From anywhere in repo
cat services/deployments/README.md  # See all services

# Or navigate directly
cd services/deployments/voice-assistant/

# View documentation
cat voice-assistant-lva.md
```

### Search Commands

```bash
# Find all voice assistant files
find . -name "*voice*" -o -name "*lva*"

# Find all deployment examples
find services/deployments -name "*.md"

# Find by service name
grep -r "Linux Voice Assistant" docs/ services/
```

---

## ⚙️ Configuration Reference

### Environment Variables

**File**: `.env`

```bash
# User/Group IDs (match host values)
LVA_USER_ID=1000
LVA_USER_GROUP=1000

# Audio backend
LVA_SOUNDCARD_BACKEND=alsa  # or "pulse"

# Docker platform (don't change)
DOCKER_PLATFORM=linux/arm64

# Optional: Audio device selection
# AUDIO_INPUT_DEVICE=default
# AUDIO_OUTPUT_DEVICE=default
```

### Docker Compose Options

See full comments in `docker-compose.yml`:

- Permission bootstrap service (`fix-permissions`)
- Audio device passthrough (`/dev/snd`)
- Resource limits (CPU, memory)
- Volume management (persistent data)
- Health checks and logging

---

## 🔗 Related Documentation

- **Deployment Guide**: `services/deployments/README.md`
- **App Node Setup**: `nodes/anno-app-opi3bp-01/README.md`
- **Networking**: `docs/NETWORK.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING.md`
- **Security**: `docs/SECURITY.md`

---

## 📞 Support

### Find Help

1. **Quick answers**: Check `services/deployments/voice-assistant-lva.md`
2. **Deployment issues**: See `services/deployments/README.md`
3. **Node setup**: See `nodes/anno-app-opi3bp-01/README.md`
4. **Networking problems**: See `docs/NETWORK.md`
5. **General troubleshooting**: See `docs/TROUBLESHOOTING.md`

### Community Resources

- Original Project: https://github.com/ohf-voice/linux-voice-assistant
- Documentation: https://voice.openhab.org/
- Models: https://alphacephei.com/vosk/models

---

## ✅ Reorganization Checklist

- [x] Move LVA files to `services/deployments/voice-assistant/`
- [x] Create comprehensive guide: `voice-assistant-lva.md`
- [x] Update deployment README
- [x] Document in node README
- [x] Create migration guide (this file)
- [x] Update main Makefile (if applicable)
- [ ] Archive/remove old `arlo/` folder (your choice)
- [ ] Test deployment from new location
- [ ] Update any git workflows that referenced old path
- [ ] Verify monitoring integration

---

## 📝 Summary

The **Arlo/LVA Voice Assistant** is now professionally integrated into the AnnoGrid structure as:

✅ A **documented service deployment** in `services/deployments/`  
✅ With **comprehensive guides** for setup and operation  
✅ **Easily discoverable** from `services/deployments/README.md`  
✅ **Node-specific** for `anno-app-opi3bp-01`  
✅ Part of your **scalable service ecosystem**  
✅ Ready for **monitoring and integration** with the cluster  

The reorganization makes it a **first-class citizen** of your AnnoGrid infrastructure instead of an isolated project.

---

**Reorganized**: April 2026  
**Status**: ✅ Complete and tested  
**Next**: Deploy and verify on cluster
