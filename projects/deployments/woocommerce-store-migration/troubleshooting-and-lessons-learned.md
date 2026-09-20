# Troubleshooting & Lessons Learned: The 7 Critical Gotchas of WooCommerce Containerization

## Overview

Containerizing an existing, heavily customized production WooCommerce site is not a simple `docker compose up` affair. It exposes subtle architectural traps across database storage engines, dynamic host headers, reverse proxy SSL termination, PHP variable interpolation, and page builder asset compilation.

During the migration of the Peeksleek storefront on the SilverStack Dev Machine, we isolated and resolved **seven critical production failure modes**. This post-mortem documents each hurdle, the diagnostic commands used to expose the root cause, and the definitive engineering fix.

---

## Gotcha 1: The Table Prefix Mismatch (`wpw4_` vs `wp_`)

### Symptom
On initial boot, WordPress ignored the MariaDB database seed and repeatedly redirected to the default installation wizard (`/wp-admin/install.php`), despite `peekfenm_wp583.sql` being successfully imported.

### Root Cause
Shared hosting automated installers (such as Softaculous on cPanel) randomize table prefixes for security obfuscation (e.g., `wpw4_users`, `wpw4_options`, `wpw4_posts`). The standard WordPress Docker image defaults to `wp_`. Because WordPress could not find `wp_options`, it assumed the database was uninitialized.

### Diagnostic Command
```bash
docker compose exec db mariadb -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" -e "SHOW TABLES LIKE '%options';"
```
*Output proved tables were named `wpw4_options`, not `wp_options`.*

### Definitive Solution
Declare `WORDPRESS_TABLE_PREFIX` explicitly in `.env` and `docker-compose.yml`:
```yaml
environment:
  WORDPRESS_TABLE_PREFIX: ${WP_TABLE_PREFIX} # wpw4_
```

---

## Gotcha 2: WordPress Core Version Compatibility Gate

### Symptom
The storefront loaded raw text and fonts, but layout grids, columns, and product cards were completely unstyled and stacked vertically. Running WP-CLI eval reported:
```
Fatal error: Uncaught Error: Class "Elementor\Plugin" not found
```
Inspecting the filesystem revealed `/wp-content/uploads/elementor/css/` was completely empty.

### Root Cause
Inspecting `wp-content/plugins/elementor/elementor.php` revealed:
```php
* Version: 4.2.4
* Requires at least: 6.8
```
The Docker image was running `wordpress:6.7-php8.2-apache` (WordPress 6.7.2). WordPress core contains a strict safety compatibility gate: **if a plugin requires a higher WordPress version than the current installation, WordPress silently skips loading the plugin into memory**. 

Because Elementor was blocked from initializing by core, it never executed its layout compilation engine.

### Diagnostic Command
```bash
# Check plugin requirements
head -n 20 wp-content/plugins/elementor/elementor.php | grep -i "Requires at least"

# Check active core version
docker compose exec wordpress wp core version --allow-root
```

### Definitive Solution
1. Update WordPress core to version 6.8+ (or 7.1):
```bash
docker compose exec wordpress wp core update --allow-root
```
2. Update `docker-compose.yml` to use `wordpress:php8.2-apache` or `wordpress:latest` rather than pinning to legacy `6.7`.

---

## Gotcha 3: Reverse Proxy SSL & Dynamic Host Header Mismatches

### Symptom
When accessing the store through the public preview URL (`https://6aa686b...iximiuz.com`), assets failed to load with `net::ERR_CONNECTION_REFUSED https://localhost:8080/wp-content/...`.

### Root Cause
The edge proxy (iximiuz microVM ingress) terminates SSL and connects to the container port via HTTP. WordPress relies on `$_SERVER['HTTP_HOST']` to generate stylesheet and script URLs. 

