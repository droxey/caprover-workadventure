#!/bin/bash
# ===========================================
# Synapse Startup Script for WorkAdventure
# ===========================================
# Initializes configuration on first run

set -e

DATA_DIR="/data"
CONFIG_FILE="$DATA_DIR/homeserver.yaml"
SIGNING_KEY="$DATA_DIR/signing.key"
LOG_CONFIG="$DATA_DIR/log.config"

echo "=== Synapse Startup ==="
echo "Server: ${SYNAPSE_SERVER_NAME}"

# Generate macaroon and form secrets if not set
if [ -z "$MACAROON_SECRET_KEY" ]; then
    export MACAROON_SECRET_KEY=$(openssl rand -hex 32)
fi
if [ -z "$FORM_SECRET" ]; then
    export FORM_SECRET=$(openssl rand -hex 32)
fi

# Create data directories
mkdir -p "$DATA_DIR/media_store"

# Generate signing key if missing
if [ ! -f "$SIGNING_KEY" ]; then
    echo "Generating signing key..."
    python -m synapse.app.homeserver \
        --config-path "$CONFIG_FILE" \
        --generate-keys
fi

# Create log config if missing
if [ ! -f "$LOG_CONFIG" ]; then
    echo "Creating log configuration..."
    cat > "$LOG_CONFIG" << 'LOGEOF'
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
loggers:
  synapse.storage.SQL:
    level: WARNING
  synapse.access.http:
    level: WARNING
root:
  level: INFO
  handlers: [console]
disable_existing_loggers: false
LOGEOF
fi

# Generate homeserver.yaml from environment variables
if [ ! -f "$CONFIG_FILE" ] || [ "$REGENERATE_CONFIG" = "true" ]; then
    echo "Generating homeserver.yaml..."
    
    # Use envsubst for variable substitution
    export MATRIX_DOMAIN="${SYNAPSE_SERVER_NAME}"
    
    cat > "$CONFIG_FILE" << EOF
# Synapse Homeserver Configuration
# Generated: $(date -Iseconds)

server_name: "${SYNAPSE_SERVER_NAME}"
pid_file: /data/homeserver.pid
public_baseurl: "https://${SYNAPSE_SERVER_NAME}/"

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  txn_limit: 10000
  args:
    user: "${POSTGRES_USER}"
    password: "${POSTGRES_PASSWORD}"
    database: "${POSTGRES_DB}"
    host: "${POSTGRES_HOST}"
    port: ${POSTGRES_PORT:-5432}
    cp_min: 5
    cp_max: 10

log_config: "/data/log.config"

media_store_path: /data/media_store
max_upload_size: 50M
max_image_pixels: 32M

url_preview_enabled: true
url_preview_ip_range_blacklist:
  - '127.0.0.0/8'
  - '10.0.0.0/8'
  - '172.16.0.0/12'
  - '192.168.0.0/16'

enable_registration: ${SYNAPSE_ENABLE_REGISTRATION:-false}
registration_shared_secret: "${SYNAPSE_REGISTRATION_SHARED_SECRET}"

enable_metrics: false
enable_room_list_search: true

retention:
  enabled: true
  default_policy:
    min_lifetime: 1d
    max_lifetime: 180d

rc_message:
  per_second: 10
  burst_count: 50

rc_registration:
  per_second: 0.5
  burst_count: 5

rc_login:
  address:
    per_second: 0.5
    burst_count: 5
  account:
    per_second: 0.5
    burst_count: 5

trusted_key_servers:
  - server_name: "matrix.org"

signing_key_path: "/data/signing.key"
report_stats: ${SYNAPSE_REPORT_STATS:-false}

macaroon_secret_key: "${MACAROON_SECRET_KEY}"
form_secret: "${FORM_SECRET}"

suppress_key_server_warning: true
EOF

    echo "Configuration generated."
fi

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
MAX_RETRIES=30
RETRY=0
until PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\q' 2>/dev/null; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge $MAX_RETRIES ]; then
        echo "PostgreSQL not available after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    echo "PostgreSQL not ready (attempt $RETRY/$MAX_RETRIES)..."
    sleep 2
done
echo "PostgreSQL is ready."

# Start Synapse
echo "Starting Synapse..."
exec python -m synapse.app.homeserver \
    --config-path "$CONFIG_FILE" \
    --config-path /data/log.config
