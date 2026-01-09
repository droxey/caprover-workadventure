#!/bin/bash

# ===========================================
# WorkAdventure + LiveKit Diagnostic Script
# ===========================================
# Checks for all known issues and configuration problems
# Run this before and after deployment to verify setup
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKS_PASSED=0

# Helper functions
pass() {
    echo -e "${GREEN}✓ $1${NC}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    ERRORS=$((ERRORS + 1))
}

info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

echo "╔══════════════════════════════════════════════════╗"
echo "║   WorkAdventure + LiveKit Diagnostic Tool        ║"
echo "║   Version: 2.1.0                                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Running comprehensive diagnostics..."

# ===========================================
# SECTION 1: Environment Configuration
# ===========================================
section "1. Environment Configuration"

# Check if .env exists
if [ -f ".env" ]; then
    pass ".env file exists"
    source .env
else
    fail ".env file not found - copy .env.template to .env"
fi

# Check required variables
check_var() {
    local var_name=$1
    local var_value="${!var_name}"
    local description=$2
    
    if [ -z "$var_value" ] || [ "$var_value" == "CHANGE_ME"* ] || [ "$var_value" == "YOUR_"* ]; then
        fail "$var_name not configured ($description)"
    else
        pass "$var_name is set"
    fi
}

check_var "DOMAIN" "Your domain name"
check_var "PUBLIC_IP" "Server public IP for WebRTC"
check_var "SECRET_KEY" "JWT signing key"
check_var "LIVEKIT_API_KEY" "LiveKit API key"
check_var "LIVEKIT_API_SECRET" "LiveKit API secret"

# ===========================================
# SECTION 2: LIVEKIT_KEYS Format (CRITICAL)
# ===========================================
section "2. LiveKit Keys Format (CRITICAL BUG CHECK)"

if [ -n "$LIVEKIT_KEYS" ]; then
    # Check for space after colon
    if [[ "$LIVEKIT_KEYS" =~ ^API[a-f0-9]+:\ .+ ]]; then
        pass "LIVEKIT_KEYS format is correct (space after colon)"
    elif [[ "$LIVEKIT_KEYS" =~ ^API[a-f0-9]+:.+ ]]; then
        fail "LIVEKIT_KEYS missing space after colon!"
        echo -e "    ${YELLOW}Current: LIVEKIT_KEYS=\"$LIVEKIT_KEYS\"${NC}"
        echo -e "    ${GREEN}Should be: LIVEKIT_KEYS=\"${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}\"${NC}"
        echo -e "    ${BLUE}Fix: Re-run ./gen-secrets.sh${NC}"
    else
        fail "LIVEKIT_KEYS format is invalid"
        echo -e "    ${YELLOW}Expected format: \"APIxxxxxxx: secretxxxxxx\"${NC}"
    fi
else
    warn "LIVEKIT_KEYS not set - will be derived from API_KEY and API_SECRET"
fi

# ===========================================
# SECTION 3: Network & Firewall
# ===========================================
section "3. Network & Firewall"

# Check PUBLIC_IP matches actual IP
if [ -n "$PUBLIC_IP" ]; then
    ACTUAL_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || echo "")
    if [ -n "$ACTUAL_IP" ]; then
        if [ "$PUBLIC_IP" == "$ACTUAL_IP" ]; then
            pass "PUBLIC_IP matches actual IP ($ACTUAL_IP)"
        else
            fail "PUBLIC_IP mismatch!"
            echo -e "    ${YELLOW}Configured: $PUBLIC_IP${NC}"
            echo -e "    ${GREEN}Actual: $ACTUAL_IP${NC}"
            echo -e "    ${BLUE}Fix: Update PUBLIC_IP in .env${NC}"
        fi
    else
        warn "Could not determine actual public IP"
    fi
fi

# Check firewall ports
echo ""
info "Checking firewall ports..."

check_port_open() {
    local port=$1
    local proto=$2
    local desc=$3
    
    if command -v ufw &> /dev/null; then
        if ufw status 2>/dev/null | grep -q "$port.*ALLOW"; then
            pass "Port $port/$proto ($desc) is allowed in UFW"
        else
            warn "Port $port/$proto ($desc) may not be open in UFW"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if firewall-cmd --list-ports 2>/dev/null | grep -q "$port/$proto"; then
            pass "Port $port/$proto ($desc) is allowed in firewalld"
        else
            warn "Port $port/$proto ($desc) may not be open in firewalld"
        fi
    else
        info "Cannot check firewall - verify manually: $port/$proto ($desc)"
    fi
}

