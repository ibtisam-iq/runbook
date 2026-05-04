# Nexus Repository Manager Rootfs: Artifact Server Image Build and Integration

## Context

Nexus Repository Manager Rootfs is a production-grade Nexus 3 Community Edition image for iximiuz playgrounds. It runs on top of `ubuntu-24-04-rootfs`, booting `lab-init` → `nginx` → `nexus` via systemd, with Nginx on port 80 and `cloudflared` pre-installed for Cloudflare Tunnel custom-domain access.

Nexus uses its own embedded storage under `/opt/sonatype-work` — no external database is required.

> **This image is a microVM rootfs for the [iximiuz Labs](https://labs.iximiuz.com) platform.** The platform mounts it as a block device and boots it with its own kernel. systemd becomes PID 1 through the platform boot process. Do not attempt to validate systemd, service behavior, or Nexus startup via `docker run` — use `labctl` instead (see [Verification](#verification)).

![](../../../assets/screenshots/nexus-server-drive-config.png)

All source artifacts:

| Artifact | Path |
|---|---|
| Dockerfile | [`iximiuz/rootfs/nexus/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/nexus/Dockerfile) |
| Scripts | [`iximiuz/rootfs/nexus/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/nexus/scripts/) |
| Configs | [`iximiuz/rootfs/nexus/configs/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/nexus/configs/) |
| Welcome banner | [`iximiuz/rootfs/nexus/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/nexus/welcome) |
| CI Workflow | [`.github/workflows/build-nexus-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-nexus-rootfs.yml) |
| iximiuz Manifest | [`iximiuz/manifests/nexus-server.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/nexus-server.yml) |

---

## Objectives

Nexus Rootfs must:

- Provide Nexus 3.89.1-02 CE running as the `nexus` system user on top of `ubuntu-24-04-rootfs`.
- Boot in the sequence `lab-init` → `nginx` → `nexus` via systemd, exposing Nexus through Nginx on **port 80** immediately on first boot.
- Configure Nginx as a reverse proxy using build-time port substitution (`__NEXUS_PORT__`), with a `/health` endpoint.
- Write Nexus port and host into `nexus.properties` at build time — no manual configuration needed after first boot.
- Provide `cloudflared` for instant public domain exposure without firewall rules.
- Apply a **limited `sudo` profile** for the `nexus` daemon user — service management and log inspection only.
- Be built reproducibly via GitHub Actions and published as `ghcr.io/ibtisam-iq/nexus-rootfs` with `latest`, `community`, and `3.89.1.02-community` tags.

---

## Architecture / Conceptual Overview

The image inherits the full OS base from `ubuntu-24-04-rootfs` (systemd, SSH, non-root user `ibtisam`, shell config, base tools) and adds a Nexus runtime stack on top:

| Layer | Components |
|---|---|
| Inherited from base | systemd, SSH, user `ibtisam`, bash config, base tools |
| Runtime stack | Java 21 (OpenJDK), Nexus CE 3.89.1 (`nexus` user), Nginx reverse proxy, `cloudflared` |
| Systemd units | `lab-init.service`, `nginx.service` (override), `nexus.service` |
| Security | Limited `sudoers` for `nexus` daemon, no full root |

### Boot Sequence

```
systemd (PID 1)
  └── lab-init.service  [oneshot]
        Generates SSH host keys (ephemeral per VM)
        Creates /run/sshd, /run/nginx
        Fixes /opt/nexus and /opt/sonatype-work ownership
        Creates /opt/sonatype-work/jvm-prefs (JVM user prefs)
          ↓ (Before= constraint respected by systemd)
  └── nginx.service     [simple, daemon off]
        Listens on :80
        Reverse proxies → 127.0.0.1:NEXUS_PORT
          ↓
  └── nexus.service     [simple]
        /opt/nexus/bin/nexus run
        Runs as nexus:nexus
        OOMScoreAdjust=-900 (protected from OOM killer)
        LimitNOFILE=65536, LimitNPROC=8192
```

### Port and Config Substitution

`__NEXUS_PORT__` is a build-time placeholder substituted via `sed` during the Docker build in:

| File | What changes |
|---|---|
| `/etc/nginx/sites-available/nexus` | `upstream nexus { server 127.0.0.1:__NEXUS_PORT__ }` |
| `$HOME/.welcome` | Displayed URL in the welcome banner |

**Additionally**, `install-nexus.sh` writes `nexus.properties` directly with the port value:

```
application-port=8081
application-host=0.0.0.0
nexus-context-path=/
```

This means Nexus is fully configured at build time — no manual port configuration needed at runtime.

---

## Key Decisions

**Nexus is architecture-aware** — `install-nexus.sh` detects the CPU architecture and builds the correct Sonatype download URL. Sonatype uses `linux-aarch_64` (with underscore) for ARM, not `aarch64` — the script handles this explicitly. The CI workflow builds `linux/amd64` only (QEMU intentionally omitted).

**JVM user prefs directory** — The `nexus` system user has no home directory (`--no-create-home`). Without intervention, the JVM attempts to write user preferences to `~/.java` and fails silently. `install-nexus.sh` appends `-Djava.util.prefs.userRoot=/opt/sonatype-work/jvm-prefs` to `nexus.vmoptions`. `lab-init.sh` recreates this directory at every boot and ensures `nexus:nexus` ownership — because `/opt/sonatype-work` permissions may be reset when the microVM mounts it fresh.

**`lab-init.service` runs before SSH, Nginx, and Nexus** — SSH host keys are deleted from the base image (unique per VM; `lab-init.sh` regenerates them via `ssh-keygen -A` at each boot). `/run/sshd` and `/run/nginx` are wiped by `tmpfs` on every reboot. `/opt/nexus` and `/opt/sonatype-work` ownership must be confirmed as `nexus:nexus` at every boot. Without this, all three services would fail to start.

**Nginx as canonical entry point** — All external traffic enters via Nginx on port 80. Nexus only listens on `0.0.0.0:NEXUS_PORT` internally. `client_max_body_size 1G` is set in `nginx.conf` to support large artifact uploads (Maven JARs, Docker layers). Nexus does not have its own reverse-proxy awareness headers in this configuration — the proxy headers (`X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`) are set at the Nginx layer.

**Limited `sudo` for `nexus` daemon** — `configs/sudoers.d/nexus-user` grants the `nexus` system user passwordless access to: `systemctl restart/stop/start/status nexus`, `systemctl reload nginx`, and `journalctl`. No full root. This limits blast radius if Nexus is compromised.

**`USER root` at image end + `CMD ["/lib/systemd/systemd"]`** — Nexus rootfs ends as `USER root`. This is required because `CMD ["/lib/systemd/systemd"]` must start as root. When the iximiuz platform boots the microVM, it runs as root regardless — but the explicit `USER root` + `CMD` makes the intent unambiguous and allows `docker run` to attempt systemd boot (which will fail in a plain container as expected).

**`BUILD_DATE` and `VCS_REF` are not passed as `build-args` in CI** — The workflow does not pass `BUILD_DATE` or `VCS_REF` as explicit `build-args`. The Dockerfile `LABEL` block interpolates these from the ARGs, so the `org.opencontainers.image.created` and `org.opencontainers.image.revision` OCI labels will be empty strings. The `docker/metadata-action` step does inject these into image labels via its own mechanism, but only at the OCI manifest layer — not via ARG substitution in the LABEL block. This is a known gap.

---

## Source Layout

```text
nexus/
├── Dockerfile
├── README.md
├── welcome
├── configs/
│   ├── nginx.conf                      # client_max_body_size 1G; upstream on __NEXUS_PORT__
│   ├── nexus.service                   # Type=simple; /opt/nexus/bin/nexus run as nexus:nexus
│   ├── sudoers.d/
│   │   └── nexus-user                  # Limited sudo: service control + journalctl only
│   └── systemd/
│       └── lab-init.service            # oneshot: Before=ssh,nginx,nexus
└── scripts/
    ├── install-nexus.sh                # Java 21 + Nexus CE 3.89.1 (arch-aware download)
    ├── configure-nginx.sh              # Installs nginx, enables site, systemd override
    ├── lab-init.sh                     # SSH keys + /run dirs + nexus data perms at each boot
    ├── healthcheck.sh                  # Build-time validation (8 sections)
    ├── customize-bashrc.sh             # Nexus/Nginx aliases → ~/.bashrc
    └── install-cloudflared.sh          # Cloudflare Tunnel CLI
```

---

## Build Arguments

| ARG | CI Default | Description |
|---|---|---|
| `USER` | `ibtisam` | Interactive non-root user (inherited from base) |
| `NEXUS_PORT` | `8081` | Nexus HTTP port — substituted in nginx, nexus.properties, welcome |
| `BUILD_DATE` | From CI metadata-action | OCI label: image creation timestamp |
| `VCS_REF` | `github.sha` | OCI label: git commit SHA |

---

## Prerequisites

- `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest` built and published (the `FROM` reference).
- Local checkout of [`github.com/ibtisam-iq/silver-stack`](https://github.com/ibtisam-iq/silver-stack) with `iximiuz/rootfs/nexus/` available.
- Docker Buildx available locally, or a GitHub Actions runner with `docker/setup-buildx-action`.
- Network access to `download.sonatype.com` (Nexus binary), apt (Java, Nginx, cloudflared).
- For CI: `packages: write` permission to push to GHCR via `secrets.GITHUB_TOKEN`.

---

## Build Steps

### 1. Local Build

From `iximiuz/rootfs/nexus/`:

```bash
docker build \
  --build-arg USER="ibtisam" \
  --build-arg NEXUS_PORT=8081 \
  -t ghcr.io/ibtisam-iq/nexus-rootfs:latest \
  .
```

> `BUILD_DATE` and `VCS_REF` are injected by CI. Local builds do not require them.

The Dockerfile performs the following sequence in order:

**Step 1 — Inherit the base**

- `FROM ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`
- `USER root` for all installation steps
- ARGs declared: `USER`, `NEXUS_PORT`, `BUILD_DATE`, `VCS_REF`
- `ENV` sets: `NEXUS_HOME=/opt/nexus`, `NEXUS_DATA=/opt/sonatype-work`, `NEXUS_PORT`, `JAVA_HOME`, `PATH` (Java bin prepended), `TZ=UTC`

**Step 2 — Copy and parameterize configs**

- `COPY configs/nginx.conf /etc/nginx/sites-available/nexus` → `sed` replaces `__NEXUS_PORT__`
- `COPY configs/nexus.service /etc/systemd/system/nexus.service`
- `COPY configs/sudoers.d/nexus-user /etc/sudoers.d/nexus-user`
- `COPY configs/systemd/lab-init.service /etc/systemd/system/lab-init.service`

> Note: Dockerfile does **not** run `sed` on `nexus.service` for port substitution. The port is written directly into `nexus.properties` by `install-nexus.sh` at the next step.

**Step 3 — Copy build-time scripts**

- `COPY scripts/ /opt/nexus-scripts/` + `chmod +x *.sh`

**Step 4 — Install Java 21 + Nexus CE** (`install-nexus.sh ${NEXUS_PORT}`)

- Validates port argument.
- Installs `openjdk-21-jdk` via apt.
- Detects CPU arch (`x86_64` → `linux-x86_64`, `aarch64` → `linux-aarch_64`).
- Downloads `nexus-3.89.1-02-linux-<arch>.tar.gz` from Sonatype CDN.
- Extracts to `/opt/nexus`, removes tarball.
- Creates `nexus` system user (`--system --no-create-home --shell /bin/bash`).
- Sets ownership: `chown -R nexus:nexus /opt/nexus /opt/sonatype-work`, permissions `750`.
- Writes `run_as_user="nexus"` to `/opt/nexus/bin/nexus.rc`.
- Writes `nexus.properties` with `application-port`, `application-host=0.0.0.0`, `nexus-context-path=/`.
- Appends `-Djava.util.prefs.userRoot=/opt/sonatype-work/jvm-prefs` to `nexus.vmoptions`.
- Creates `/opt/sonatype-work/jvm-prefs` and sets `nexus:nexus` ownership.

**Step 5 — Configure Nginx** (`configure-nginx.sh`)

- Installs `nginx` via apt.
- Validates `/etc/nginx/sites-available/nexus` exists (COPY'd in Step 2).
- Removes default Nginx site, enables Nexus site symlink.
- Creates systemd override `/etc/systemd/system/nginx.service.d/override.conf`:
    - `Type=simple`, `ExecStart=/usr/sbin/nginx -g 'daemon off;'`
    - Required for systemd container compatibility.
- Runs `nginx -t` to validate config.

**Step 6 — Enable systemd units**

```bash
systemctl enable lab-init
systemctl enable nginx
systemctl enable nexus
```
Creates symlinks in `/etc/systemd/system/multi-user.target.wants/`. Validated by `healthcheck.sh`.

**Step 7 — Build-time healthcheck** (`healthcheck.sh ${USER}`)

Validates 8 sections without starting services (systemd not running during build):

| Section | What is checked |
|---|---|
| 1. System tools | `curl`, `wget`, `git`, `vim`, `nginx` present |
| 2. Java | `java`, `javac` commands; `JAVA_HOME` set |
| 3. Nexus installation | `/opt/nexus/bin/nexus` present; `nexus.rc` has `run_as_user="nexus"`; `/opt/nexus` owned by `nexus` |
| 4. Nexus port config | `nexus.properties` exists; `application-port=NEXUS_PORT`; nginx upstream port matches |
| 5. Nginx config | Site file present; symlink enabled; default removed; `nginx -t` passes |
| 6. Systemd units | `lab-init`, `ssh`, `nginx`, `nexus` symlinks in `multi-user.target.wants/` |
| 7. SSH config | `sshd_config` and `sshd` binary present; host keys absent (expected — generated at boot) |
| 8. Users | Interactive `$USER` account; `sudoers.d/nexus-user` present |

**Step 8 — Install cloudflared** (`install-cloudflared.sh`)

- Adds Cloudflare apt repository and GPG key.
- Installs `cloudflared`.

**Step 9 — Fix ownership**

- `chown -R ${USER}:${USER} /home/${USER}`

**Step 10 — User customizations**

- `USER $USER` + `ENV HOME=/home/$USER`
- `COPY welcome $HOME/.welcome` → `sed -i` replaces `__NEXUS_PORT__`
- `customize-bashrc.sh` (bind mount) appends to `~/.bashrc`:
    - `nexus-status`, `nexus-logs`, `nexus-restart`, `nexus-start`, `nexus-stop`
    - `nginx-status`, `nginx-logs`, `nginx-reload`
    - Standard `ll`, `la`, `l` aliases

**Step 11 — Return to root + CMD**

- `USER root` — required for `CMD ["/lib/systemd/systemd"]`.
- `EXPOSE 22 80 ${NEXUS_PORT}`
- `CMD ["/lib/systemd/systemd"]`

---

### 2. Build and Push via GitHub Actions

Canonical build: [`.github/workflows/build-nexus-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-nexus-rootfs.yml)

**Triggers:**

- `push` to `main` when files under `iximiuz/rootfs/nexus/**` (excluding `README.md`) or the workflow file change.
- Pull requests with the same path filters.
- Manual `workflow_dispatch`.

**Key steps:**

1. Checkout repository.
2. Set up Docker Buildx (no QEMU — amd64 only, intentional).
3. Log in to GHCR via `secrets.GITHUB_TOKEN`.
4. Extract metadata via `docker/metadata-action`:
    - Tags: `latest`, `community`, `3.89.1.02-community` (on default branch), `sha-<short>`, `YYYY-MM-DD`
    - Labels include `org.opencontainers.image.base.name=ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`
5. `docker/build-push-action` with:
    - `context: ./iximiuz/rootfs/nexus`
    - `platforms: linux/amd64`
    - `push: true` (non-PR only)
    - `build-args: USER=ibtisam`, `NEXUS_PORT=8081`
    - GHA layer cache enabled.
6. Print final image digest.

> **Known gap:** `BUILD_DATE` and `VCS_REF` are not passed as explicit `build-args`. The Dockerfile `LABEL` block will produce empty string OCI labels for `created` and `revision`. The `docker/metadata-action` does inject these into the OCI manifest labels at the image layer — but not via Dockerfile ARG interpolation.

---

## Verification

### ✅ Correct: Inspect the Registry Image

```bash
skopeo inspect docker://ghcr.io/ibtisam-iq/nexus-rootfs:latest \
  | jq '{
      name: .Name,
      base: .Labels["org.opencontainers.image.base.name"],
      created: .Labels["org.opencontainers.image.created"],
      documentation: .Labels["org.opencontainers.image.documentation"],
      authors: .Labels["org.opencontainers.image.authors"]
    }'
```

---

### ✅ Correct: Binary and Config Presence Check (`docker run` — limited scope)

Confirms binaries, files, and symlinks are baked in correctly. Does **not** validate runtime behavior (no systemd, no Nexus, no Nginx, no SSH):

```bash
docker run --rm ghcr.io/ibtisam-iq/nexus-rootfs:latest bash -c "
  java -version 2>&1 | head -1
  nginx -v 2>&1
  cloudflared --version

  echo '--- Nexus binary ---'
  ls -lh /opt/nexus/bin/nexus
  grep run_as_user /opt/nexus/bin/nexus.rc

  echo '--- nexus.properties ---'
  cat /opt/sonatype-work/nexus3/etc/nexus.properties

  echo '--- Nginx upstream port ---'
  grep proxy_pass /etc/nginx/sites-available/nexus

  echo '--- Systemd unit symlinks ---'
  ls /etc/systemd/system/multi-user.target.wants/ | grep -E 'lab-init|nginx|nexus'

  echo '--- JVM prefs vmoption ---'
  grep jvm-prefs /opt/nexus/bin/nexus.vmoptions

  echo '--- Welcome banner ---'
  cat /home/ibtisam/.welcome
"
```

> Errors like `System has not been booted with systemd as init system` are **expected and correct** — not a bug.

---

### ✅ Correct: Full Runtime Verification (iximiuz microVM)

The only valid way to verify the full stack (systemd, Nexus, Nginx, SSH) is to boot in an iximiuz microVM:

```bash
# Step 1 — ensure labctl is authenticated
labctl auth whoami

# Step 2 — download the manifest
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/iximiuz/manifests/nexus-server.yml \
  -o nexus-server.yml

# Step 3 — create the playground
labctl playground create --base flexbox nexus-server -f nexus-server.yml
```

Once the VM is running, connect via the terminal tab or `labctl ssh nexus-server`:

```bash
# --- System health ---
systemctl is-system-running           # Expected: running
systemctl status lab-init             # Expected: inactive (exited) — oneshot complete
systemctl status nginx                # Expected: active (running)
systemctl status nexus                # Expected: active (running)
systemctl status ssh                  # Expected: active (running)

# --- Nexus accessible via Nginx ---
curl -s -o /dev/null -w "%{http_code}" http://localhost:80/
# Expected: 200 (Nexus UI loaded through Nginx)

curl -s http://localhost:80/health
# Expected: healthy

# --- Initial admin password (first login only) ---
cat /opt/sonatype-work/nexus3/admin.password

# --- Aliases available ---
alias | grep nexus-
alias | grep nginx-
```

---

### ❌ Not Valid: `docker run` for systemd or service checks

```
System has not been booted with systemd as init system (PID 1). Can't operate.
```

This is **expected and correct** — not a bug. The image is purpose-built for microVM boot, not Docker container runtime. Use the iximiuz microVM for all service-level verification.

> Nexus takes **60–90 seconds** to fully initialize on first boot. `systemctl status nexus` may show `activating` during this period — this is normal. Wait for the `Started` log line in `nexus-logs` before testing the UI.

---

## Integration with iximiuz Labs

### Prerequisites

Before proceeding, ensure the following are in place on the machine from which you will run `labctl` commands:

1. **`labctl` is installed**
   ```bash
   # macOS
   brew install iximiuz/tools/labctl

   # Linux
   curl -sfL https://raw.githubusercontent.com/iximiuz/labctl/main/install.sh | sh
   ```
2. **`labctl` is authenticated**
   ```bash
   labctl auth login
   # Follow the one-time browser URL to complete authentication
   ```
   Verify the session:
   ```bash
   labctl auth whoami
   ```

---

### Step 1 - Create the playground

Download the manifest directly without cloning the full repository:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/iximiuz/manifests/nexus-server.yml \
  -o nexus-server.yml
```

The manifest declares a single machine `nexus-server` whose root drive is mounted directly from the published GHCR image:

```yaml
drives:
  - source: oci://ghcr.io/ibtisam-iq/nexus-rootfs:latest
    mount: /
    size: 50GiB
```

The manifest can be edited before running - for example, to adjust `cpuCount`, `ramSize`, or `size` to match account quota or preferences.

Run `labctl playground create` pointing at the local manifest:

```bash
labctl playground create --base flexbox nexus-server -f nexus-server.yml
```

When the command succeeds, `labctl` prints the playground URL and its unique ID:

```
Creating playground from /path/to/<MANIFEST_FILENAME>
Playground URL: https://labs.iximiuz.com/playgrounds/nexus-server-<unique-id>
nexus-server-<unique-id>
```

> **Note:** The playground does **not** appear under **Playgrounds → Running**.
> Custom playgrounds created via `labctl` appear under **Playgrounds → My Custom**.

---

### Step 2 - Open the playground

Click the URL printed by `labctl`, or navigate manually:

1. Open [labs.iximiuz.com/dashboard](https://labs.iximiuz.com/dashboard).
2. In the dashboard navigation bar, click **Playgrounds**.
3. Under Playgrounds, click the **My Custom** tab.
4. Locate the playground by the `title` set in the manifest file
   (e.g., `SilverStack Nexus Server`). If the manifest title was
   customized before running, look for that name instead.
5. The playground card shows a **Start** button and a three-dot menu (⋮).

To start immediately, click **Start**.

To review or adjust settings before starting, click ⋮ → **Configure**. This opens the Playground Settings page where machine drives, resources, network, and UI tabs can be inspected before launch.

![](../../../assets/screenshots/silverstack-nexus-server-playground.png)

---

### Step 3 - Verify the running playground

Once started, the welcome banner is displayed automatically and shows the configured internal
ports, service status commands, and next steps.

Follow the instructions in the welcome file for post-setup tasks.

![](../../../assets/screenshots/nexus-server-welcome.png)

---

## Cloudflare Tunnel Configuration

To expose the service on a custom public domain, `cloudflared` is already installed in the image. The welcome page includes step-by-step instructions for configuring and connecting the tunnel. Follow those instructions on first login.

If any issues arise during Cloudflare Tunnel setup, refer to phase 4 in the following runbook:

> 📖 [self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs.md](../../../self-hosted/ci-cd/iximiuz/self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs.md#phase-4-implementation---creating-cloudflare-tunnels)

---

## Related

- [Nexus README](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/nexus/README.md)
- [Nexus Dockerfile](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/nexus/Dockerfile)
- [Nexus scripts](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/nexus/scripts)
- [Nexus configs](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/nexus/configs)
- [Ubuntu base rootfs README](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/README.md)
- [Nexus workflow](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-nexus-rootfs.yml)
- [Nexus manifest](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/nexus-server.yml)
- [Jenkins Rootfs runbook](https://runbook.ibtisam-iq.com/containers/iximiuz/rootfs/setup-jenkins-rootfs-image/)
- [SonarQube Rootfs runbook](https://runbook.ibtisam-iq.com/containers/iximiuz/rootfs/setup-sonarqube-rootfs-image/)
- [Dev Machine runbook](https://runbook.ibtisam-iq.com/containers/iximiuz/rootfs/setup-dev-machine-rootfs-image/)