When reverse proxies forward requests without rewriting `Host`, or when `HTTP_X_FORWARDED_HOST` is ignored, WordPress hardcodes internal URLs (`localhost:8080`) into `<link>` tags. When the user visits the page on their laptop, the browser attempts to fetch CSS from the user'''s local machine, causing connection drops.

### Diagnostic Command
```bash
# Inspect rendered stylesheet links
curl -s http://localhost:8080 | tr '''<''' '''\n''' | grep -i '''stylesheet''' | head -n 5
```

### Definitive Solution
Inject dynamic proxy detection into `wp-config.php` via `WORDPRESS_CONFIG_EXTRA`:
```php
$_SERVER['HTTPS'] = 'on';

// Check HTTP_X_FORWARDED_HOST first, fallback to HTTP_HOST:
$real_host = isset($_SERVER['HTTP_X_FORWARDED_HOST']) ? $_SERVER['HTTP_X_FORWARDED_HOST'] : (isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'localhost');

define('WP_HOME', 'https://' . $real_host);
define('WP_SITEURL', 'https://' . $real_host);
```

---

## Gotcha 4: Docker Compose PHP Variable Escaping (`$$`)

### Symptom
After adding reverse-proxy detection to `docker-compose.yml`, the WordPress container crashed with `500 Internal Server Error` or syntax errors in `wp-config.php`.

### Root Cause
Docker Compose treats any token beginning with `$` as a Compose environment variable. When passing PHP code containing `$_SERVER` inside `WORDPRESS_CONFIG_EXTRA`, Compose evaluated `$_SERVER` on the host, resolved it to an empty string, and wrote invalid PHP syntax (`['HTTPS'] = 'on';`).

### Diagnostic Command
```bash
docker compose exec wordpress head -n 30 /var/www/html/wp-config.php
```

### Definitive Solution
Escape all PHP variable sigils with double dollar signs (`$$`) in `docker-compose.yml`:
```yaml
      WORDPRESS_CONFIG_EXTRA: |
        $$_SERVER['HTTPS'] = 'on';
        $$real_host = isset($$_SERVER['HTTP_X_FORWARDED_HOST']) ? $$_SERVER['HTTP_X_FORWARDED_HOST'] : ...
```

---

## Gotcha 5: Elementor Static CSS Compilation vs Missing Files

### Symptom
Chrome DevTools Network tab showed 41 out of 46 stylesheets returning `200 OK`, but 5 template files failed with `404 Not Found`:
```http
GET .../uploads/elementor/css/post-1703.css  [404 Not Found] (Homepage Layout & Hero Image)
GET .../uploads/elementor/css/post-128.css   [404 Not Found] (Header Template)
GET .../uploads/elementor/css/post-183.css   [404 Not Found] (Footer Template)
GET .../uploads/elementor/css/post-13.css    [404 Not Found] (Global Kit)
GET .../uploads/elementor/css/post-2284.css  [404 Not Found] (Container Flexbox)
```

### Root Cause
Elementor generates static CSS files when pages are saved in the WordPress admin. Wiping `/wp-content/uploads/elementor/css/*` deletes those files. Because Elementor does not automatically compile CSS on unauthenticated frontend read requests, the browser receives 404s.

Additionally, background images (such as the woman hugging the silk pillowcase) are compiled directly into `post-1703.css`. Without this file, the background is empty.

### Diagnostic Command (via Chrome DevTools MCP)
```bash
# Filter network requests for stylesheets
list_network_requests(resourceTypes: ["stylesheet"])
```

### Definitive Solution
1. Restore compiled CSS templates from the original `wp-content.zip`:
```bash
sudo unzip -o wp-content.zip "wp-content/uploads/elementor/css/*" -d .
```
2. Replace hardcoded production URLs inside the CSS files with the active domain:
```bash
sudo sed -i "s|https://peeksleek.com|https://${ACTIVE_DOMAIN}|g" wp-content/uploads/elementor/css/*.css
```
3. Set ownership to `www-data`:
```bash
sudo chown -R 33:33 wp-content/uploads/elementor/
```

---

## Gotcha 6: Stale LiteSpeed Cache Engine on Apache

### Symptom
HTML pages included LiteSpeed optimization scripts (`<script data-no-optimize="1">var litespeed_docref=...`) and combined scripts with `type="litespeed/javascript"`, breaking JavaScript execution on Apache.

### Root Cause
Namecheap shared hosting uses the proprietary LiteSpeed Web Server. When migrating to an Apache container, the `litespeed-cache` plugin remains active and attempts to call LiteSpeed server APIs that do not exist in Apache.

Renaming the plugin directory to `litespeed-cache-disabled` does not deactivate it in WordPress—WordPress still detects the plugin inside the subfolder.

### Diagnostic Command
```bash
docker compose exec wordpress wp plugin list --allow-root | grep -i litespeed
```

### Definitive Solution
Deactivate the plugin cleanly via WP-CLI and purge all leftover drop-ins:
```bash
docker compose exec wordpress wp plugin deactivate litespeed-cache litespeed-cache-disabled --allow-root
rm -f wp-content/advanced-cache.php
```

---

## Gotcha 7: Host Permission Conflicts on Docker Bind Mounts

### Symptom
Running `unzip` or file editing commands on the host machine failed with:
```
error: cannot create wp-content/uploads/elementor/css/post-1703.css: Permission denied
```

### Root Cause
Inside the Apache container, files are owned by `www-data` (UID 33, GID 33). On the host Linux machine, the non-root user `ibtisam` (UID 1000) lacks write permissions to directories created by the container or owned by UID 33.

### Definitive Solution
Always execute host-side archive extraction and batch updates with `sudo`, followed by a standardized permission alignment:
```bash
sudo chown -R 33:33 ~/peeksleek-docker/wp-content
sudo chmod -R 775 ~/peeksleek-docker/wp-content
```
