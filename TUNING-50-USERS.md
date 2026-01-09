# Performance Tuning for 50 Concurrent Users

Optimization guide for running WorkAdventure + LiveKit with 50 simultaneous users.

## Table of Contents

- [Hardware Requirements](#hardware-requirements)
- [Kernel Tuning](#kernel-tuning)
- [Docker Optimization](#docker-optimization)
- [LiveKit Tuning](#livekit-tuning)
- [Redis Optimization](#redis-optimization)
- [Network Optimization](#network-optimization)
- [Monitoring](#monitoring)

---

## Hardware Requirements

### Recommended Specifications

| Users | CPU | RAM | Bandwidth | Storage |
|-------|-----|-----|-----------|---------|
| 1-25 | 2 vCPU | 4 GB | 100 Mbps | 40 GB SSD |
| 25-50 | 4 vCPU | 8 GB | 200 Mbps | 80 GB SSD |
| 50-100 | 8 vCPU | 16 GB | 500 Mbps | 120 GB SSD |
| 100+ | Dedicated LiveKit cluster | | | |

### Resource Allocation per Service

| Service | CPU | Memory | Notes |
|---------|-----|--------|-------|
| play | 1.0 | 512 MB | Main application |
| back | 1.0 | 512 MB | API server |
| livekit | 2.0 | 1 GB | Video processing |
| redis | 0.5 | 256 MB | Session store |
| map-storage | 0.5 | 256 MB | Map serving |
| traefik | 0.5 | 256 MB | Reverse proxy |

**Total minimum:** 5.5 vCPU, 2.8 GB RAM (plus system overhead)

---

## Kernel Tuning

### Network Buffers

Large network buffers are critical for WebRTC performance:

```bash
# /etc/sysctl.d/99-workadventure.conf

# Increase socket buffer sizes (for video streams)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216

# TCP buffer auto-tuning
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# UDP buffers for WebRTC media
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
```

### Connection Handling

```bash
# Maximum connection queue
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Port range for outbound connections
net.ipv4.ip_local_port_range = 1024 65535
```

### TCP Optimization

```bash
# Enable TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Reuse TIME_WAIT connections
net.ipv4.tcp_tw_reuse = 1

# Faster timeout
net.ipv4.tcp_fin_timeout = 15

# Keep-alive settings
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# BBR congestion control (better for video)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

### File Descriptors

```bash
# System-wide limits
fs.file-max = 2097152
fs.nr_open = 2097152
```

```bash
# /etc/security/limits.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
```

### Apply Settings

```bash
sudo sysctl -p /etc/sysctl.d/99-workadventure.conf
# Reboot for limits.conf changes
```

---

## Docker Optimization

### Daemon Configuration

```json
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
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10
}
```

### Container Resource Limits

Set in `docker-compose.hardened.yaml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 256M
```

### Health Check Tuning

For busy environments, relax health check intervals:

```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:3000/ping"]
  interval: 60s      # Increase from 30s
  timeout: 15s       # Increase from 10s
  retries: 5         # Increase from 3
  start_period: 60s  # Allow more startup time
```

---

## LiveKit Tuning

### Server Configuration

```yaml
# livekit.yaml

rtc:
  # Optimize for 50 users
  port_range_start: 50000
  port_range_end: 50100
  use_external_ip: true

room:
  max_participants: 50
  empty_timeout: 300
  departure_timeout: 30

limit:
  num_tracks: 50
  max_participant_bitrate: 3000000
  subscription_limit_video: 25
  subscription_limit_audio: 100
```

### Bandwidth Calculation

Per user (720p video + audio):
- Video: ~1.5 Mbps up/down
- Audio: ~50 Kbps up/down
- **Total per user:** ~3 Mbps symmetric

**50 users:** ~150 Mbps minimum bandwidth

### CPU Estimation

LiveKit CPU usage per user:
- Encoding/decoding: ~0.1 CPU per stream
- SFU routing: ~0.05 CPU per participant

**50 users with 4 video streams each:**
- ~20 CPU cores ideal
- ~8 CPU minimum (with quality tradeoffs)

### Scaling Beyond 50 Users

For 100+ users, consider:

1. **External LiveKit:** Dedicated LiveKit server
2. **LiveKit Cloud:** Managed service at cloud.livekit.io
3. **LiveKit Cluster:** Multiple servers with load balancing

```bash
# Update environment
LIVEKIT_URL=wss://dedicated-livekit.example.com
```

---

## Redis Optimization

### Configuration

```bash
redis-server \
  --maxmemory 128mb \
  --maxmemory-policy allkeys-lru \
  --appendonly yes \
  --tcp-backlog 511 \
  --timeout 0 \
  --tcp-keepalive 300
```

### Memory Policy

- `allkeys-lru`: Evict least recently used keys when full
- 128MB sufficient for 50 concurrent sessions
- Scale to 256MB for 100+ users

### Persistence

- `appendonly yes`: Enables AOF persistence
- Recovery time: seconds vs minutes with RDB

---

## Network Optimization

### Rate Limiting for 50 Users

```nginx
# nginx/nginx.conf

# General requests
limit_req_zone $binary_remote_addr zone=general:10m rate=30r/s;

# WebSocket (higher for real-time)
limit_req_zone $binary_remote_addr zone=websocket:10m rate=10r/s;

# With burst for 50 users
limit_req zone=general burst=100 nodelay;
limit_req zone=websocket burst=50 nodelay;
```

### Connection Limits

```nginx
# Per IP
limit_conn_zone $binary_remote_addr zone=perip:10m;
limit_conn perip 50;

# Per server
limit_conn_zone $server_name zone=perserver:10m;
limit_conn perserver 1000;
```

### Timeout Settings

```nginx
# For WebSocket connections
proxy_connect_timeout 60s;
proxy_send_timeout 300s;
proxy_read_timeout 300s;
```

---

## Monitoring

### Key Metrics to Watch

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU Usage | >70% | >90% |
| Memory Usage | >80% | >95% |
| Network Out | >80% capacity | >95% |
| WebRTC Failed | >5% | >15% |
| Response Time | >500ms | >2000ms |

### Monitoring Script

```bash
#!/bin/bash
# /usr/local/bin/wa-metrics.sh

echo "=== WorkAdventure Metrics ==="
echo ""

# Container stats
docker stats --no-stream --format \
  "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
  | grep -E "(workadventure|livekit)"

echo ""

# Connection counts
echo "Active Connections:"
ss -s | grep -E "(TCP|UDP)"

echo ""

# LiveKit status
LIVEKIT_ROOMS=$(curl -s http://localhost:7880/debug/rooms 2>/dev/null | jq '. | length' 2>/dev/null || echo "N/A")
echo "LiveKit Active Rooms: $LIVEKIT_ROOMS"
```

### Prometheus Metrics (Optional)

Enable in `.env`:

```bash
PROMETHEUS_AUTHORIZATION_TOKEN=your-secret-token
```

Query metrics at: `https://play.example.com/metrics`

### Log Analysis

```bash
# Count active WebSocket connections
docker logs srv-captain--workadventure-play 2>&1 | \
  grep -c "WebSocket connection established"

# Find slow requests
docker logs srv-captain--workadventure-play 2>&1 | \
  grep -E "took [0-9]{4,}ms"
```

---

## Performance Checklist

Before going live with 50 users:

- [ ] Server meets hardware requirements
- [ ] Kernel parameters applied
- [ ] Docker daemon configured
- [ ] File descriptor limits increased
- [ ] BBR congestion control enabled
- [ ] Rate limits appropriate for load
- [ ] LiveKit configured for user count
- [ ] Redis memory adequate
- [ ] Monitoring in place
- [ ] Load tested with simulated users

### Load Testing

Use [k6](https://k6.io/) or similar:

```javascript
// k6 script for WebSocket testing
import ws from 'k6/ws';

export default function () {
  const url = 'wss://play.example.com/room/test';
  ws.connect(url, {}, function (socket) {
    socket.on('open', () => console.log('connected'));
    socket.on('message', (data) => console.log('Received: ' + data));
    socket.setTimeout(() => socket.close(), 30000);
  });
}
```

```bash
k6 run --vus 50 --duration 5m load-test.js
```