check_port_open "7881" "tcp" "LiveKit TCP fallback"
check_port_open "50000:50100" "udp" "LiveKit WebRTC UDP"

# Test UDP port connectivity
echo ""
info "Testing LiveKit port connectivity..."
if [ -n "$PUBLIC_IP" ]; then
    if timeout 2 nc -zuv "$PUBLIC_IP" 7881 2>&1 | grep -q "open\|succeeded"; then
        pass "Port 7881/tcp is reachable"
    else
        warn "Port 7881/tcp may not be reachable (test from external host)"
    fi
fi

# ===========================================
# SECTION 4: Docker & CapRover
# ===========================================
section "4. Docker & CapRover"

# Check Docker version
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    info "Docker version: $DOCKER_VERSION"
    
    # Check for Docker v29 breaking change
    if [[ "$DOCKER_VERSION" =~ ^29\. ]]; then
        warn "Docker v29 detected - ensure CapRover is v1.14.1+"
    fi
    pass "Docker is installed"
else
    fail "Docker not found"
fi

# Check CapRover version
CAPROVER_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep "captain-captain" || echo "")
if [ -n "$CAPROVER_CONTAINER" ]; then
    CAPROVER_VERSION=$(docker exec captain-captain cat /usr/src/app/package.json 2>/dev/null | grep '"version"' | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/' || echo "unknown")
    info "CapRover version: $CAPROVER_VERSION"
    
    # Check for v1.14.1+ (required for Docker v29)
    if [[ "$CAPROVER_VERSION" =~ ^1\.([0-9]+)\. ]]; then
        MINOR_VERSION="${BASH_REMATCH[1]}"
        if [ "$MINOR_VERSION" -lt 14 ]; then
            fail "CapRover version too old for Docker v29 - upgrade to 1.14.1+"
        else
            pass "CapRover version is compatible"
        fi
    fi
else
    info "CapRover not detected (standalone deployment)"
fi

# ===========================================
# SECTION 5: Container Status
# ===========================================
section "5. Container Status"

check_container() {
    local pattern=$1
    local name=$2
    
    CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "$pattern" | head -1 || echo "")
    if [ -n "$CONTAINER" ]; then
        STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "none")
        
        if [ "$STATUS" == "running" ]; then
            if [ "$HEALTH" == "healthy" ] || [ "$HEALTH" == "none" ]; then
                pass "$name is running ($CONTAINER)"
            else
                warn "$name is running but unhealthy ($HEALTH)"
            fi
        else
            fail "$name is not running (status: $STATUS)"
        fi
    else
        info "$name container not found"
    fi
}

check_container "workadventure.*play" "Play (Frontend)"
check_container "workadventure.*back" "Back (API)"
check_container "workadventure.*map" "Map Storage"
check_container "workadventure.*livekit" "LiveKit"
check_container "workadventure.*redis" "Redis"
check_container "workadventure.*ejabberd" "Ejabberd"

# ===========================================
# SECTION 6: Service Communication
# ===========================================
section "6. Service Communication"

# Test Redis
REDIS_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "workadventure.*redis|srv-captain.*redis" | head -1 || echo "")
if [ -n "$REDIS_CONTAINER" ]; then
    REDIS_PING=$(docker exec "$REDIS_CONTAINER" redis-cli PING 2>/dev/null || echo "")
    if [ "$REDIS_PING" == "PONG" ]; then
        pass "Redis is responding"
    else
        fail "Redis is not responding"
    fi
fi

