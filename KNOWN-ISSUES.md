# Known Issues & Configuration Guide

This document covers known bugs, configuration issues, and workarounds for WorkAdventure + LiveKit deployments on CapRover.

## Table of Contents

- [Critical Issues](#critical-issues)
- [CapRover-Specific Limitations](#caprover-specific-limitations)
- [WorkAdventure Bugs](#workadventure-bugs)
- [LiveKit Issues](#livekit-issues)
- [Configuration Pitfalls](#configuration-pitfalls)
- [Troubleshooting Commands](#troubleshooting-commands)

---

## Critical Issues

### 1. Docker v29 Breaking Change with CapRover

**Impact:** CapRover will fail to start after Docker upgrade to v29+

**Cause:** Docker v29 dropped support for Docker API v1.43 which older CapRover versions use.

**Symptoms:**
```
Error: (HTTP code 400) unexpected - client version 1.43 is too old.
Minimum supported API version is 1.44
```

**Fix:**
```bash
# Upgrade CapRover to 1.14.1+ BEFORE upgrading Docker
docker service update captain-captain --image caprover/caprover:latest

# If already broken, manually upgrade:
docker pull caprover/caprover:latest
docker service update captain-captain --image caprover/caprover:latest --force
```

**Reference:** [CapRover Issue #2351](https://github.com/caprover/caprover/issues/2351)

---

### 2. PUBLIC_IP Must Match Server's Actual IP

**Impact:** WebRTC connections will fail, video/audio won't work

**Symptoms:**
- Video calls connect but no audio/video streams
- LiveKit shows "connection failed" in browser console
- ICE candidates fail

**Diagnosis:**
```bash
# Get your actual public IP
curl -4 ifconfig.me

# Compare with configured value
grep PUBLIC_IP .env
```

**Fix:** Update `PUBLIC_IP` in `.env` to match your server's actual public IP.

---

### 3. LiveKit Firewall Ports

**Impact:** Video calls fail completely or fall back to slow TURN relay

**Required Ports:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 7881 | TCP | WebRTC over TCP fallback |
| 50000-50100 | UDP | WebRTC media streams |

**Fix:**
```bash
# UFW (Ubuntu)
sudo ufw allow 7881/tcp
sudo ufw allow 50000:50100/udp

# AWS Security Group
# Add inbound rules for 7881/tcp and 50000-50100/udp from 0.0.0.0/0
```

---

## CapRover-Specific Limitations

### Fixed in `-fixed.yml` Versions

The original CapRover one-click apps (`workadventure-livekit.yml` and `workadventure-livekit-synapse.yml`) **do not work** because they rely on docker-compose fields that CapRover ignores.

**Use these instead:**
- `workadventure-livekit-fixed.yml`
- `workadventure-livekit-synapse-fixed.yml`

**How the fixes work:**

| Problem | Original | Fixed |
|---------|----------|-------|
| Redis password | `command: redis-server --requirepass X` (ignored) | `bitnami/redis:7.2` with `REDIS_PASSWORD` env var |
| LiveKit config | `command: --redis.address X --rtc.tcp_port Y` (ignored) | `LIVEKIT_CONFIG` env var with embedded YAML |
| Resource limits | `deploy.resources` (ignored) | Removed (use Docker Compose for limits) |
| Health checks | `healthcheck` (ignored) | Removed (manual monitoring required) |

---

### Ignored Docker Compose Fields

**CapRover only supports these docker-compose fields:**
- `image`
- `environment`
- `ports`
- `volumes`
- `depends_on`
- `hostname`

**These fields are SILENTLY IGNORED:**

| Field | Impact |
|-------|--------|
| `healthcheck` | Containers have no health monitoring |
| `deploy` | Resource limits (CPU/memory) don't apply |
| `security_opt` | Security options like `no-new-privileges` ignored |
| `command` | Can't override container entrypoint |
| `entrypoint` | Can't change entrypoint |
| `networks` | Uses `captain-overlay-network` only |
| `restart` | Managed by Docker Swarm, not compose |
| `cap_add` | No capability additions |
| `privileged` | No privileged mode |
| `extra_hosts` | No custom /etc/hosts entries |

**Workaround:** For full docker-compose support, deploy using `docker-compose` directly on the server instead of through CapRover.

**Reference:** [CapRover Docker Compose Docs](https://caprover.com/docs/docker-compose.html)

---

### Service Name Prefixing

**Issue:** CapRover prefixes all service names with `srv-captain--`

**Impact:** Inter-service communication URLs must include the prefix.

**Example:**
```yaml
# WRONG - won't resolve
REDIS_HOST: workadventure-redis

# CORRECT - includes CapRover prefix
REDIS_HOST: srv-captain--workadventure-redis
```

---

## WorkAdventure Bugs

### Audio Device Change Bug (Fixed in v1.27.2+)

**Affected Versions:** < v1.27.2

**Symptoms:** When audio device changes (e.g., AirPods disconnected) while muted in a LiveKit meeting, audio cannot be restarted.

**Fix:** Upgrade to WorkAdventure v1.27.2 or later.

**Reference:** [WorkAdventure PR #5419](https://github.com/workadventure/workadventure/pull/5419)

---

### Audio Cut When Exiting LiveKit (Fixed in v1.27.2+)

**Affected Versions:** < v1.27.2

**Symptoms:** Audio abruptly cuts when leaving a LiveKit zone.

**Fix:** Upgrade to WorkAdventure v1.27.2 or later.

**Reference:** [WorkAdventure PR #5447](https://github.com/workadventure/workadventure/pull/5447)

---

### White Screen on Ubuntu 24.04 After Suspend/Resume

**Status:** In Progress (Draft PR)

**Symptoms:** After laptop suspend/resume on Ubuntu 24.04, the game shows a white screen.

**Cause:** WebGL context loss not handled properly.

**Workaround:** Refresh the browser page after resume.

**Reference:** [WorkAdventure PR #5073](https://github.com/workadventure/workadventure/pull/5073)

---

### Chrome 142+ Localhost Restrictions

**Symptoms:** Map scripting development breaks on localhost.

**Cause:** Chrome 142 introduced restrictions on localhost connections.

**Workaround:** Use a different browser for development, or configure Chrome flags.

**Reference:** [WorkAdventure Releases](https://github.com/workadventure/workadventure/releases)

---

## LiveKit Issues

### LIVEKIT_KEYS Format

**Issue:** LiveKit requires a specific format for API keys.

**Correct Format:**
```bash
# Note the space AFTER the colon
LIVEKIT_KEYS="APIKeyHere: SecretKeyHere"
```

**Wrong Format:**
```bash
# Missing space after colon - WILL FAIL
LIVEKIT_KEYS="APIKeyHere:SecretKeyHere"
```

---

### WebSocket URL Must Use wss://

**Issue:** LIVEKIT_URL must use secure WebSocket protocol.

**Correct:**
```bash
LIVEKIT_URL=wss://livekit.example.com
```

**Wrong:**
```bash
# Insecure - will fail with HTTPS
LIVEKIT_URL=ws://livekit.example.com
```

---

## Configuration Pitfalls

### Default/Weak Secrets

**Issue:** Using default or weak secrets is a security risk.

**Detection:**
```bash
# Check for common weak patterns
grep -E "(changeme|password123|secret123|CHANGE_ME|example)" .env
```

**Fix:** Always generate strong secrets:
```bash
./gen-secrets.sh --auto
# Or manually:
openssl rand -hex 32  # For SECRET_KEY
openssl rand -hex 12  # For LIVEKIT_API_KEY
openssl rand -base64 32  # For LIVEKIT_API_SECRET
```

---

### Missing WebSocket Support in CapRover

**Symptoms:** WebSocket connections fail, character doesn't move.

**Fix:** Enable WebSocket support in CapRover for these apps:
1. CapRover → Apps → `workadventure-play` → HTTP Settings → WebSocket Support: ON
2. CapRover → Apps → `workadventure-livekit` → HTTP Settings → WebSocket Support: ON

---

### HTTPS Not Enabled

**Symptoms:** Mixed content warnings, WebRTC fails.

**Fix:** Enable HTTPS for ALL services:
1. CapRover → Apps → [each app] → Enable HTTPS
2. CapRover → Apps → [each app] → Force HTTPS

---

## Troubleshooting Commands

### Check All Services Running

```bash
# List all WorkAdventure containers
docker ps --filter "name=workadventure" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### View Service Logs

```bash
# Play (frontend) logs
docker logs srv-captain--workadventure-play --tail 100

# Back (API) logs
docker logs srv-captain--workadventure-back --tail 100

# LiveKit logs
docker logs srv-captain--workadventure-livekit --tail 100
```

### Test Redis Connectivity

```bash
# For fixed versions (Bitnami Redis)
docker exec srv-captain--workadventure-redis redis-cli -a YOUR_REDIS_PASSWORD PING
# Should return: PONG

# For docker-compose versions (standard Redis)
docker exec workadventure-redis redis-cli PING
# Should return: PONG
```

### Test LiveKit Health

```bash
# From inside the network
docker exec srv-captain--workadventure-play \
  wget -q -O - http://srv-captain--workadventure-livekit:7880/health
```

### Check Port Connectivity

```bash
# Test LiveKit TCP port
nc -zv YOUR_PUBLIC_IP 7881

# Test LiveKit UDP (requires netcat on target)
nc -zuv YOUR_PUBLIC_IP 50000
```

### Restart All Services

```bash
# Restart all WorkAdventure containers
docker ps --format '{{.Names}}' | grep workadventure | xargs -I {} docker restart {}
```

### Force Update CapRover

```bash
docker service update captain-captain --image caprover/caprover:latest --force
```

---

## Resources

- **WorkAdventure Issues:** https://github.com/workadventure/workadventure/issues
- **WorkAdventure Discord:** https://discord.workadventu.re/
- **LiveKit Issues:** https://github.com/livekit/livekit/issues
- **LiveKit Slack:** https://livekit.io/join-slack
- **CapRover Troubleshooting:** https://caprover.com/docs/troubleshooting.html
- **CapRover Issues:** https://github.com/caprover/caprover/issues

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-09 | 2.1.1 | **Added `-fixed.yml` versions** that work with CapRover (Bitnami Redis, embedded LiveKit config) |
| 2026-01-09 | 2.1.0 | Updated to WA v1.27.2, LiveKit v1.8, added known issues |
| 2026-01-08 | 2.0.0 | Migrated from Jitsi to LiveKit |
