#!/bin/bash

# ===========================================
# WorkAdventure + LiveKit Pre-Flight Check
# ===========================================
# Run this BEFORE deployment to verify configuration
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0

echo "╔══════════════════════════════════════════════════╗"
echo "║   Pre-Flight Check                               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Check .env file
if [ ! -f ".env" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo "  Run: cp .env.template .env && ./gen-secrets.sh"
    exit 1
fi

source .env

# Required checks
echo "Checking required configuration..."
echo ""

# DOMAIN
if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "workadventure.example.com" ]; then
    echo -e "${RED}✗ DOMAIN not configured${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ DOMAIN: $DOMAIN${NC}"
fi

# PUBLIC_IP
ACTUAL_IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "")
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "YOUR_SERVER_PUBLIC_IP" ]; then
    echo -e "${RED}✗ PUBLIC_IP not configured${NC}"
    echo -e "  ${BLUE}Your IP appears to be: $ACTUAL_IP${NC}"
    ERRORS=$((ERRORS + 1))
elif [ -n "$ACTUAL_IP" ] && [ "$PUBLIC_IP" != "$ACTUAL_IP" ]; then
    echo -e "${YELLOW}⚠ PUBLIC_IP ($PUBLIC_IP) differs from detected IP ($ACTUAL_IP)${NC}"
else
    echo -e "${GREEN}✓ PUBLIC_IP: $PUBLIC_IP${NC}"
fi

# SECRET_KEY
if [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" == "CHANGE_ME"* ]; then
    echo -e "${RED}✗ SECRET_KEY not configured${NC}"
    echo "  Run: ./gen-secrets.sh"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ SECRET_KEY is set${NC}"
fi

# LIVEKIT_API_KEY
if [ -z "$LIVEKIT_API_KEY" ] || [[ ! "$LIVEKIT_API_KEY" =~ ^API ]]; then
    echo -e "${RED}✗ LIVEKIT_API_KEY not configured or invalid${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ LIVEKIT_API_KEY: $LIVEKIT_API_KEY${NC}"
fi

# LIVEKIT_API_SECRET
if [ -z "$LIVEKIT_API_SECRET" ] || [ ${#LIVEKIT_API_SECRET} -lt 32 ]; then
    echo -e "${RED}✗ LIVEKIT_API_SECRET not configured or too short${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ LIVEKIT_API_SECRET is set (${#LIVEKIT_API_SECRET} chars)${NC}"
fi

# LIVEKIT_KEYS format check (CRITICAL)
echo ""
echo "Checking LIVEKIT_KEYS format (CRITICAL)..."
if [ -n "$LIVEKIT_KEYS" ]; then
    # Must have space after colon
    if [[ "$LIVEKIT_KEYS" =~ ^\"?API[a-f0-9]+:\ [^\ ]+\"?$ ]]; then
        echo -e "${GREEN}✓ LIVEKIT_KEYS format is correct${NC}"
    else
        echo -e "${RED}✗ LIVEKIT_KEYS format is WRONG${NC}"
        echo -e "  ${YELLOW}Current: $LIVEKIT_KEYS${NC}"
        echo -e "  ${GREEN}Required: \"APIkey: secret\" (note space after colon)${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ LIVEKIT_KEYS not set - will be derived${NC}"
fi

# MAP_STORAGE_AUTHENTICATION_PASSWORD
if [ -z "$MAP_STORAGE_AUTHENTICATION_PASSWORD" ] || [ "$MAP_STORAGE_AUTHENTICATION_PASSWORD" == "CHANGE_ME"* ]; then
    echo -e "${RED}✗ MAP_STORAGE_AUTHENTICATION_PASSWORD not configured${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ MAP_STORAGE_AUTHENTICATION_PASSWORD is set${NC}"
fi

# Check firewall
echo ""
echo "Checking firewall (if accessible)..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null || echo "")
    if echo "$UFW_STATUS" | grep -q "7881.*ALLOW"; then
        echo -e "${GREEN}✓ Port 7881/tcp appears open${NC}"
    else
        echo -e "${YELLOW}⚠ Port 7881/tcp may not be open in UFW${NC}"
        echo "  Run: sudo ufw allow 7881/tcp"
    fi
    
    if echo "$UFW_STATUS" | grep -q "50000:50100.*ALLOW"; then
        echo -e "${GREEN}✓ Ports 50000-50100/udp appear open${NC}"
    else
        echo -e "${YELLOW}⚠ Ports 50000-50100/udp may not be open in UFW${NC}"
        echo "  Run: sudo ufw allow 50000:50100/udp"
    fi
else
    echo -e "${BLUE}ℹ UFW not found - check firewall manually${NC}"
    echo "  Required ports: 7881/tcp, 50000-50100/udp"
fi

# Docker check
echo ""
echo "Checking Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "not running")
    echo -e "${GREEN}✓ Docker version: $DOCKER_VERSION${NC}"
    
    if [[ "$DOCKER_VERSION" =~ ^29\. ]]; then
        echo -e "${YELLOW}⚠ Docker v29 detected - ensure CapRover is v1.14.1+${NC}"
    fi
else
    echo -e "${RED}✗ Docker not found${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo ""
echo "══════════════════════════════════════════════════"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Pre-flight check passed!${NC}"
    echo ""
    echo "Ready to deploy:"
    echo "  CapRover: Upload workadventure-livekit.yml"
    echo "  Docker:   docker-compose up -d"
    exit 0
else
    echo -e "${RED}✗ $ERRORS issue(s) found - fix before deploying${NC}"
    exit 1
fi
