#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AnnoGrid Application Server — SD Card Data Extractor
#
# Pulls everything relevant to anno-app-opi3bp-01's Docker stack out of a
# mounted, read-only copy of its SD card image (rootfs partition) and lays
# it out in a self-contained folder that restore-to-new-host.sh can consume.
#
# It does NOT trust hardcoded volume names — compose project names vary
# with COMPOSE_PROJECT_NAME / checkout directory name at deploy time.
# Instead it enumerates whatever actually exists under
# <rootfs>/var/lib/docker/volumes/ and tags each by keyword match against
# known services (postgres, n8n, core-data, etc), plus locates the live
# repo checkout (by finding docker/application-server/docker-compose.db.yml)
# to pull every stack's .env file and gitignored bind-mount dirs (n8n,
# tandoor, twenty-personal-crm, obsidian, homarr, homepage all live as
# siblings of application-server/ under docker/, not nested inside it).
#
# Usage:
#   sudo ./extract-sdcard-data.sh <mounted-rootfs-path> <output-dir>
#
# Example (continuing from the image-mount steps):
#   sudo mount -o ro,noload /dev/loop0p2 /mnt/rpi_root
#   sudo ./extract-sdcard-data.sh /mnt/rpi_root /path/to/backup/app-server-data
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

ROOTFS="${1:-}"
OUT="${2:-}"

if [ -z "$ROOTFS" ] || [ -z "$OUT" ]; then
    echo "Usage: $0 <mounted-rootfs-path> <output-dir>" >&2
    exit 1
fi

if [ ! -d "$ROOTFS/var/lib/docker" ]; then
    echo "❌ $ROOTFS does not look like a mounted Linux rootfs (no var/lib/docker found)." >&2
    echo "   Did you mount the correct partition (the ext4 rootfs, not the boot partition)?" >&2
    exit 1
fi

mkdir -p "$OUT/docker_volumes" "$OUT/env_files" "$OUT/bind_mounts" "$OUT/configs"

echo "🔎 Locating the AnnoGrid checkout on the image..."
DOCKER_DIR=""
COMPOSE_HIT="$(find "$ROOTFS" -maxdepth 10 -type f -name "docker-compose.db.yml" 2>/dev/null | grep '/application-server/' | head -n1 || true)"
if [ -n "$COMPOSE_HIT" ]; then
    DOCKER_DIR="$(dirname "$(dirname "$COMPOSE_HIT")")"   # .../docker (parent of application-server/)
    echo "   ✅ Found: $DOCKER_DIR"
else
    echo "   ⚠️  Could not auto-locate the docker/ checkout on the image."
    echo "      .env files and bind-mount data (n8n, tandoor, twenty-crm, obsidian, homarr, homepage) will be skipped."
    echo "      You can pass its path manually and re-run just that section."
fi

# ── 1. Docker named volumes (ground truth: whatever is actually on disk) ──
echo "📦 Archiving Docker named volumes..."
VOL_ROOT="$ROOTFS/var/lib/docker/volumes"
MANIFEST="$OUT/MANIFEST.txt"
{
    echo "AnnoGrid application-server (anno-app-opi3bp-01) — SD card extraction"
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Source rootfs: $ROOTFS"
    echo
    echo "== Docker named volumes found on the card =="
} > "$MANIFEST"

classify_volume () {
    local name="$1"
    case "$name" in
        *postgres*)                 echo "postgres (db)";;
        *maria*|*mysql*)            echo "mariadb (db)";;
        *redis*)                    echo "redis (cache)";;
        *mongo*)                    echo "mongodb (db)";;
        *minio*)                    echo "minio (object storage)";;
        *n8n*)                      echo "n8n (workflow automation)";;
        *monica*)                   echo "monica (personal CRM)";;
        *jellyfin*)                 echo "jellyfin (media)";;
        *uptime*kuma*)              echo "uptime-kuma (monitoring)";;
        *portainer*)                echo "portainer (docker mgmt — low value, safe to skip)";;
        *twenty*|*staticfiles*)     echo "twenty-crm / tandoor static assets";;
        *) echo "UNKNOWN — inspect manually";;
    esac
}

if [ -d "$VOL_ROOT" ]; then
    for vol_dir in "$VOL_ROOT"/*/; do
        [ -d "$vol_dir" ] || continue
        vol_name="$(basename "$vol_dir")"
        data_dir="${vol_dir}_data"
        [ -d "$data_dir" ] || data_dir="$vol_dir"
        label="$(classify_volume "$vol_name")"
        echo "  - $vol_name  →  $label" | tee -a "$MANIFEST"
        tar -czf "$OUT/docker_volumes/${vol_name}.tar.gz" -C "$data_dir" . 2>/dev/null \
            && echo "      archived ✅" \
            || echo "      ⚠️  archive failed (empty or permission issue) — check manually"
    done
else
    echo "  (none — $VOL_ROOT does not exist on this image)" | tee -a "$MANIFEST"
fi

# ── 2. .env files for every stack (secrets + config live ONLY here) ──
if [ -n "$DOCKER_DIR" ]; then
    echo "🔑 Collecting .env files..."
    echo >> "$MANIFEST"
    echo "== .env files recovered ==" >> "$MANIFEST"
    while IFS= read -r -d '' envfile; do
        rel="${envfile#"$DOCKER_DIR"/}"
        dest="$OUT/env_files/${rel//\//__}"
        cp "$envfile" "$dest"
        echo "  - $rel" | tee -a "$MANIFEST"
    done < <(find "$DOCKER_DIR" -maxdepth 3 -type f -name ".env" -print0 2>/dev/null)

    # ── 3. gitignored bind-mount data directories ──
    echo "📁 Collecting bind-mount data directories..."
    echo >> "$MANIFEST"
    echo "== Bind-mount directories recovered ==" >> "$MANIFEST"
    for rel in \
        "homarr/data" \
        "obsidian/couchdb-data" \
        "obsidian/couchdb-etc" \
        "tandoor/mediafiles" \
        "twenty-personal-crm/data" \
        "homepage/config" \
        "homepage/public"; do
        src="$DOCKER_DIR/$rel"
        if [ -d "$src" ]; then
            dest="$OUT/bind_mounts/${rel//\//__}"
            mkdir -p "$dest"
            rsync -aAX "$src"/ "$dest"/ 2>/dev/null && echo "  - $rel" | tee -a "$MANIFEST"
        fi
    done

    # ── 4. DB init-script configs (postgres/mariadb custom init, peekaping nginx) ──
    if [ -d "$DOCKER_DIR/application-server/configs" ]; then
        rsync -aAX "$DOCKER_DIR/application-server/configs"/ "$OUT/configs"/ 2>/dev/null
        echo "  - application-server/configs/ (postgres/mariadb init scripts)" | tee -a "$MANIFEST"
    fi
fi

echo
echo "✅ Done. Output written to: $OUT"
echo "   See $MANIFEST for a full inventory of what was recovered."
echo "   Next: run restore-to-new-host.sh (see RESTORE.md) on the target Docker host."
