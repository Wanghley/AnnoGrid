#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AnnoGrid Application Server — Restore extracted SD card data
# onto a fresh (or replacement) Docker host.
#
# Run this ON the target host (new SD card / new Orange Pi / temp box),
# AFTER copying the extraction output folder (produced by
# extract-sdcard-data.sh) onto it.
#
# Usage:
#   ./restore-to-new-host.sh <extraction-dir>
#
# Example:
#   ./restore-to-new-host.sh /home/pi/app-server-data
#
# This recreates each Docker named volume found in the extraction and
# restores its tarball into it. It does NOT start any containers and does
# NOT touch .env files or bind-mount data automatically — those need a
# manual review pass (see RESTORE.md) because secrets should generally be
# rotated, not blindly restored.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -d "$SRC/docker_volumes" ]; then
    echo "Usage: $0 <extraction-dir>   (expects <dir>/docker_volumes/*.tar.gz)" >&2
    exit 1
fi

echo "This will create/overwrite Docker volumes on THIS host from:"
echo "  $SRC/docker_volumes/"
read -p "Continue? [y/N] " confirm
[ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { echo "Aborted."; exit 0; }

for tarball in "$SRC"/docker_volumes/*.tar.gz; do
    [ -f "$tarball" ] || continue
    vol_name="$(basename "$tarball" .tar.gz)"

    if docker volume inspect "$vol_name" >/dev/null 2>&1; then
        echo "⚠️  Volume '$vol_name' already exists on this host."
        read -p "   Overwrite its contents? [y/N] " ov
        [ "$ov" = "y" ] || [ "$ov" = "Y" ] || { echo "   Skipped $vol_name"; continue; }
    else
        docker volume create "$vol_name" >/dev/null
        echo "✅ Created volume: $vol_name"
    fi

    docker run --rm \
        -v "${vol_name}:/target" \
        -v "$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball"):/backup.tar.gz:ro" \
        alpine sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xzf /backup.tar.gz -C /target" \
        && echo "   ↳ restored data into $vol_name"
done

echo
echo "✅ Volume restore complete."
echo
echo "Still manual (by design — see RESTORE.md):"
echo "  1. Review/rotate secrets, then place .env files from '$SRC/env_files/' next to each"
echo "     stack's docker-compose.yml (rename '<stack>__.env' back to '.env')."
echo "  2. Copy bind-mount folders from '$SRC/bind_mounts/' back to their stack directories"
echo "     (e.g. bind_mounts/homarr__data -> docker/homarr/data)."
echo "  3. Copy '$SRC/configs/' back to docker/application-server/configs/ if restoring the"
echo "     core db stack (postgres/mariadb init scripts)."
echo "  4. Bring stacks up in order: application-server (db -> app -> mon), then each"
echo "     standalone stack under docker/ (core-data, n8n, twenty-personal-crm, tandoor,"
echo "     obsidian, homarr, portainer, peekaping, homepage)."
