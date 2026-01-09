#!/bin/bash
# ===========================================
# WorkAdventure Restore Script
# ===========================================
# Restores from backup archive

set -euo pipefail

BACKUP_FILE="${1:-}"
TEMP_DIR="/tmp/workadventure_restore_$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

usage() {
    echo "Usage: $0 <backup_file.tar.gz>"
    echo ""
    echo "Example:"
    echo "  $0 ./backups/workadventure_backup_20240101_120000.tar.gz"
    exit 1
}

if [[ -z "$BACKUP_FILE" ]]; then
    usage
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo -e "${RED}Error: Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

echo "=========================================="
echo "WorkAdventure Restore"
echo "=========================================="
echo "Backup file: $BACKUP_FILE"
echo ""

# -------------------------------------------
# 1. Verify checksum if available
# -------------------------------------------
CHECKSUM_FILE="${BACKUP_FILE%.tar.gz}.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
    echo "Verifying checksum..."
    if sha256sum -c "$CHECKSUM_FILE" 2>/dev/null; then
        echo -e "${GREEN}✅ Checksum verified${NC}"
    else
        echo -e "${RED}❌ Checksum verification failed!${NC}"
        echo "The backup file may be corrupted."
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  No checksum file found, skipping verification${NC}"
fi

# -------------------------------------------
# 2. Confirm restore
# -------------------------------------------
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will overwrite existing data!${NC}"
echo "Current data will be LOST."
echo ""
read -p "Type 'RESTORE' to confirm: " CONFIRM

if [[ "$CONFIRM" != "RESTORE" ]]; then
    echo "Restore cancelled."
    exit 0
fi

# -------------------------------------------
# 3. Extract backup
# -------------------------------------------
echo ""
echo "Extracting backup..."
mkdir -p "$TEMP_DIR"
tar xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# -------------------------------------------
# 4. Stop services
# -------------------------------------------
echo "Stopping services..."
docker compose down 2>/dev/null || true

# -------------------------------------------
# 5. Restore Redis data
# -------------------------------------------
if [[ -f "$TEMP_DIR"/*_redis.tar.gz ]]; then
    echo "Restoring Redis data..."
    docker volume rm workadventure_redis-data 2>/dev/null || true
    docker volume create workadventure_redis-data
    docker run --rm \
        -v workadventure_redis-data:/data \
        -v "$TEMP_DIR":/backup \
        alpine sh -c "tar xzf /backup/*_redis.tar.gz -C /data"
    echo -e "${GREEN}✅ Redis data restored${NC}"
fi

# -------------------------------------------
# 6. Restore Map Storage
# -------------------------------------------
if [[ -f "$TEMP_DIR"/*_maps.tar.gz ]]; then
    echo "Restoring map storage..."
    docker volume rm workadventure_map-storage 2>/dev/null || true
    docker volume create workadventure_map-storage
    docker run --rm \
        -v workadventure_map-storage:/data \
        -v "$TEMP_DIR":/backup \
        alpine sh -c "tar xzf /backup/*_maps.tar.gz -C /data"
    echo -e "${GREEN}✅ Map storage restored${NC}"
fi

# -------------------------------------------
# 7. Restore configuration (optional)
# -------------------------------------------
if [[ -f "$TEMP_DIR"/*_config.tar.gz ]]; then
    echo ""
    read -p "Restore configuration files? (y/N): " RESTORE_CONFIG
    if [[ "$RESTORE_CONFIG" =~ ^[Yy]$ ]]; then
        tar xzf "$TEMP_DIR"/*_config.tar.gz
        echo -e "${GREEN}✅ Configuration restored${NC}"
    fi
fi

# -------------------------------------------
# 8. Start services
# -------------------------------------------
echo ""
echo "Starting services..."
docker compose -f docker-compose.hardened.yaml up -d

# -------------------------------------------
# 9. Wait for health checks
# -------------------------------------------
echo "Waiting for services to become healthy..."
sleep 10

# Check container status
docker compose ps

# -------------------------------------------
# Summary
# -------------------------------------------
echo ""
echo "=========================================="
echo -e "${GREEN}✅ Restore Complete${NC}"
echo "=========================================="
echo ""
echo "Verify the deployment:"
echo "  docker compose ps"
echo "  docker compose logs -f"
echo ""
