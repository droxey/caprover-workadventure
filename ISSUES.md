# Troubleshooting Guide

Detailed solutions for common issues with WorkAdventure + LiveKit on CapRover.

---

## Table of Contents

1. [Video/Audio Issues](#videoaudio-issues)
2. [Connection Issues](#connection-issues)
3. [CapRover Issues](#caprover-issues)
4. [LiveKit Issues](#livekit-issues)
5. [Map Editor Issues](#map-editor-issues)
6. [Performance Issues](#performance-issues)
7. [SSL/HTTPS Issues](#sslhttps-issues)
8. [Docker Issues](#docker-issues)

---

## Video/Audio Issues

### Video calls not working

**Symptoms:**
- Video bubble appears but no video/audio
- "Connecting..." stays indefinitely
- WebRTC errors in browser console

**Diagnosis:**
```bash
# 1. Check LiveKit container
docker logs srv-captain--workadventure-livekit --tail 50

# 2. Check firewall ports
sudo ufw status | grep -E "7881|50000"

# 3. Test UDP connectivity (from another machine)
nc -zuv YOUR_PUBLIC_IP 50000

# 4. Verify PUBLIC_IP
curl -4 ifconfig.me
grep PUBLIC_IP .env
```

**Solutions:**

1. **Open firewall ports:**
   ```bash
   sudo ufw allow 7881/tcp
   sudo ufw allow 50000:50100/udp
   sudo ufw reload
   ```

2. **Fix PUBLIC_IP mismatch:**
   ```bash
   # Get actual IP
   ACTUAL_IP=$(curl -4 ifconfig.me)
   
   # Update .env
   sed -i "s/PUBLIC_IP=.*/PUBLIC_IP=$ACTUAL_IP/" .env
   
   # Restart LiveKit
   docker restart srv-captain--workadventure-livekit
   ```

3. **Fix LIVEKIT_KEYS format:**
   ```bash
   # Check current format
   grep LIVEKIT_KEYS .env
   
   # Must have space after colon:
   # LIVEKIT_KEYS="APIkey: secret"
   
   # Regenerate if wrong
   ./gen-secrets.sh
   ```

### Audio device change breaks audio

**Symptoms:**
- Switched headphones/speakers while muted
- Cannot unmute or hear others afterward

**Solution:**
- Upgrade to WorkAdventure v1.27.2+ (included by default)
- Refresh the browser page

### Echo or feedback

**Solutions:**
1. Use headphones (recommended)
2. Reduce `MAX_PER_GROUP` to limit participants
3. Enable browser echo cancellation

### No microphone/camera access

**Checklist:**
- [ ] HTTPS is enabled (required for WebRTC)
- [ ] Browser permissions granted
- [ ] Not blocked by corporate firewall
- [ ] Try incognito mode
- [ ] Clear browser cache

---

## Connection Issues

### WebSocket connection failed

**Symptoms:**
- "WebSocket connection failed" in console
- Character doesn't move
- Infinite loading

**Solutions:**

1. **Add WebSocket headers to CapRover nginx:**
   
   Go to Apps → workadventure → HTTP Settings → Edit Default Nginx Configurations:
   
   ```nginx
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   proxy_read_timeout 86400s;
   proxy_send_timeout 86400s;
   ```

2. **Verify HTTPS is enabled:**
   - CapRover → Apps → workadventure → Enable HTTPS
   - Force HTTPS redirect

3. **Check container status:**
   ```bash
   docker ps | grep workadventure
   docker logs srv-captain--workadventure-play --tail 50
   ```

### Cannot access WorkAdventure at all

**Diagnosis:**
```bash
# 1. Check DNS
host workadventure.yourdomain.com

# 2. Check containers
docker ps | grep workadventure

# 3. Check CapRover app status
# Visit CapRover dashboard

# 4. View logs
docker logs srv-captain--workadventure-play --tail 100
```

**Solutions:**
1. Verify DNS points to your server
2. Restart containers: `docker restart srv-captain--workadventure-play`
3. Check CapRover app is deployed

### Timeout errors

**Diagnosis:**
```bash
# Check server resources
htop
docker stats

# Check Redis
docker exec srv-captain--workadventure-redis redis-cli PING
```

**Solutions:**
1. Increase server RAM (4GB+ recommended)
2. Restart Redis: `docker restart srv-captain--workadventure-redis`
3. Clear Redis cache:
   ```bash
   docker exec srv-captain--workadventure-redis redis-cli FLUSHALL
   ```

---

## CapRover Issues

### Docker v29 Breaking Change (CRITICAL)

**Symptoms:**
- CapRover dashboard inaccessible
- Captain container keeps restarting
- Error: "client version 1.43 is too old"

**Solution:**
```bash
# Check Docker version
docker version

# If Docker v29+ and CapRover < 1.14.1:
# Option 1: Upgrade CapRover (recommended)
docker service update captain-captain --image caprover/caprover:1.14.1

# Option 2: Downgrade Docker (temporary)
# Not recommended for production
```

### CapRover docker-compose limitations

**What's NOT supported:**
- `command` / `entrypoint`
- `healthcheck`
- `cap_add` / `privileged`
- `networks` (custom)
- `restart`

**Workaround:** The included `workadventure-livekit.yml` is designed to work within these constraints.

### Service name prefixing

**Issue:** Internal URLs don't work because services aren't prefixed.

**Fix:** All inter-service URLs must use `srv-captain--` prefix:

```bash
# ✅ Correct
REDIS_HOST=srv-captain--workadventure-redis
MAP_STORAGE_URL=http://srv-captain--workadventure-map:3000

# ❌ Wrong
REDIS_HOST=workadventure-redis
MAP_STORAGE_URL=http://map-storage:3000
```

---

## LiveKit Issues

### LiveKit container won't start

**Diagnosis:**
```bash
docker logs srv-captain--workadventure-livekit --tail 100
```

**Common causes:**

1. **Invalid LIVEKIT_KEYS format:**
   ```bash
   # Check format (must have space after colon)
   grep LIVEKIT_KEYS .env
   
   # Should be: "APIkey: secret"
   # NOT: "APIkey:secret"
   ```

2. **Port conflict:**
   ```bash
   # Check if ports are in use
   netstat -tulpn | grep -E "7880|7881"
   ```

3. **Invalid livekit.yaml:**
   ```bash
   # Verify YAML syntax
   cat livekit.yaml | python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)"
   ```

### LiveKit WebSocket not connecting

**Diagnosis:**
```bash
# Test from browser console
new WebSocket('wss://workadventure-livekit.yourdomain.com').onopen = () => console.log('Connected!')
```

**Solutions:**
1. Verify HTTPS is enabled on LiveKit app in CapRover
2. Check `LIVEKIT_URL` starts with `wss://`
3. Verify DNS resolves correctly

---

## Map Editor Issues

### Cannot access map editor

**Diagnosis:**
```bash
docker ps | grep map
docker logs srv-captain--workadventure-map --tail 50
```

**Solutions:**

1. **Check credentials in .env:**
   ```bash
   grep MAP_STORAGE .env
   ```

2. **Verify URL:**
   - `https://workadventure.yourdomain.com/map-storage/`

3. **Check container is running:**
   ```bash
   docker restart srv-captain--workadventure-map
   ```

### Maps not loading

**Diagnosis:**
```bash
# Check map storage volume
docker exec srv-captain--workadventure-map ls -la /maps

# Check PUBLIC_MAP_STORAGE_URL
grep PUBLIC_MAP_STORAGE_URL .env
```

**Solutions:**
1. Ensure `PUBLIC_MAP_STORAGE_URL` matches your domain
2. Check browser console for CORS errors
3. Verify volume permissions

### Cannot save maps

```bash
# Check volume permissions
docker exec srv-captain--workadventure-map ls -la /maps

# Check disk space
df -h
```

---

## Performance Issues

### High CPU usage

**Diagnosis:**
```bash
docker stats
htop
```

**Solutions:**
1. Increase server resources
2. Set resource limits in docker-compose
3. Use external LiveKit for 50+ video users

### High memory usage

```bash
# Identify culprit
docker stats --no-stream

# Clear Redis cache
docker exec srv-captain--workadventure-redis redis-cli FLUSHALL

# Restart services
docker restart srv-captain--workadventure-play
```

### Slow loading

1. Check network latency: `ping yourdomain.com`
2. Enable nginx compression
3. Consider CDN for static assets

---

## SSL/HTTPS Issues

### Certificate errors

**Solutions:**

1. **Re-enable HTTPS in CapRover:**
   - Disable HTTPS on app
   - Wait 30 seconds
   - Re-enable HTTPS

2. **Check DNS:**
   ```bash
   host workadventure.yourdomain.com
   ```

3. **Verify certificate:**
   ```bash
   openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
   ```

### Mixed content warnings

**Check all URLs use HTTPS:**
```bash
grep -E "URL|url" .env | grep -v "https://"
```

**Required format:**
- `LIVEKIT_URL=wss://...` (not `ws://`)
- `FRONT_URL=https://...`
- `PUBLIC_MAP_STORAGE_URL=https://...`

---

## Docker Issues

### Containers keep restarting

**Diagnosis:**
```bash
# Check logs
docker logs srv-captain--workadventure-play --tail 100

# Check for OOM
dmesg | grep -i "killed process"
```

**Solutions:**
1. Increase memory limits
2. Add swap space
3. Check for configuration errors in logs

### Cannot pull images

```bash
# Test Docker Hub
docker pull hello-world

# Check disk space
df -h
docker system df

# Clean up
docker system prune -a
```

### Volume permission issues

```bash
# Check ownership
docker exec srv-captain--workadventure-map ls -la /maps

# Fix permissions
docker exec srv-captain--workadventure-map chown -R 1000:1000 /maps
```

---

## Getting Help

1. **Run diagnostics:**
   ```bash
   ./scripts/diagnostic.sh
   ```

2. **Check GitHub Issues:**
   - [WorkAdventure](https://github.com/workadventure/workadventure/issues)
   - [LiveKit](https://github.com/livekit/livekit/issues)
   - [CapRover](https://github.com/caprover/caprover/issues)

3. **Community:**
   - [WorkAdventure Discord](https://discord.workadventu.re/)
   - [LiveKit Slack](https://livekit.io/join-slack)
