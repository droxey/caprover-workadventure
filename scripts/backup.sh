#!/bin/bash
# ===========================================
# WorkAdventure Backup Script
# ===========================================
# Creates encrypted backups of all data

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="workadventure_backup_${DATE}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "WorkAdventure Backup"
echo "=========================================="
echo "Date: $(date)"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

# -------------------------------------------
# 1. Stop services for consistent backup
# -------------------------------------------
echo -e "${YELLOW}Pausing services for consistent backup...${NC}"
docker compose pause redis map-storage 2>/dev/null || true

# -------------------------------------------
# 2. Backup Redis data
# -------------------------------------------
echo "Backing up Redis data..."
docker run --rm \
    -v workadventure_redis-data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/${BACKUP_NAME}_redis.tar.gz -C /data .

# -------------------------------------------
# 3. Backup Map Storage
# -------------------------------------------
echo "Backing up map storage..."
docker run --rm \
    -v workadventure_map-storage:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/${BACKUP_NAME}_maps.tar.gz -C /data .

# -------------------------------------------
# 4. Backup configuration
# -------------------------------------------
echo "Backing up configuration..."
tar czf "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz" \
    --exclude='.env' \
    --exclude='*.backup' \
    .env.template \
    docker-compose*.yaml \
    nginx/ \
    livekit.yaml \
    2>/dev/null || true

# -------------------------------------------
# 5. Resume services
# -------------------------------------------
echo -e "${YELLOW}Resuming services...${NC}"
docker compose unpause redis map-storage 2>/dev/null || true

# -------------------------------------------
# 6. Create combined archive
# -------------------------------------------
echo "Creating combined archive..."
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" \
    ${BACKUP_NAME}_redis.tar.gz \
    ${BACKUP_NAME}_maps.tar.gz \
    ${BACKUP_NAME}_config.tar.gz

# Clean up individual files
rm -f ${BACKUP_NAME}_redis.tar.gz \
      ${BACKUP_NAME}_maps.tar.gz \
      ${BACKUP_NAME}_config.tar.gz

cd - > /dev/null

# -------------------------------------------
# 7. Calculate checksum
# -------------------------------------------
echo "Calculating checksum..."
sha256sum "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" > "$BACKUP_DIR/${BACKUP_NAME}.sha256"

# -------------------------------------------
# 8. Clean old backups
# -------------------------------------------
echo "Cleaning backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "workadventure_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "workadventure_backup_*.sha256" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# -------------------------------------------
# Summary
# -------------------------------------------
BACKUP_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)

echo ""
echo "=========================================="
echo -e "${GREEN}✅ Backup Complete${NC}"
echo "=========================================="
echo "File: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "Size: $BACKUP_SIZE"
echo "Checksum: $BACKUP_DIR/${BACKUP_NAME}.sha256"
echo ""
echo "To restore, run:"
echo "  ./scripts/restore-backup.sh $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo ""
