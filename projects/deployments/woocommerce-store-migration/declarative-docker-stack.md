# Declarative Docker Stack: Production-Grade Infrastructure as Code

## Overview

A robust DevOps deployment must be fully declarative, version-controlled, and self-healing. By leveraging Docker Compose, custom PHP ini overlays, and automated reverse-proxy host resolution, the Peeksleek stack boots identically across local laptops, ephemeral playgrounds, and production cloud nodes.

---

## 1. Environment Configuration (`.env`)

Create `.env` in the project root to decouple credentials and operational ports from the Compose file:

```bash
# =============================================================================
# ENVIRONMENT VARIABLES: PEEKSLEEK DOCKER COMPOSE STACK
# =============================================================================
TZ=UTC

# MariaDB Credentials
DB_NAME=peekfenm_wp583
DB_USER=peekfenm_wp583
DB_PASSWORD=peeksleek_secure_db_pass_2026
DB_ROOT_PASSWORD=peeksleek_mariadb_root_pass_2026

# WordPress Configuration
WP_PORT=8080
WP_TABLE_PREFIX=wpw4_
PUBLIC_URL=http://localhost:8080
```

---

## 2. Docker Compose Specification (`docker-compose.yml`)

The compose file orchestrates all three services, establishes container dependencies via healthchecks, mounts configuration overlays, and declares isolated network namespaces:

```yaml
services:
  # -------------------------------------------------------------------------
  # 1. DATABASE: MariaDB 10.11 (4GB Buffer Pool, Multi-Core Threading)
  # -------------------------------------------------------------------------
  db:
    image: mariadb:10.11
    container_name: peeksleek_db
    restart: unless-stopped
    command: [
      '--character-set-server=utf8mb4',
      '--collation-server=utf8mb4_unicode_ci',
      '--max_connections=300',
      '--innodb_buffer_pool_size=4G',
      '--innodb_log_file_size=512M',
      '--innodb_flush_log_at_trx_commit=2',
      '--tmp_table_size=256M',
      '--max_heap_table_size=256M',
      '--table_open_cache=4000'
    ]
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
      TZ: ${TZ}
    volumes:
      - db_data:/var/lib/mysql
      - ./init-db:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      timeout: 5s
      retries: 25
      start_period: 15s
    networks:
      - peeksleek_internal
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"

  # -------------------------------------------------------------------------
  # 2. IN-MEMORY CACHE: Redis 7 (1GB RAM Cache)
  # -------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: peeksleek_redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "1024mb", "--maxmemory-policy", "allkeys-lru"]
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - peeksleek_internal
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # -------------------------------------------------------------------------
  # 3. APPLICATION: WordPress 6.8+ / PHP 8.2 Apache
  # -------------------------------------------------------------------------
  wordpress:
    image: wordpress:php8.2-apache
    container_name: peeksleek_app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "${WP_PORT}:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
      WORDPRESS_TABLE_PREFIX: ${WP_TABLE_PREFIX}
      
      # -----------------------------------------------------------------------
      # REVERSE PROXY HOST & SSL DETECTION (iximiuz / Cloudflare / AWS)
      # Notice: PHP variables must be escaped with double-$$ for Compose!
      # -----------------------------------------------------------------------
      WORDPRESS_CONFIG_EXTRA: |
        $$_SERVER['HTTPS'] = 'on';

        // Check HTTP_X_FORWARDED_HOST first, fallback to HTTP_HOST:
        $$real_host = isset($$_SERVER['HTTP_X_FORWARDED_HOST']) ? $$_SERVER['HTTP_X_FORWARDED_HOST'] : (isset($$_SERVER['HTTP_HOST']) ? $$_SERVER['HTTP_HOST'] : 'localhost');

        define('WP_HOME', 'https://' . $$real_host);
        define('WP_SITEURL', 'https://' . $$real_host);

        define('WP_REDIS_HOST', 'redis');
        define('WP_REDIS_PORT', 6379);
        define('WP_MEMORY_LIMIT', '1024M');
        define('WP_MAX_MEMORY_LIMIT', '1024M');

    volumes:
      - ./custom-php/php-custom.ini:/usr/local/etc/php/conf.d/php-custom.ini:ro
      - ./wp-content:/var/www/html/wp-content
    networks:
      - peeksleek_internal
      - peeksleek_edge
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "3"

volumes:
  db_data:
    driver: local
  redis_data:
    driver: local

networks:
  peeksleek_internal:
    driver: bridge
  peeksleek_edge:
    driver: bridge
```

---

## 3. Custom PHP Runtime Configuration (`custom-php/php-custom.ini`)

Create `custom-php/php-custom.ini` to override default PHP restrictions:

```ini
; -----------------------------------------------------------------------------
; Custom PHP-FPM / Apache Configuration for Peeksleek WooCommerce
; -----------------------------------------------------------------------------
memory_limit = 1024M
upload_max_filesize = 256M
post_max_size = 256M
max_execution_time = 300
max_input_vars = 5000

; Zend OPcache High-Performance Tuning
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 32
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
opcache.save_comments = 1
```

---

## 4. Key Architectural Patterns in this Compose File

### Variable Escaping in Compose (`$$`)
In Docker Compose syntax, any token matching `$VAR` is interpreted as an environment variable to be evaluated on the host machine. Because PHP uses `$`, writing `$_SERVER['HTTPS'] = 'on';` results in Docker replacing `$_SERVER` with an empty string, breaking PHP syntax. 

Prefixing with `$$` (e.g., `$$_SERVER`) instructs Compose to output a literal single `$` into the generated `/var/www/html/wp-config.php`.

### Dynamic Host Resolution (`WP_HOME` / `WP_SITEURL`)
Hardcoding a domain like `https://peeksleek.com` or `http://localhost:8080` breaks preview environments behind dynamic ingress routers (such as iximiuz Labs or AWS ALBs). The injection snippet:
1. Checks for `HTTP_X_FORWARDED_HOST` passed by the reverse proxy.
2. Falls back to `HTTP_HOST` if directly accessed.
3. Automatically sets `WP_HOME` and `WP_SITEURL` to match the exact origin domain requested by the user's browser, preventing all cross-origin errors.
