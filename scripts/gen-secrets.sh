#!/bin/bash
# ===========================================
# WorkAdventure Secrets Generator
# ===========================================
# Generates cryptographically secure secrets
# Supports both standard and Synapse versions

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SYNAPSE_MODE=false
if [[ "${1:-}" == "--synapse" ]] || [[ "${1:-}" == "-s" ]]; then
    SYNAPSE_MODE=true
    shift
fi

echo "=========================================="
echo "WorkAdventure Secrets Generator"
if $SYNAPSE_MODE; then
    echo -e "${CYAN}Mode: With Synapse/Matrix${NC}"
else
    echo "Mode: Standard (no Synapse)"
fi
echo "=========================================="
echo ""

# Generate base secrets
SECRET_KEY=$(openssl rand -hex 32)
LIVEKIT_API_KEY=$(openssl rand -hex 12)
LIVEKIT_API_SECRET=$(openssl rand -base64 32 | tr -d '\n')
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
MAP_STORAGE_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')

echo -e "${GREEN}Generated Secrets:${NC}"
echo ""
echo "SECRET_KEY=$SECRET_KEY"
echo "LIVEKIT_API_KEY=$LIVEKIT_API_KEY"
echo "LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET"
echo "REDIS_PASSWORD=$REDIS_PASSWORD"
echo "MAP_STORAGE_PASSWORD=$MAP_STORAGE_PASSWORD"

# Generate Synapse secrets if requested
if $SYNAPSE_MODE; then
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
    MATRIX_ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')
    MATRIX_REGISTRATION_SECRET=$(openssl rand -hex 32)
    
    echo ""
    echo -e "${CYAN}Synapse Secrets:${NC}"
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
    echo "MATRIX_ADMIN_PASSWORD=$MATRIX_ADMIN_PASSWORD"
    echo "MATRIX_REGISTRATION_SECRET=$MATRIX_REGISTRATION_SECRET"
fi

echo ""

# Ask if user wants to create .env
if [[ "${1:-}" == "--auto" ]] || [[ "${1:-}" == "-a" ]]; then
    CREATE_ENV="y"
else
    echo -e "${YELLOW}Create .env file with these secrets? (y/N)${NC}"
    read -r CREATE_ENV
fi

if [[ "$CREATE_ENV" =~ ^[Yy]$ ]]; then
    if [[ -f ".env" ]]; then
        echo -e "${YELLOW}Backing up existing .env to .env.backup${NC}"
        cp .env .env.backup
    fi
    
    # Select appropriate template
    if $SYNAPSE_MODE && [[ -f ".env.synapse.template" ]]; then
        cp .env.synapse.template .env
    elif [[ -f ".env.template" ]]; then
        cp .env.template .env
    else
        # Create minimal .env
        if $SYNAPSE_MODE; then
            cat > .env << EOF
# WorkAdventure + LiveKit + Synapse Configuration
# Generated: $(date -Iseconds)

DOMAIN=example.com
VERSION=v1.21.0

SECRET_KEY=$SECRET_KEY
LIVEKIT_API_KEY=$LIVEKIT_API_KEY
LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

MATRIX_ADMIN_USER=admin
MATRIX_ADMIN_PASSWORD=$MATRIX_ADMIN_PASSWORD
MATRIX_REGISTRATION_SECRET=$MATRIX_REGISTRATION_SECRET

MAP_STORAGE_USER=admin
MAP_STORAGE_PASSWORD=$MAP_STORAGE_PASSWORD

ACME_EMAIL=admin@example.com

MAX_USERS_PER_ROOM=50
ENABLE_ANONYMOUS=true
EOF
        else
            cat > .env << EOF
# WorkAdventure + LiveKit Configuration
# Generated: $(date -Iseconds)

DOMAIN=example.com
VERSION=v1.20.0

SECRET_KEY=$SECRET_KEY
LIVEKIT_API_KEY=$LIVEKIT_API_KEY
LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET
REDIS_PASSWORD=$REDIS_PASSWORD

MAP_STORAGE_USER=admin
MAP_STORAGE_PASSWORD=$MAP_STORAGE_PASSWORD

ACME_EMAIL=admin@example.com

MAX_USERS_PER_ROOM=50
ENABLE_ANONYMOUS=true
EOF
        fi
    fi
    
    # Update secrets in .env
    sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$SECRET_KEY/" .env
    sed -i "s/^LIVEKIT_API_KEY=.*/LIVEKIT_API_KEY=$LIVEKIT_API_KEY/" .env
    sed -i "s/^LIVEKIT_API_SECRET=.*/LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET/" .env
    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$REDIS_PASSWORD/" .env
    sed -i "s/^MAP_STORAGE_PASSWORD=.*/MAP_STORAGE_PASSWORD=$MAP_STORAGE_PASSWORD/" .env
    
    if $SYNAPSE_MODE; then
        sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
        sed -i "s/^MATRIX_ADMIN_PASSWORD=.*/MATRIX_ADMIN_PASSWORD=$MATRIX_ADMIN_PASSWORD/" .env
        sed -i "s/^MATRIX_REGISTRATION_SECRET=.*/MATRIX_REGISTRATION_SECRET=$MATRIX_REGISTRATION_SECRET/" .env
    fi
    
    # Secure permissions
    chmod 600 .env
    
    echo ""
    echo -e "${GREEN}✅ .env created with secure permissions (600)${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Edit .env to set your DOMAIN and ACME_EMAIL${NC}"
fi

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo "1. Edit .env and set DOMAIN and ACME_EMAIL"
echo "2. Run ./scripts/security-check.sh"
if $SYNAPSE_MODE; then
    echo "3. Deploy with: docker compose -f docker-compose.synapse.yaml up -d"
    echo "4. Initialize Synapse admin user (see README)"
else
    echo "3. Deploy with: docker compose -f docker-compose.hardened.yaml up -d"
fi
echo ""
