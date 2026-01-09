#!/bin/bash
# ===========================================
# WorkAdventure Security Check Script
# ===========================================
# Run before deployment to verify security

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

print_result() {
    local status=$1
    local message=$2
    case $status in
        PASS) echo -e "${GREEN}[PASS]${NC} $message"; ((PASS++)) ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $message"; ((WARN++)) ;;
        FAIL) echo -e "${RED}[FAIL]${NC} $message"; ((FAIL++)) ;;
    esac
}

echo "=========================================="
echo "WorkAdventure Security Audit"
echo "=========================================="
echo ""

# -------------------------------------------
# 1. Environment File Checks
# -------------------------------------------
echo "--- Environment Configuration ---"

if [[ -f ".env" ]]; then
    print_result PASS ".env file exists"
    
    # Check file permissions
    PERMS=$(stat -c %a .env 2>/dev/null || stat -f %Lp .env 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
        print_result PASS ".env has secure permissions (600)"
    else
        print_result FAIL ".env permissions are $PERMS (should be 600)"
    fi
    
    # Check required variables
    source .env 2>/dev/null || true
    
    if [[ -n "${SECRET_KEY:-}" ]] && [[ ${#SECRET_KEY} -ge 64 ]]; then
        print_result PASS "SECRET_KEY is set (64+ chars)"
    else
        print_result FAIL "SECRET_KEY missing or too short"
    fi
    
    if [[ -n "${REDIS_PASSWORD:-}" ]] && [[ ${#REDIS_PASSWORD} -ge 16 ]]; then
        print_result PASS "REDIS_PASSWORD is set (16+ chars)"
    else
        print_result FAIL "REDIS_PASSWORD missing or too short"
    fi
    
    if [[ -n "${LIVEKIT_API_KEY:-}" ]] && [[ -n "${LIVEKIT_API_SECRET:-}" ]]; then
        print_result PASS "LiveKit credentials are set"
    else
        print_result FAIL "LiveKit credentials missing"
    fi
    
    if [[ -n "${MAP_STORAGE_PASSWORD:-}" ]] && [[ ${#MAP_STORAGE_PASSWORD} -ge 12 ]]; then
        print_result PASS "MAP_STORAGE_PASSWORD is set (12+ chars)"
    else
        print_result FAIL "MAP_STORAGE_PASSWORD missing or too short"
    fi
    
    if [[ "${DEBUG_MODE:-false}" == "false" ]]; then
        print_result PASS "DEBUG_MODE is disabled"
    else
        print_result WARN "DEBUG_MODE is enabled (disable in production)"
    fi
else
    print_result FAIL ".env file not found"
fi

echo ""

# -------------------------------------------
# 2. Docker Configuration Checks
# -------------------------------------------
echo "--- Docker Security ---"

if command -v docker &> /dev/null; then
    print_result PASS "Docker is installed"
    
    # Check Docker version
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    if [[ "$DOCKER_VERSION" != "unknown" ]]; then
        print_result PASS "Docker version: $DOCKER_VERSION"
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_result WARN "Running as root (consider rootless Docker)"
    else
        print_result PASS "Not running as root"
    fi
    
    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        SOCK_PERMS=$(stat -c %a /var/run/docker.sock 2>/dev/null || stat -f %Lp /var/run/docker.sock 2>/dev/null)
        if [[ "$SOCK_PERMS" == "660" ]] || [[ "$SOCK_PERMS" == "600" ]]; then
            print_result PASS "Docker socket has secure permissions"
        else
            print_result WARN "Docker socket permissions: $SOCK_PERMS"
        fi
    fi
else
    print_result FAIL "Docker not installed"
fi

echo ""

# -------------------------------------------
# 3. Network Security Checks
# -------------------------------------------
echo "--- Network Security ---"

# Check firewall
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
    if [[ "$UFW_STATUS" == *"active"* ]]; then
        print_result PASS "UFW firewall is active"
    else
        print_result WARN "UFW firewall is inactive"
    fi
elif command -v firewall-cmd &> /dev/null; then
    if firewall-cmd --state 2>/dev/null | grep -q "running"; then
        print_result PASS "firewalld is active"
    else
        print_result WARN "firewalld is inactive"
    fi
else
    print_result WARN "No firewall detected (ufw/firewalld)"
fi

# Check required ports
REQUIRED_PORTS=(80 443 7881)
for PORT in "${REQUIRED_PORTS[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
        print_result PASS "Port $PORT is available"
    else
        print_result WARN "Port $PORT not listening"
    fi
done

echo ""

# -------------------------------------------
# 4. SSL/TLS Checks
# -------------------------------------------
echo "--- SSL/TLS Security ---"

if [[ -d "./letsencrypt" ]]; then
    if [[ -f "./letsencrypt/acme.json" ]]; then
        ACME_PERMS=$(stat -c %a ./letsencrypt/acme.json 2>/dev/null || stat -f %Lp ./letsencrypt/acme.json 2>/dev/null)
        if [[ "$ACME_PERMS" == "600" ]]; then
            print_result PASS "acme.json has secure permissions"
        else
            print_result WARN "acme.json permissions: $ACME_PERMS (should be 600)"
        fi
    else
        print_result WARN "acme.json not found (will be created on first run)"
    fi
else
    print_result WARN "letsencrypt directory not found"
fi

echo ""

# -------------------------------------------
# 5. System Checks
# -------------------------------------------
echo "--- System Security ---"

# Check for security updates
if command -v apt &> /dev/null; then
    UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "security" || echo "0")
    if [[ "$UPDATES" -eq 0 ]]; then
        print_result PASS "No pending security updates"
    else
        print_result WARN "$UPDATES security updates available"
    fi
fi

# Check SSH configuration
if [[ -f "/etc/ssh/sshd_config" ]]; then
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        print_result PASS "SSH root login disabled"
    else
        print_result WARN "SSH root login may be enabled"
    fi
    
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        print_result PASS "SSH password auth disabled"
    else
        print_result WARN "SSH password auth may be enabled"
    fi
fi

# Check fail2ban
if command -v fail2ban-client &> /dev/null; then
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        print_result PASS "fail2ban is running"
    else
        print_result WARN "fail2ban installed but not running"
    fi
else
    print_result WARN "fail2ban not installed"
fi

echo ""

# -------------------------------------------
# Summary
# -------------------------------------------
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC} $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}❌ Security check failed. Fix issues before deploying.${NC}"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Security check passed with warnings.${NC}"
    exit 0
else
    echo -e "${GREEN}✅ All security checks passed!${NC}"
    exit 0
fi