# Test LiveKit
LIVEKIT_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "workadventure.*livekit|srv-captain.*livekit" | head -1 || echo "")
if [ -n "$LIVEKIT_CONTAINER" ]; then
    LIVEKIT_HEALTH=$(docker exec "$LIVEKIT_CONTAINER" wget -q --spider http://localhost:7880 2>&1 && echo "ok" || echo "")
    if [ "$LIVEKIT_HEALTH" == "ok" ]; then
        pass "LiveKit API is responding"
    else
        # Try curl as fallback
        LIVEKIT_HEALTH=$(docker exec "$LIVEKIT_CONTAINER" curl -sf http://localhost:7880 2>&1 && echo "ok" || echo "")
        if [ "$LIVEKIT_HEALTH" == "ok" ]; then
            pass "LiveKit API is responding"
        else
            warn "LiveKit API may not be responding (check logs)"
        fi
    fi
fi

# ===========================================
# SECTION 7: Log Analysis
# ===========================================
section "7. Recent Log Analysis"

analyze_logs() {
    local pattern=$1
    local name=$2
    
    CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "$pattern" | head -1 || echo "")
    if [ -n "$CONTAINER" ]; then
        ERROR_COUNT=$(docker logs --tail 100 "$CONTAINER" 2>&1 | grep -ci "error\|exception\|fatal" || echo "0")
        if [ "$ERROR_COUNT" -gt 10 ]; then
            warn "$name has $ERROR_COUNT errors in recent logs"
            echo -e "    ${BLUE}View logs: docker logs --tail 50 $CONTAINER${NC}"
        elif [ "$ERROR_COUNT" -gt 0 ]; then
            info "$name has $ERROR_COUNT errors in recent logs"
        else
            pass "$name logs are clean"
        fi
    fi
}

analyze_logs "workadventure.*play" "Play"
analyze_logs "workadventure.*back" "Back"
analyze_logs "workadventure.*livekit" "LiveKit"

# ===========================================
# SECTION 8: DNS & SSL
# ===========================================
section "8. DNS & SSL"

if [ -n "$DOMAIN" ]; then
    # Check DNS resolution
    DNS_IP=$(host "$DOMAIN" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}' || echo "")
    if [ -n "$DNS_IP" ]; then
        pass "DNS resolves $DOMAIN -> $DNS_IP"
        
        if [ -n "$PUBLIC_IP" ] && [ "$DNS_IP" != "$PUBLIC_IP" ]; then
            warn "DNS IP ($DNS_IP) differs from PUBLIC_IP ($PUBLIC_IP)"
        fi
    else
        fail "DNS not resolving for $DOMAIN"
    fi
    
    # Check SSL certificate
    SSL_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
    if [ -n "$SSL_EXPIRY" ]; then
        pass "SSL certificate valid until: $SSL_EXPIRY"
    else
        warn "Could not verify SSL certificate"
    fi
fi

# ===========================================
# SECTION 9: CapRover Service Names
# ===========================================
section "9. CapRover Service Name Verification"

if [ -n "$CAPROVER_CONTAINER" ]; then
    info "Checking service name prefixing..."
    
    # List all workadventure services
    WA_SERVICES=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "workadventure|srv-captain" | grep -v captain-captain || echo "")
    
    if [ -n "$WA_SERVICES" ]; then
        echo "$WA_SERVICES" | while read -r service; do
            if [[ "$service" =~ ^srv-captain-- ]]; then
                pass "Correct prefix: $service"
            else
                warn "Non-standard name: $service"
            fi
        done
    fi
    
    info "Remember: Inter-service URLs must use srv-captain-- prefix"
fi

# ===========================================
# SECTION 10: Known Bug Checks
# ===========================================
section "10. Known Bug Checks"

# Check WorkAdventure version for known fixes
if [ -n "$VERSION" ]; then
    info "WorkAdventure version: $VERSION"
    
    # v1.27.2 includes audio device fix
    if [[ "$VERSION" =~ ^v1\.27\.[2-9] ]] || [[ "$VERSION" =~ ^v1\.2[8-9] ]] || [[ "$VERSION" =~ ^v[2-9]\. ]]; then
        pass "Version includes audio device change fix"
    else
        warn "Consider upgrading to v1.27.2+ for audio device bug fix"
    fi
fi

# Check LiveKit version
if [ -n "$LIVEKIT_VERSION" ]; then
    info "LiveKit version: $LIVEKIT_VERSION"
fi

# ===========================================
# SUMMARY
# ===========================================
echo ""
echo "══════════════════════════════════════════════════"
echo "                   SUMMARY"
echo "══════════════════════════════════════════════════"
echo ""

echo -e "${GREEN}Checks Passed: $CHECKS_PASSED${NC}"
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
fi
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}Errors: $ERRORS${NC}"
fi

echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ All checks passed! Ready for deployment.     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ Passed with warnings. Review above.          ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ Issues found! Fix errors before deploying.    ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Common fixes:"
    echo "  1. Run ./gen-secrets.sh to regenerate secrets"
    echo "  2. Set PUBLIC_IP to your server's actual IP"
    echo "  3. Open firewall ports 7881/tcp and 50000-50100/udp"
    echo "  4. Upgrade CapRover to v1.14.1+ if using Docker v29"
    exit 1
fi
