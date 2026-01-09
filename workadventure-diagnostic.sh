#!/bin/bash

# ============================================================================
# WorkAdventure + LiveKit + CapRover Diagnostic Script
# ============================================================================
# Checks for known bugs, configuration issues, and deployment health
# Run on your CapRover server: bash workadventure-diagnostic.sh
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Counters
CRITICAL=0
WARNINGS=0
PASSED=0
INFO=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC} $1"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    CRITICAL=$((CRITICAL + 1))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    INFO=$((INFO + 1))
}

# ============================================================================
# START DIAGNOSTIC
# ============================================================================

print_header "WorkAdventure + LiveKit + CapRover Diagnostic Tool"
echo ""
echo "  Started: $(date)"
echo "  Hostname: $(hostname)"
echo ""

# ============================================================================
# 1. SYSTEM CHECKS
# ============================================================================
print_section "1. System Environment"

# Check if running as root or with sudo
if [ "$EUID" -eq 0 ]; then
    pass "Running with root privileges"
else
    info "Running as non-root user (some checks may be limited)"
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "Operating System: $PRETTY_NAME"
    
    # Ubuntu 24.04 WebGL bug warning
    if [[ "$VERSION_ID" == "24.04" ]]; then
        warn "Ubuntu 24.04 detected - Known WebGL context loss bug on suspend/resume"
        echo "       See: github.com/workadventure/workadventure/pull/5073"
    fi
else
    warn "Could not detect OS version"
fi

# Check available memory
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
if [ "$TOTAL_MEM" -lt 4000 ]; then
    warn "Low total RAM: ${TOTAL_MEM}MB (4GB+ recommended)"
else
    pass "Total RAM: ${TOTAL_MEM}MB"
fi

if [ "$AVAIL_MEM" -lt 1000 ]; then
    warn "Low available RAM: ${AVAIL_MEM}MB"
else
    pass "Available RAM: ${AVAIL_MEM}MB"
fi

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    fail "Disk usage critical: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -gt 80 ]; then
    warn "Disk usage high: ${DISK_USAGE}%"
else
    pass "Disk usage: ${DISK_USAGE}%"
fi

# ============================================================================
# 2. DOCKER VERSION CHECK (Critical Bug)
# ============================================================================
print_section "2. Docker Version (Critical)"

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    DOCKER_API=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || echo "unknown")
    
    info "Docker Version: $DOCKER_VERSION"
    info "Docker API Version: $DOCKER_API"
    
    # Check for Docker 29+ breaking change
    DOCKER_MAJOR=$(echo "$DOCKER_VERSION" | cut -d. -f1)
    if [ "$DOCKER_MAJOR" -ge 29 ] 2>/dev/null; then
        warn "Docker 29+ detected - Requires CapRover 1.14.1+"
        echo "       Breaking change: Docker API v1.43 no longer supported"
        echo "       See: github.com/caprover/caprover/issues/2351"
    else
        pass "Docker version compatible ($DOCKER_VERSION)"
    fi
else
    fail "Docker not found!"
fi

# ============================================================================
# 3. CAPROVER VERSION CHECK
# ============================================================================
print_section "3. CapRover Version"

CAPROVER_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "captain-captain" | head -1)
if [ -n "$CAPROVER_CONTAINER" ]; then
    pass "CapRover is running"
    
    # Try to get version
    CAPROVER_IMAGE=$(docker inspect "$CAPROVER_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
    info "CapRover image: $CAPROVER_IMAGE"
    
    # Check if it's an old version
    if [[ "$CAPROVER_IMAGE" == *"1.13"* ]] || [[ "$CAPROVER_IMAGE" == *"1.12"* ]] || [[ "$CAPROVER_IMAGE" == *"1.11"* ]]; then
        fail "CapRover version too old - Update to 1.14.1+ immediately!"
        echo "       Run: docker service update captain-captain --image caprover/caprover:latest"
    elif [[ "$CAPROVER_IMAGE" == *"1.14"* ]] || [[ "$CAPROVER_IMAGE" == *"latest"* ]]; then
        pass "CapRover version appears compatible"
    fi
else
    fail "CapRover container not found"
fi

# ============================================================================
# 4. WORKADVENTURE CONTAINERS
# ============================================================================
print_section "4. WorkAdventure Services"

# Define expected services
SERVICES=("play" "back" "map" "redis" "livekit")
FOUND_SERVICES=0

for service in "${SERVICES[@]}"; do
    CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "workadventure.*${service}" | head -1)
    if [ -n "$CONTAINER" ]; then
        # Check container health
        STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        HEALTH=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
        
        if [ "$STATUS" == "running" ]; then
            if [ "$HEALTH" == "unhealthy" ]; then
                warn "$service: running but unhealthy"
            else
                pass "$service: running ($CONTAINER)"
                FOUND_SERVICES=$((FOUND_SERVICES + 1))
            fi
        else
            fail "$service: not running (status: $STATUS)"
        fi
    else
        fail "$service: container not found"
    fi
