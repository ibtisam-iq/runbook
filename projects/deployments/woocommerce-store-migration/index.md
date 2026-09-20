# Enterprise WooCommerce Containerization & Migration: High-Performance Multi-Container Stack [MariaDB 10.11, Redis 7, PHP 8.2 Apache, WP-CLI]

## Overview

This project documents the end-to-end containerization, optimization, and migration of an active, production-grade e-commerce storefront—[Peeksleek](https://peeksleek.com), a luxury 100% Mulberry silk bedding brand—off legacy shared cPanel hosting (Namecheap) and onto a modern, isolated container architecture.

While cloud-hosted e-commerce sites frequently suffer from unpredictable performance degradation, silent database lockouts, and opaque server configurations, migrating an active WooCommerce installation requires addressing tight database-to-filesystem couplings, serialized metadata, dynamic URL bindings, and complex page-builder compilation caches.

!!! info "Infrastructure Target & Validation Platform"
    All architecture, container orchestration, and troubleshooting workflows documented in this runbook were designed, implemented, and validated on my custom [SilverStack Dev Machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) on iximiuz Labs (4 vCPUs, 10 GB RAM, 100 GB NVMe). The containerized topology is fully declarative and engineered to boot reproducibly on any Linux playground, bare-metal server, or AWS EC2 instance in under 60 seconds.

---

## The Problem: Shared cPanel Architecture Bottlenecks

Prior to migration, the live store ran on standard Namecheap shared cPanel hosting. Operating WooCommerce on shared hosting introduced critical infrastructure liabilities:

1. **Table-Level Database Locking (`MyISAM` Storage Engine):**
   Key WooCommerce tables were locked into MySQL MyISAM engine formats. Under concurrent traffic, write operations (e.g., cart updates, checkout sessions, inventory decrements) locked entire database tables, serializing incoming read requests and causing checkout timeouts.
2. **Severe Memory & Concurrency Limits:**
   PHP runtime memory was throttled to 128 MB with restrictive connection caps, leading to silent memory exhaustion during heavy page builder rendering and catalog queries.
3. **Absence of Dedicated Object Caching:**
   Without an in-memory caching daemon (Redis/Memcached), every visitor request forced repeated, expensive SQL round-trips to disk for transients, options, and cart metadata.
4. **Configuration Drift & Opaque State:**
   Modifications made via cPanel GUIs left no audit trail, making infrastructure version control and automated disaster recovery impossible.

---

## The Target Architecture: High-Performance Docker Stack

To solve these constraints, I engineered an isolated, production-tuned multi-tier container stack:

* **Relational Database Tier (`peeksleek_db`):** MariaDB 10.11 with a dedicated **4 GB InnoDB buffer pool** (`--innodb_buffer_pool_size=4G`), multi-core threading (`max_connections=300`), 512 MB log file sizes, and UTF-8 MB4 multilingual support. All tables operate with ACID-compliant, lock-free row-level concurrency.
* **In-Memory Caching Tier (`peeksleek_redis`):** Redis 7 on Alpine Linux allocated with a dedicated **1 GB RAM cache** (`--maxmemory 1024mb`), `allkeys-lru` eviction policy, and append-only persistence (`--appendonly yes`) for sub-millisecond object cache resolution.
* **Application Runtime Tier (`peeksleek_app`):** Hardened WordPress container on PHP 8.2 Apache, paired with a custom Zend OPcache configuration, 1024 MB script memory allocation, and declarative reverse-proxy host resolution.
* **Automated Bootstrap Layer:** 1-command startup orchestration that extracts assets, mounts the database dump, reconciles table prefixes, executes domain search-replace, and recompiles Elementor CSS templates without manual intervention.

---

## Runbook Structure

| Document | Focus & Scope |
| :--- | :--- |
| **[Architecture & Design](./architecture-and-design.md)** | Network topology, container resource allocations, MariaDB buffer tuning, and healthcheck dependency chains. |
| **[Database & Asset Extraction](./database-and-asset-extraction.md)** | Sanitized export of production MySQL databases and selective archiving of `wp-content` without runtime bloat. |
| **[Declarative Docker Stack](./declarative-docker-stack.md)** | Complete Infrastructure as Code: `docker-compose.yml`, `.env`, `custom-php/php-custom.ini`, and container entrypoints. |
| **[Troubleshooting & Lessons Learned](./troubleshooting-and-lessons-learned.md)** | Deep-dive post-mortem of 7 critical hurdles: prefix mismatches, version gates, reverse-proxy headers, variable escaping, and Elementor CSS compilation. |
| **[Automated Runbook](./automated-runbook.md)** | The 1-command automated bootstrap script (`bootstrap.sh`) for spinning up on fresh ephemeral playgrounds or production cloud servers. |
