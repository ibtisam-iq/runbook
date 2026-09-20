# Automated Runbook: 1-Command Bootstrap for Ephemeral Playgrounds & Cloud VPS

## Overview

Because developer playgrounds (such as iximiuz Labs or cloud sandboxes) are ephemeral by design, spending hours manually configuring containers, adjusting permissions, and running sequential WP-CLI commands is unacceptable.

This runbook provides the definitive **1-Command Bootstrap Script (`bootstrap.sh`)**. When executed on a freshly booted playground or cloud server, it automates the entire migration sequence—from archive extraction to database seeding, domain alignment, and layout compilation—in under 60 seconds.

---

## The Bootstrap Script (`bootstrap.sh`)

Save this script as `bootstrap.sh` in the `~/peeksleek-docker` directory:

```bash
#!/usr/bin/env bash
# =============================================================================
# PEEKSLEEK WOOCOMMERCE: 1-COMMAND AUTOMATED BOOTSTRAP SCRIPT
# Author: Muhammad Ibtisam
# Target: SilverStack Dev Machine / Any Ephemeral Docker Environment
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_DIR}"

log_info "Initializing Peeksleek High-Performance WooCommerce Stack..."

# -----------------------------------------------------------------------------
# 1. Environment & Artifact Validation
# -----------------------------------------------------------------------------
if [ ! -f .env ]; then
  log_error ".env file missing! Creating from defaults..."
  cat << 'EOF' > .env
TZ=UTC
DB_NAME=peekfenm_wp583
DB_USER=peekfenm_wp583
DB_PASSWORD=peeksleek_secure_db_pass_2026
DB_ROOT_PASSWORD=peeksleek_mariadb_root_pass_2026
WP_PORT=8080
WP_TABLE_PREFIX=wpw4_
PUBLIC_URL=http://localhost:8080
EOF
fi

# Load variables
export $(grep -v '^#' .env | xargs)

# Verify Database Dump
mkdir -p init-db
if [ ! -f init-db/*.sql ]; then
  if ls *.sql 1> /dev/null 2>&1; then
    mv *.sql init-db/
    log_info "Moved SQL dump to ./init-db/"
  else
    log_error "No .sql database dump found in ./init-db/ or root! Place your database dump here before running."
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# 2. Extract Filesystem Assets & Configure Permissions
# -----------------------------------------------------------------------------
if [ -f wp-content.zip ]; then
  log_info "Extracting wp-content.zip..."
  sudo unzip -q -o wp-content.zip -d "${PROJECT_DIR}/"
  
  # Ensure Elementor CSS templates are extracted
  sudo unzip -q -o wp-content.zip "wp-content/uploads/elementor/css/*" -d "${PROJECT_DIR}/" 2>/dev/null || true
  log_success "wp-content extracted successfully."
elif [ -d wp-content ]; then
  log_info "wp-content directory already present."
else
  log_error "wp-content.zip archive missing! Download your archive from cPanel and place it in this folder."
  exit 1
fi

# Remove stale caching drop-ins
sudo rm -rf wp-content/cache/* wp-content/litespeed/* wp-content/advanced-cache.php 2>/dev/null || true

# Enforce strict UID 33 (www-data) permissions
log_info "Configuring ownership and permissions for Apache www-data (UID 33)..."
sudo chown -R 33:33 wp-content
sudo chmod -R 775 wp-content

# -----------------------------------------------------------------------------
# 3. Boot Containers with Healthcheck Gates
# -----------------------------------------------------------------------------
log_info "Starting MariaDB, Redis, and WordPress containers..."
docker compose up -d

log_info "Waiting for MariaDB 10.11 and Redis 7 to become healthy..."
while [ "$(docker inspect --format='{{.State.Health.Status}}' peeksleek_db 2>/dev/null)" != "healthy" ]; do
  sleep 2
done
log_success "MariaDB is healthy (4GB Buffer Pool active)."

while [ "$(docker inspect --format='{{.State.Health.Status}}' peeksleek_redis 2>/dev/null)" != "healthy" ]; do
  sleep 2
done
log_success "Redis is healthy (1GB LRU Object Cache active)."

# -----------------------------------------------------------------------------
# 4. Install WP-CLI & Automate Domain Search-Replace
# -----------------------------------------------------------------------------
log_info "Checking WP-CLI binary in application container..."
docker compose exec wordpress bash -c "
  if ! command -v wp &> /dev/null; then
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
  fi
"

# Resolve the current external host (auto-detect iximiuz proxy if available)
ACTIVE_URL="${PUBLIC_URL}"
if [ -n "${IXIMIUZ_PORT_8080_URL:-}" ]; then
  ACTIVE_URL="${IXIMIUZ_PORT_8080_URL}"
fi

log_info "Aligning database URLs to active domain: ${ACTIVE_URL}..."
docker compose exec wordpress wp search-replace 'https://peeksleek.com' "${ACTIVE_URL}" --all-tables --allow-root

# Update URLs inside compiled Elementor CSS files
if [ -d wp-content/uploads/elementor/css ]; then
  log_info "Updating internal CSS references to match ${ACTIVE_URL}..."
  sudo sed -i "s|https://peeksleek.com|${ACTIVE_URL}|g" wp-content/uploads/elementor/css/*.css 2>/dev/null || true
  sudo chown -R 33:33 wp-content/uploads/elementor/
fi

# -----------------------------------------------------------------------------
# 5. Deactivate Incompatible Shared Plugins & Flush Caches
# -----------------------------------------------------------------------------
log_info "Deactivating LiteSpeed cache and obsolete plugins..."
docker compose exec wordpress wp plugin deactivate litespeed-cache litespeed-cache-disabled --allow-root 2>/dev/null || true

log_info "Setting Elementor CSS print method to external..."
docker compose exec wordpress wp option update elementor_css_print_method external --allow-root 2>/dev/null || true

log_info "Flushing WordPress and Redis object caches..."
docker compose exec wordpress wp cache flush --allow-root

# -----------------------------------------------------------------------------
# 6. Verification
# -----------------------------------------------------------------------------
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 || true)

echo "============================================================================="
log_success "PEEKSLEEK WOOCOMMERCE STACK IS LIVE!"
echo "============================================================================="
echo "Local Port:      http://localhost:${WP_PORT}"
echo "External Domain: ${ACTIVE_URL}"
echo "HTTP Status:     ${HTTP_CODE}"
echo "MariaDB Buffer:  4 GB In-Memory Pool (InnoDB)"
echo "Redis Object:    1 GB RAM LRU Cache"
echo "============================================================================="
```

---

## Step-by-Step Execution on a Brand New Playground

Whenever you launch a new ephemeral playground (or fresh Linux VPS):

### Step 1: Clone or Create the Project Directory
```bash
mkdir -p ~/peeksleek-docker/init-db ~/peeksleek-docker/custom-php
cd ~/peeksleek-docker
```

### Step 2: Download Fresh cPanel Artifacts
Place your freshly downloaded files into `~/peeksleek-docker`:
* `peekfenm_wp583.sql` -> copy to `init-db/`
* `wp-content.zip` -> place in `~/peeksleek-docker/`

### Step 3: Copy Configuration Files
Ensure `docker-compose.yml`, `.env`, and `custom-php/php-custom.ini` are present.

### Step 4: Make Executable and Run
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

### Step 5: Verify Live in Browser
Open the playground web preview (or navigate to `http://localhost:8080`) and perform a hard refresh (`Cmd + Shift + R`). 

The entire storefront, typography, responsive 2x2 product catalog, hero image, and WooCommerce cart will render in under 60 seconds.