done

if [ "$FOUND_SERVICES" -lt 4 ]; then
    echo ""
    warn "Some core services missing. Listing all WorkAdventure containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | grep -i workadventure || echo "    No containers found"
fi

# ============================================================================
# 5. LIVEKIT CONFIGURATION
# ============================================================================
print_section "5. LiveKit Configuration"

LIVEKIT_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "workadventure.*livekit" | head -1)

if [ -n "$LIVEKIT_CONTAINER" ]; then
    # Check LiveKit logs for errors
    LIVEKIT_ERRORS=$(docker logs "$LIVEKIT_CONTAINER" --tail 50 2>&1 | grep -ci "error\|failed\|fatal" || echo "0")
    if [ "$LIVEKIT_ERRORS" -gt 5 ]; then
        warn "LiveKit has $LIVEKIT_ERRORS errors in recent logs"
        echo "       Run: docker logs $LIVEKIT_CONTAINER --tail 20"
    else
        pass "LiveKit logs look healthy"
    fi
    
    # Check if LiveKit is listening
    LIVEKIT_PORTS=$(docker port "$LIVEKIT_CONTAINER" 2>/dev/null || echo "none")
    if [ "$LIVEKIT_PORTS" != "none" ]; then
        info "LiveKit ports: $(echo $LIVEKIT_PORTS | tr '\n' ' ')"
    fi
else
    fail "LiveKit container not found"
fi

# ============================================================================
# 6. NETWORK / FIREWALL CHECKS
# ============================================================================
print_section "6. Network & Firewall"

# Get public IP
PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || echo "unknown")
info "Public IP: $PUBLIC_IP"

# Check required ports
echo ""
echo "  Checking required ports..."

# Port 7881 (LiveKit TCP)
if command -v ss &> /dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":7881"; then
        pass "Port 7881/tcp (LiveKit TCP) is listening"
    else
        warn "Port 7881/tcp may not be listening locally"
    fi
fi

# Check UFW if available
if command -v ufw &> /dev/null; then
    echo ""
    echo "  UFW Firewall Status:"
    UFW_STATUS=$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo "unknown")
    
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        info "UFW is inactive (firewall disabled or using other)"
    elif echo "$UFW_STATUS" | grep -q "active"; then
        # Check for required ports
        if echo "$UFW_STATUS" | grep -qE "7881.*ALLOW"; then
            pass "UFW: Port 7881/tcp allowed"
        else
            fail "UFW: Port 7881/tcp not allowed - LiveKit TCP will fail"
            echo "       Fix: sudo ufw allow 7881/tcp"
        fi
        
        if echo "$UFW_STATUS" | grep -qE "50000:50100/udp.*ALLOW"; then
            pass "UFW: Ports 50000-50100/udp allowed"
        else
            fail "UFW: Ports 50000-50100/udp not allowed - LiveKit media will fail"
            echo "       Fix: sudo ufw allow 50000:50100/udp"
        fi
    fi
fi

# ============================================================================
# 7. ENVIRONMENT VARIABLES CHECK
# ============================================================================
print_section "7. Environment Configuration"

# Try to find .env file
ENV_LOCATIONS=(
    "/captain/data/config/workadventure/.env"
    "/srv/captain/workadventure/.env"
    "$HOME/workadventure/.env"
    "./.env"
)

ENV_FILE=""
for loc in "${ENV_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        ENV_FILE="$loc"
        break
    fi
done

