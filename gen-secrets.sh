#!/bin/bash

# ===========================================
# WorkAdventure + LiveKit Secret Generator
# ===========================================
# Generates secure random secrets for deployment
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════╗"
echo "║   WorkAdventure + LiveKit Secret Generator       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Check if .env exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠ .env file already exists${NC}"
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Copy template if it exists
if [ -f ".env.template" ]; then
    cp .env.template .env
    echo -e "${GREEN}✓ Copied .env.template to .env${NC}"
else
    echo -e "${RED}✗ .env.template not found${NC}"
    exit 1
fi

# Generate secrets
echo ""
echo -e "${BLUE}Generating secrets...${NC}"

# Generate SECRET_KEY (32 bytes, base64)
SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n')

# Generate LiveKit API Key (starts with API, 17 chars total)
LIVEKIT_API_KEY="API$(openssl rand -hex 7)"

# Generate LiveKit API Secret (40 chars)
LIVEKIT_API_SECRET=$(openssl rand -base64 30 | tr -d '\n' | head -c 40)

# Generate Map Storage Password
MAP_PASSWORD=$(openssl rand -base64 16 | tr -d '\n' | head -c 20)

# Generate Ejabberd Password
EJABBERD_PASSWORD=$(openssl rand -base64 16 | tr -d '\n' | head -c 20)

# Generate Redis Password
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n' | head -c 32)

# CRITICAL: LIVEKIT_KEYS format must have space after colon
# Format: "APIkey: secret"
LIVEKIT_KEYS="${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"

# Auto-detect PUBLIC_IP
echo ""
echo -e "${BLUE}Detecting public IP...${NC}"
PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || echo "")
if [ -n "$PUBLIC_IP" ]; then
    echo -e "${GREEN}✓ Detected PUBLIC_IP: ${PUBLIC_IP}${NC}"
else
    echo -e "${YELLOW}⚠ Could not auto-detect PUBLIC_IP${NC}"
    PUBLIC_IP="YOUR_SERVER_IP"
fi

# Update .env file
echo ""
echo -e "${BLUE}Updating .env file...${NC}"

# Use sed to replace values (macOS and Linux compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
    sed -i '' "s|LIVEKIT_API_KEY=.*|LIVEKIT_API_KEY=${LIVEKIT_API_KEY}|g" .env
    sed -i '' "s|LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}|g" .env
    sed -i '' "s|LIVEKIT_KEYS=.*|LIVEKIT_KEYS=\"${LIVEKIT_KEYS}\"|g" .env
    sed -i '' "s|MAP_STORAGE_PASSWORD=.*|MAP_STORAGE_PASSWORD=${MAP_PASSWORD}|g" .env
    sed -i '' "s|EJABBERD_PASSWORD=.*|EJABBERD_PASSWORD=${EJABBERD_PASSWORD}|g" .env
    sed -i '' "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|g" .env
    sed -i '' "s|PUBLIC_IP=.*|PUBLIC_IP=${PUBLIC_IP}|g" .env
else
    # Linux
    sed -i "s|SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|g" .env
    sed -i "s|LIVEKIT_API_KEY=.*|LIVEKIT_API_KEY=${LIVEKIT_API_KEY}|g" .env
    sed -i "s|LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}|g" .env
    sed -i "s|LIVEKIT_KEYS=.*|LIVEKIT_KEYS=\"${LIVEKIT_KEYS}\"|g" .env
    sed -i "s|MAP_STORAGE_PASSWORD=.*|MAP_STORAGE_PASSWORD=${MAP_PASSWORD}|g" .env
    sed -i "s|EJABBERD_PASSWORD=.*|EJABBERD_PASSWORD=${EJABBERD_PASSWORD}|g" .env
    sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|g" .env
    sed -i "s|PUBLIC_IP=.*|PUBLIC_IP=${PUBLIC_IP}|g" .env
fi

echo -e "${GREEN}✓ SECRET_KEY generated${NC}"
echo -e "${GREEN}✓ LIVEKIT_API_KEY generated: ${LIVEKIT_API_KEY}${NC}"
echo -e "${GREEN}✓ LIVEKIT_API_SECRET generated${NC}"
echo -e "${GREEN}✓ LIVEKIT_KEYS generated (with correct format)${NC}"
echo -e "${GREEN}✓ MAP_STORAGE_PASSWORD generated${NC}"
echo -e "${GREEN}✓ EJABBERD_PASSWORD generated${NC}"
echo -e "${GREEN}✓ REDIS_PASSWORD generated${NC}"
echo -e "${GREEN}✓ PUBLIC_IP set to: ${PUBLIC_IP}${NC}"

echo ""
echo "══════════════════════════════════════════════════"
echo -e "${YELLOW}IMPORTANT: You still need to configure:${NC}"
echo ""
echo "  1. DOMAIN - Your domain name"
echo "     Example: workadventure.yourdomain.com"
echo ""
if [ "$PUBLIC_IP" == "YOUR_SERVER_IP" ]; then
    echo "  2. PUBLIC_IP - Your server's public IP"
    echo "     Get it with: curl -4 ifconfig.me"
    echo ""
fi
echo "  3. LIVEKIT_URL - Update to match your domain"
echo "     Example: wss://livekit.yourdomain.com"
echo ""
echo "══════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Edit .env file:${NC}"
echo "  nano .env"
echo ""
echo -e "${BLUE}Then deploy:${NC}"
echo "  docker-compose up -d"
echo ""
echo -e "${BLUE}Or run the diagnostic first:${NC}"
echo "  bash workadventure-diagnostic.sh"
echo ""
