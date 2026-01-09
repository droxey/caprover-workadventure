# Server Setup Guide for WorkAdventure + LiveKit

Complete Ubuntu 24.04 server configuration for hosting WorkAdventure with LiveKit video conferencing. Optimized for 50 concurrent users.

## Table of Contents

1. [Server Requirements](#server-requirements)
2. [Initial Server Setup](#initial-server-setup)
3. [Docker Installation](#docker-installation)
4. [System Tuning for 50 Users](#system-tuning-for-50-users)
5. [Firewall Configuration](#firewall-configuration)
6. [CapRover Installation](#caprover-installation)
7. [DNS Configuration](#dns-configuration)
8. [Deploy WorkAdventure](#deploy-workadventure)
9. [Security Hardening](#security-hardening)
10. [Monitoring](#monitoring)
11. [Troubleshooting](#troubleshooting)

---

## Server Requirements

### Minimum Specifications

| Component | Standard | With Synapse |
|-----------|----------|--------------|
| CPU | 4 vCPU | 4 vCPU |
| RAM | 8 GB | 12 GB |
| Storage | 40 GB SSD | 80 GB SSD |
| Network | 100 Mbps | 200 Mbps |
| OS | Ubuntu 22.04 | Ubuntu 24.04 |

### Required Ports

| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP |
| 443 | TCP | HTTPS |
| 3000 | TCP | CapRover Dashboard |
| 7880 | TCP | LiveKit Signal |
| 7881 | TCP | LiveKit WebRTC/TCP |
| 50000-50100 | UDP | LiveKit WebRTC Media |

---

## Initial Server Setup

### 1. Update System

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl wget git htop \
    net-tools iotop \
    unzip jq \
    ca-certificates \
    gnupg lsb-release
```

### 2. Set Timezone

```bash
sudo timedatectl set-timezone UTC
```

### 3. Configure Hostname

```bash
sudo hostnamectl set-hostname workadventure
echo "127.0.0.1 workadventure" | sudo tee -a /etc/hosts
```

### 4. Create Non-Root User (if using root)

```bash
adduser workadventure
usermod -aG sudo workadventure
su - workadventure
```

### 5. Configure Swap (for low-RAM servers)

```bash
# Create 4GB swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Optimize swap usage
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Docker Installation

### 1. Install Docker

```bash
# Remove old versions
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker repository
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER

# Start Docker
sudo systemctl enable docker
sudo systemctl start docker
```

### 2. Configure Docker Daemon

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 1048576,
      "Soft": 1048576
    }
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

sudo systemctl restart docker
```

### 3. Verify Installation

```bash
docker version
docker compose version
docker run hello-world
```

---

## System Tuning for 50 Users

### 1. Kernel Parameters

```bash
sudo tee /etc/sysctl.d/99-workadventure.conf << 'EOF'
# Network buffer sizes for WebRTC
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# UDP for WebRTC media
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Connection handling
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535

# TCP optimization
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# File descriptors
fs.file-max = 2097152
fs.nr_open = 2097152

# Connection tracking
net.netfilter.nf_conntrack_max = 262144

# Security
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-workadventure.conf
```

### 2. File Descriptor Limits

```bash
sudo tee -a /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
root soft nofile 1048576
root hard nofile 1048576
EOF
```

### 3. Disable Transparent Huge Pages

```bash
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Make persistent
sudo tee /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable disable-thp
```

### 4. Apply Changes

```bash
sudo reboot
```

---

## Firewall Configuration

### 1. Configure UFW

```bash
# Reset and configure
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH (change 22 to your SSH port if different)
sudo ufw allow 22/tcp comment 'SSH'

# HTTP/HTTPS
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# CapRover (restrict to admin IPs in production)
sudo ufw allow 3000/tcp comment 'CapRover Dashboard'

# LiveKit
sudo ufw allow 7880/tcp comment 'LiveKit Signal'
sudo ufw allow 7881/tcp comment 'LiveKit WebRTC TCP'
sudo ufw allow 50000:50100/udp comment 'LiveKit WebRTC UDP'

# Enable firewall
sudo ufw enable
sudo ufw status verbose
```

### 2. Install Fail2ban

```bash
sudo apt install -y fail2ban

# Copy configuration
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Edit jail.local
sudo tee -a /etc/fail2ban/jail.local << 'EOF'

[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 3600
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status
```

---

## CapRover Installation

### 1. Initialize Docker Swarm

```bash
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
```

### 2. Install CapRover

```bash
docker run -p 80:80 -p 443:443 -p 3000:3000 \
    -e ACCEPTED_TERMS=true \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v captain-data:/captain \
    caprover/caprover
```

### 3. Initial Setup

1. Open `http://YOUR_SERVER_IP:3000`
2. Default password: `captain42`
3. **Change password immediately**
4. Configure your root domain
5. Enable HTTPS with Let's Encrypt

---

## DNS Configuration

### Required DNS Records

Create A records pointing to your server IP:

| Type | Name | Value |
|------|------|-------|
| A | captain.example.com | YOUR_IP |
| A | *.captain.example.com | YOUR_IP |

Or for simpler setup:

| Type | Name | Value |
|------|------|-------|
| A | example.com | YOUR_IP |
| A | *.example.com | YOUR_IP |

### Verify DNS

```bash
dig +short captain.example.com
dig +short play.captain.example.com
```

---

## Deploy WorkAdventure

### 1. Generate Credentials

```bash
echo "SECRET_KEY: $(openssl rand -hex 32)"
echo "LIVEKIT_API_KEY: $(openssl rand -hex 12)"
echo "LIVEKIT_API_SECRET: $(openssl rand -base64 32)"
echo "REDIS_PASSWORD: $(openssl rand -base64 24)"
echo "MAP_STORAGE_PASSWORD: $(openssl rand -base64 16)"
```

**Save these credentials securely.**

### 2. Deploy via CapRover

1. Go to **Apps** → **One-Click Apps**
2. Paste contents of `workadventure-livekit.yml`
3. Fill in your credentials
4. Click **Deploy**

### 3. Post-Deployment Configuration

After deployment:

1. **Enable HTTPS** on all apps:
   - Apps → play → Enable HTTPS → Force HTTPS
   - Apps → map-storage → Enable HTTPS → Force HTTPS
   - Apps → livekit → Enable HTTPS → Force HTTPS

2. **Enable WebSocket** on play and livekit:
   - Apps → [app] → HTTP Settings → WebSocket Support: ON

3. **Verify health**:
   ```bash
   docker ps --filter "name=workadventure" --format "table {{.Names}}\t{{.Status}}"
   ```

---

## Deploy with Synapse (Persistent Chat)

If you need persistent chat history, deploy the Synapse version instead.

### Additional DNS Record

| Type | Name | Value |
|------|------|-------|
| A | matrix.example.com | YOUR_IP |

### Generate Additional Credentials

```bash
# Run with --synapse flag
./scripts/gen-secrets.sh --synapse
```

This generates additional secrets:
- `POSTGRES_PASSWORD` — PostgreSQL database
- `MATRIX_ADMIN_PASSWORD` — Matrix admin account
- `MATRIX_REGISTRATION_SECRET` — User registration

### Deploy via CapRover

1. Use `workadventure-livekit-synapse.yml` instead
2. Fill in ALL credentials (8 required)
3. Wait 5-10 minutes for Synapse to initialize

### Deploy via Docker Compose

```bash
# Copy Synapse template
cp .env.synapse.template .env

# Generate secrets
./scripts/gen-secrets.sh --synapse --auto

# Edit domain
nano .env

# Deploy
docker compose -f docker-compose.synapse.yaml up -d
```

### Initialize Matrix Admin User

After Synapse starts (check logs for "synapse.app.homeserver - Synapse now listening"):

```bash
# CapRover
docker exec srv-captain--workadventure-synapse \
  register_new_matrix_user -c /data/homeserver.yaml \
  -u admin -p YOUR_SECURE_PASSWORD -a \
  http://localhost:8008

# Docker Compose
docker exec workadventure-synapse-1 \
  register_new_matrix_user -c /data/homeserver.yaml \
  -u admin -p YOUR_SECURE_PASSWORD -a \
  http://localhost:8008
```

### Verify Matrix Federation

```bash
# Check Matrix API
curl -s https://matrix.example.com/_matrix/client/versions | jq

# Expected output includes version list
```

### Enable HTTPS for Matrix

Add to post-deployment:
- Apps → synapse → Enable HTTPS → Force HTTPS
- Apps → synapse → HTTP Settings → WebSocket Support: ON

---

## Security Hardening

### 1. SSH Hardening

```bash
sudo tee -a /etc/ssh/sshd_config << 'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sudo systemctl restart sshd
```

### 2. Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 3. SSL/TLS Best Practices

CapRover handles SSL via Let's Encrypt. Verify:

```bash
# Test SSL configuration
curl -vI https://play.example.com 2>&1 | grep -E "(SSL|TLS|certificate)"
```

### 4. Run Security Check

```bash
./scripts/security-check.sh
```

---

## Monitoring

### 1. Basic Monitoring Script

```bash
sudo tee /usr/local/bin/wa-status.sh << 'EOF'
#!/bin/bash
echo "=== WorkAdventure Status ==="
echo ""
echo "--- Container Health ---"
docker ps --filter "name=workadventure" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "--- Resource Usage ---"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep workadventure
echo ""
echo "--- Disk Usage ---"
df -h / | tail -1
echo ""
echo "--- System Load ---"
uptime
EOF

sudo chmod +x /usr/local/bin/wa-status.sh
```

### 2. Log Monitoring

```bash
# View all WorkAdventure logs
docker logs srv-captain--workadventure-play --tail 100 -f

# Search for errors
docker logs srv-captain--workadventure-play 2>&1 | grep -i error
```

### 3. Set Up Cron for Backups

```bash
# Daily backup at 3 AM
echo "0 3 * * * /path/to/scripts/backup.sh >> /var/log/workadventure-backup.log 2>&1" | crontab -
```

---

## Troubleshooting

### Video Calls Not Working

```bash
# Check LiveKit health
curl -v https://livekit.example.com/health

# Check UDP ports are open
sudo ufw status | grep 50000

# Test from external network
nc -vzu YOUR_IP 50000
```

### High Memory Usage

```bash
# Check container memory
docker stats --no-stream | grep workadventure

# Restart services
docker compose restart

# Check for memory leaks in logs
docker logs srv-captain--workadventure-play 2>&1 | grep -i "memory\|heap"
```

### Container Restart Loop

```bash
# Check logs
docker logs srv-captain--workadventure-play --tail 200

# Check health status
docker inspect srv-captain--workadventure-play --format='{{.State.Health.Status}}'

# Force recreation
docker compose down && docker compose up -d
```

### DNS/SSL Issues

```bash
# Verify DNS
dig +short play.example.com

# Check certificate
openssl s_client -connect play.example.com:443 -servername play.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates

# Renew certificates
docker exec srv-captain--captain /app/captain cert renew --force
```

---

## Quick Reference

### Important Paths

| Path | Description |
|------|-------------|
| `/var/lib/docker/volumes/` | Docker volumes |
| `/captain/` | CapRover data |
| `/var/log/` | System logs |

### Common Commands

```bash
# Check status
wa-status.sh

# View logs
docker logs srv-captain--workadventure-play -f

# Restart services
docker compose restart

# Backup
./scripts/backup.sh

# Security check
./scripts/security-check.sh
```

### Port Reference

| Port | Service |
|------|---------|
| 80 | HTTP (redirects to HTTPS) |
| 443 | HTTPS |
| 3000 | CapRover Dashboard |
| 7880 | LiveKit Signal (WSS) |
| 7881 | LiveKit TCP Fallback |
| 50000-50100 | LiveKit UDP Media |