if [ -n "$ENV_FILE" ]; then
    info "Found .env file: $ENV_FILE"
    
    # Check critical variables
    if grep -q "^PUBLIC_IP=" "$ENV_FILE" 2>/dev/null; then
        CONFIGURED_IP=$(grep "^PUBLIC_IP=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ "$CONFIGURED_IP" == "$PUBLIC_IP" ]; then
            pass "PUBLIC_IP matches server IP ($PUBLIC_IP)"
        else
            fail "PUBLIC_IP mismatch! Configured: $CONFIGURED_IP, Actual: $PUBLIC_IP"
            echo "       Fix: Update PUBLIC_IP in .env file"
        fi
    else
        warn "PUBLIC_IP not found in .env"
    fi
    
    # Check LIVEKIT_URL format
    if grep -q "^LIVEKIT_URL=" "$ENV_FILE" 2>/dev/null; then
        LIVEKIT_URL=$(grep "^LIVEKIT_URL=" "$ENV_FILE" | cut -d'=' -f2)
        if [[ "$LIVEKIT_URL" == wss://* ]]; then
            pass "LIVEKIT_URL uses secure WebSocket (wss://)"
        elif [[ "$LIVEKIT_URL" == ws://* ]]; then
            fail "LIVEKIT_URL uses insecure WebSocket (ws://) - Must use wss://"
        fi
    fi
    
    # Check LIVEKIT_KEYS format
    if grep -q "LIVEKIT_KEYS\|LIVEKIT_API_KEY" "$ENV_FILE" 2>/dev/null; then
        pass "LiveKit API keys configured"
    else
        fail "LiveKit API keys not found in .env"
    fi
    
    # Check for default/weak secrets
    if grep -qE "(changeme|password123|secret123|CHANGE_ME)" "$ENV_FILE" 2>/dev/null; then
        fail "Default/weak secrets detected in .env!"
        echo "       Run gen-secrets.sh to generate secure values"
    else
        pass "No obvious default secrets detected"
    fi
else
    warn "Could not locate .env file for inspection"
    echo "       Searched: ${ENV_LOCATIONS[*]}"
fi

# ============================================================================
# 8. SERVICE CONNECTIVITY
# ============================================================================
print_section "8. Service Connectivity"

# Check Redis
REDIS_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "workadventure.*redis" | head -1)
if [ -n "$REDIS_CONTAINER" ]; then
    REDIS_PING=$(docker exec "$REDIS_CONTAINER" redis-cli PING 2>/dev/null || echo "FAIL")
    if [ "$REDIS_PING" == "PONG" ]; then
        pass "Redis responding to PING"
    else
        fail "Redis not responding"
    fi
else
    warn "Redis container not found for connectivity test"
fi

# Check Play service HTTP
PLAY_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "workadventure.*play" | head -1)
if [ -n "$PLAY_CONTAINER" ]; then
    # Try to get the internal port
    PLAY_CHECK=$(docker exec "$PLAY_CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$PLAY_CHECK" == "200" ] || [ "$PLAY_CHECK" == "302" ]; then
        pass "Play service responding (HTTP $PLAY_CHECK)"
    elif [ "$PLAY_CHECK" == "000" ]; then
        info "Could not test Play service internally (curl may not be installed)"
    else
        warn "Play service returned HTTP $PLAY_CHECK"
    fi
fi

# ============================================================================
# 9. RECENT LOG ERRORS
# ============================================================================
print_section "9. Recent Log Analysis"

echo "  Checking last 100 lines of each service for errors..."
echo ""

check_service_logs() {
    local pattern=$1
    local name=$2
    
    CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "$pattern" | head -1)
    if [ -n "$CONTAINER" ]; then
        ERROR_COUNT=$(docker logs "$CONTAINER" --tail 100 2>&1 | grep -ciE "error|exception|fatal|panic" || echo "0")
        WARN_COUNT=$(docker logs "$CONTAINER" --tail 100 2>&1 | grep -ciE "warn|warning" || echo "0")
        
        if [ "$ERROR_COUNT" -gt 10 ]; then
            warn "$name: $ERROR_COUNT errors, $WARN_COUNT warnings in last 100 lines"
        elif [ "$ERROR_COUNT" -gt 0 ]; then
            info "$name: $ERROR_COUNT errors, $WARN_COUNT warnings in last 100 lines"
        else
            pass "$name: No errors in recent logs"
        fi
    fi
}

check_service_logs "workadventure.*play" "Play"
check_service_logs "workadventure.*back" "Back"
check_service_logs "workadventure.*map" "Map Storage"
check_service_logs "workadventure.*livekit" "LiveKit"
check_service_logs "workadventure.*redis" "Redis"

# ============================================================================
# 10. KNOWN BUGS CHECK
# ============================================================================
print_section "10. Known Bugs Status"

echo "  Checking for known issues..."
echo ""

# Check WorkAdventure version
PLAY_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "workadventure.*play" | head -1)
if [ -n "$PLAY_CONTAINER" ]; then
    WA_IMAGE=$(docker inspect "$PLAY_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
    info "WorkAdventure image: $WA_IMAGE"
    
    # Check for old versions with known bugs
    if [[ "$WA_IMAGE" == *"1.26"* ]] || [[ "$WA_IMAGE" == *"1.25"* ]]; then
        warn "WorkAdventure version may have audio device change bug"
        echo "       Upgrade to v1.27.2+ for fixes"
    elif [[ "$WA_IMAGE" == *"1.27"* ]] || [[ "$WA_IMAGE" == *"latest"* ]] || [[ "$WA_IMAGE" == *"develop"* ]]; then
        pass "WorkAdventure version includes recent bug fixes"
    fi
fi

# Chrome 142 localhost restriction warning
info "Note: Chrome 142+ has new localhost connection restrictions"
echo "       This affects local map scripting development"
echo "       See: github.com/workadventure/workadventure/releases"

# ============================================================================
# 11. CAPROVER-SPECIFIC CHECKS
# ============================================================================
print_section "11. CapRover-Specific Issues"

echo "  Checking CapRover docker-compose compatibility..."
echo ""

info "CapRover only supports these docker-compose fields:"
echo "       image, environment, ports, volumes, depends_on, hostname"
echo ""
warn "These fields are IGNORED by CapRover (may affect your setup):"
echo "       • cap_add (network capabilities)"
echo "       • privileged"
echo "       • extra_hosts"  
echo "       • healthcheck"
echo "       • custom networks"
echo "       • entrypoint/command overrides"
echo "       • restart policies"
echo ""
info "If you need these features, run docker-compose directly on the server"

# Check service naming
echo ""
echo "  Checking service name prefixes..."
WA_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i workadventure || echo "")
if echo "$WA_CONTAINERS" | grep -q "srv-captain--"; then
    pass "Services correctly prefixed with srv-captain--"
else
    warn "Services may not have correct CapRover prefix"
    echo "       Inter-service communication may fail"
fi

# ============================================================================
# SUMMARY
# ============================================================================
print_header "Diagnostic Summary"

echo ""
echo -e "  ${GREEN}Passed:${NC}    $PASSED"
echo -e "  ${BLUE}Info:${NC}      $INFO"
echo -e "  ${YELLOW}Warnings:${NC}  $WARNINGS"
echo -e "  ${RED}Critical:${NC}  $CRITICAL"
echo ""

if [ "$CRITICAL" -gt 0 ]; then
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  CRITICAL ISSUES FOUND - Address these immediately!          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=1
elif [ "$WARNINGS" -gt 3 ]; then
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  Multiple warnings - Review before going to production       ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=0
else
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓  System looks healthy!                                        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    EXIT_CODE=0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Quick Fix Commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  # Open firewall ports for LiveKit"
echo "  sudo ufw allow 7881/tcp"
echo "  sudo ufw allow 50000:50100/udp"
echo ""
echo "  # View service logs"
echo "  docker logs srv-captain--workadventure-play --tail 50"
echo "  docker logs srv-captain--workadventure-livekit --tail 50"
echo ""
echo "  # Restart all WorkAdventure services"
echo "  docker ps --format '{{.Names}}' | grep workadventure | xargs -I {} docker restart {}"
echo ""
echo "  # Update CapRover (if needed)"
echo "  docker service update captain-captain --image caprover/caprover:latest"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Resources:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  • WorkAdventure Issues: github.com/workadventure/workadventure/issues"
echo "  • LiveKit Issues: github.com/livekit/livekit/issues"
echo "  • CapRover Docs: caprover.com/docs/troubleshooting.html"
echo "  • WorkAdventure Discord: discord.workadventu.re"
echo ""

exit ${EXIT_CODE:-0}
