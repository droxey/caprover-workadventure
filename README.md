# WorkAdventure + LiveKit on CapRover

Security-hardened deployment of WorkAdventure virtual office with LiveKit video conferencing. Additional configuration for persistent chat included.

**Current Versions:**

- WorkAdventure: v1.27.2 _(fixes audio device bugs)_
- LiveKit: v1.8

**Two deployment options:**

- **Standard** — LiveKit video only (8 GB RAM)
- **With Synapse** — LiveKit + Matrix persistent chat (12+ GB RAM)

## Table of Contents

- [Quick Start](#quick-start)
- [Deployment Options](#deployment-options)
- [Known Issues](#known-issues)
- [Diagnostics](#diagnostics)
- [Synapse Version (Persistent Chat)](#synapse-version-persistent-chat)
- [Security Features](#security-features)
- [Configuration](#configuration)
- [Maintenance](#maintenance)
- [Files Reference](#files-reference)

## Quick Start

### Standard Version (No Persistent Chat)

```bash
./gen-secrets.sh
# Edit .env with your DOMAIN
docker compose -f docker-compose.yaml up -d
```

### With Synapse (Persistent Chat)

```bash
cp .env.synapse.template .env
./gen-secrets.sh
# Edit .env with your DOMAIN
docker compose -f docker-compose.synapse.yaml up -d
```

---

## Known Issues

⚠️ **Before deploying, review [KNOWN-ISSUES.md](KNOWN-ISSUES.md) for:**

- Docker v29 breaking change with CapRover
- CapRover limitations (ignored docker-compose fields)
- WorkAdventure audio bugs (fixed in v1.27.2)
- LiveKit configuration pitfalls
- Firewall port requirements

---

## Diagnostics

Run the diagnostic script to check your deployment:

```bash
# On your server
bash workadventure-diagnostic.sh
```

This checks:
- Docker and CapRover versions
- All services running
- Firewall ports open
- Configuration validity
- Known bug exposure

---

## Deployment Options

| Version | File | RAM | Features |
|---------|------|-----|----------|
| Standard | `workadventure-livekit.yml` | 8 GB | Video, maps, rooms |
| Synapse | `workadventure-livekit-synapse.yml` | 12+ GB | + Persistent chat |

### CapRover One-Click

**⚠️ Use the `-fixed.yml` versions!** The original versions use `command` and `deploy` fields that CapRover ignores.

1. Copy appropriate **`.yml`** file contents
2. Go to **Apps → One-Click Apps → Paste YAML**
3. Fill credentials and deploy

### Docker Compose

```bash
# Standard
docker compose -f docker-compose.hardened.yaml up -d

# With Synapse
docker compose -f docker-compose.synapse.yaml up -d
```

## Synapse Version (Persistent Chat)

### What You Get

| Feature | Description |
|---------|-------------|
| **Message History** | Chat persists across sessions |
| **Offline Messages** | Users receive messages when they return |
| **Email Notifications** | Optional SMTP for message alerts |
| **Element App** | Connect from mobile/desktop Matrix clients |
| **Federation** | (Optional) Connect to other Matrix servers |

### Additional Requirements

| Resource | Standard | With Synapse |
|----------|----------|--------------|
| RAM | 8 GB | 12+ GB |
| Storage | 40 GB | 80+ GB |
| Services | 5 | 7 (+PostgreSQL, Synapse) |

### Additional DNS Record

| Subdomain | Target |
|-----------|--------|
| `matrix.example.com` | Your server IP |

### Post-Deployment: Create Admin User

After deployment, create the Matrix admin user:

```bash
# CapRover
docker exec srv-captain--workadventure-synapse \
  register_new_matrix_user -c /data/homeserver.yaml \
  -u admin -p YOUR_PASSWORD -a \
  http://localhost:8008

# Docker Compose
docker exec workadventure-synapse-1 \
  register_new_matrix_user -c /data/homeserver.yaml \
  -u admin -p YOUR_PASSWORD -a \
  http://localhost:8008
```

### Verify Matrix is Working

```bash
# Check federation endpoint
curl -s https://matrix.example.com/_matrix/client/versions

# Expected: {"versions":["r0.0.1",...]}
```

### Connect from Element App

Users can connect to your Matrix server from Element:
1. Download Element (https://element.io)
2. Sign in → Change homeserver
3. Enter: `https://matrix.example.com`
4. Login with WorkAdventure credentials

---

## Security Features

### Container Security

| Feature | Implementation |
|---------|---------------|
| Network Isolation | Internal Docker network |
| Resource Limits | CPU/memory caps per service |
| No-New-Privileges | Prevents privilege escalation |
| Health Checks | Auto-restart unhealthy containers |
| Log Rotation | 10MB max, 3 files |

### Network Security

| Feature | Implementation |
|---------|---------------|
| Rate Limiting | Nginx zones (30/10/2 req/sec) |
| Connection Limits | 50 per IP, 500 per server |
| TLS 1.2+ | Let's Encrypt via Traefik |
| Firewall | UFW with minimal ports |

### Application Security

| Feature | Implementation |
|---------|---------------|
| Redis Auth | Password protected |
| Basic Auth | Map storage protected |
| Secrets | Environment variables |
| JWT | Signed tokens |

### Rate Limiting Details

| Endpoint | Limit | Burst |
|----------|-------|-------|
| General | 30/sec | 50 |
| WebSocket | 10/sec | 30 |
| API | 20/sec | 30 |
| Upload | 2/min | 2 |
| Auth | 5/min | 5 |

---

## Configuration

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `DOMAIN` | Your root domain |
| `SECRET_KEY` | JWT signing key (64 hex chars) |
| `LIVEKIT_API_KEY` | LiveKit API key (24 hex chars) |
| `LIVEKIT_API_SECRET` | LiveKit API secret |
| `REDIS_PASSWORD` | Redis authentication |
| `MAP_STORAGE_PASSWORD` | Map storage basic auth |
| `ACME_EMAIL` | Let's Encrypt email |

### Optional Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION` | v1.20.0 | WorkAdventure version |
| `MAX_USERS_PER_ROOM` | 50 | Room capacity |
| `ENABLE_ANONYMOUS` | true | Allow guest access |

### OIDC Configuration

For SSO integration, add to `.env`:

```bash
ENABLE_OPENID=true
OPENID_CLIENT=workadventure
OPENID_SECRET=your-secret
OPENID_ISSUER=https://auth.example.com/realms/your-realm
```

---

## Maintenance

### Health Check

```bash
./scripts/security-check.sh
```

### Backup

```bash
# Manual backup
./scripts/backup.sh

# Automated daily at 3 AM
echo "0 3 * * * /path/to/scripts/backup.sh" | crontab -
```

### Restore

```bash
./scripts/restore-backup.sh ./backups/workadventure_backup_YYYYMMDD.tar.gz
```

### Update

```bash
# Update VERSION in .env or CapRover config
VERSION=v1.21.0

# Redeploy
docker compose pull
docker compose up -d
```

### Logs

```bash
# All services
docker compose logs -f

# Specific service
docker logs srv-captain--workadventure-play -f

# Search errors
docker logs srv-captain--workadventure-play 2>&1 | grep -i error
```

### Credential Rotation

Rotate secrets every 90 days:

```bash
./scripts/gen-secrets.sh
# Update in CapRover app config
# Trigger redeployment
```

---

## Files Reference

### Deployment Files

| File | Purpose |
|------|---------|
| `workadventure-livekit.yml` | CapRover one-click (broken - for reference only) |
| `workadventure-livekit-synapse.yml` | CapRover one-click (broken - for reference only) |
| `docker-compose.hardened.yaml` | Docker Compose (standard) |
| `docker-compose.synapse.yaml` | Docker Compose (with Matrix) |

### Configuration

| File | Purpose |
|------|---------|
| `.env.template` | Environment template (standard) |
| `.env.synapse.template` | Environment template (with Matrix) |
| `livekit.yaml` | LiveKit server config |
| `synapse/` | Synapse configuration files |
| `nginx/` | Rate limiting configs |
| `fail2ban/` | Brute force protection |

### Scripts

| File | Purpose |
|------|---------|
| `scripts/gen-secrets.sh` | Credential generator |
| `scripts/security-check.sh` | Security audit |
| `scripts/backup.sh` | Backup script |
| `scripts/restore-backup.sh` | Restore script |

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | This file |
| `SERVER-SETUP.md` | Server setup guide |
| `TUNING-50-USERS.md` | Performance tuning |

## License

This deployment configuration is MIT licensed.

- WorkAdventure: AGPL-3.0 with Commons Clause
- LiveKit: Apache-2.0
- CapRover: Apache-2.0
