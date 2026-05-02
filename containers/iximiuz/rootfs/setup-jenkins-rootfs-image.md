# Jenkins LTS Rootfs: CI Server Image Build and Integration

## Context

Jenkins LTS Rootfs is a **production‑grade Jenkins server image for iximiuz playgrounds**.

It boots Jenkins via systemd with Nginx acting as a reverse proxy and `cloudflared` pre‑installed so the instance can be exposed on a custom domain via Cloudflare Tunnel with SSL.

![](../../../assets/screenshots/silverstack-jenkins-server-playground.png)

It is defined under:

- README: [`iximiuz/rootfs/jenkins/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/README.md)
- Dockerfile: [`iximiuz/rootfs/jenkins/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/Dockerfile)
- Scripts: [`iximiuz/rootfs/jenkins/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/scripts)
- Configs: [`iximiuz/rootfs/jenkins/configs/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/configs)
    - Nginx: [`configs/nginx.conf`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/configs/nginx.conf)
    - Jenkins systemd unit: [`configs/jenkins.service`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/configs/jenkins.service)
    - lab-init systemd unit: [`configs/systemd/lab-init.service`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/configs/systemd/lab-init.service)
    - sudoers: [`configs/sudoers.d/jenkins-user`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/configs/sudoers.d/jenkins-user)
- Welcome banner: [`iximiuz/rootfs/jenkins/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/welcome)
- iximiuz manifest: [`iximiuz/manifests/jenkins-server.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/jenkins-server.yml)
- CI workflow: [`.github/workflows/build-jenkins-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-jenkins-rootfs.yml)

The image **does not** bake in pipeline tools or plugins. Instead, it places two **post‑setup scripts on PATH**:

- `install-pipeline-tools` - installs the CI toolchain (Maven, Docker, kubectl, Trivy, AWS CLI, Helm, Terraform, Ansible, etc.).
- `install-plugins` - installs an enterprise‑grade Jenkins plugin bundle via Jenkins CLI and triggers a safe restart.

---

## Objectives

Jenkins LTS Rootfs must:

- Provide a **Jenkins LTS** instance running on top of `ubuntu-24-04-rootfs` with systemd as PID 1.
- Start services in the order: `lab-init` → `nginx` → `jenkins`, making Jenkins available on port 80 via Nginx.
- Configure Nginx as a **reverse proxy** for internal Jenkins HTTP, using build‑time port substitution and a `/health` endpoint.
- Provide a **Cloudflare‑ready** environment via `cloudflared` so Jenkins can be exposed securely on a custom domain.
- Expose **two post‑setup scripts** (`install-pipeline-tools`, `install-plugins`) on `/usr/local/bin` and never run them during build.
- Use a **limited sudo profile** for the `jenkins` user that allows safe service control and log inspection but not full root.
- Be built reproducibly via CI and published as `ghcr.io/ibtisam-iq/jenkins-rootfs` with LTS and `latest` tags.

---

## Architecture / Conceptual Overview

The Jenkins rootfs image:

- Inherits all behavior from the base image `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest` (systemd, SSH, tools, prompt, non‑root user `ibtisam`).
- Adds a **Jenkins runtime stack**:
    - Java 21 (OpenJDK).
    - Jenkins LTS server running as `jenkins` user.
    - Nginx reverse proxy using `configs/nginx.conf`, mapping external port 80 to internal `__JENKINS_PORT__`.
    - `cloudflared` binary for Cloudflare Tunnel integration.

Systemd units:

- `lab-init.service` (`configs/systemd/lab-init.service`) - one‑shot init that runs `/opt/jenkins-scripts/lab-init.sh` before SSH, Nginx, and Jenkins.
- `nginx.service` - from base, enabled in Jenkins image.
- `jenkins.service` (`configs/jenkins.service`) - Type=notify service that runs `/usr/bin/jenkins --httpPort=__JENKINS_PORT__` as `jenkins` user.

Sudo profile for `jenkins`:

- [`configs/sudoers.d/jenkins-user`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/configs/sudoers.d/jenkins-user) allows `jenkins` to restart/stop/start/status Jenkins, reload Nginx, and use `journalctl` via `sudo` without password.

Post‑setup scripts:

- `install-pipeline-tools` - from `scripts/install-pipeline-tools.sh`, installs 10 pipeline tools with pinned versions (notably Trivy pinned to `0.69.3` due to CVE‑2026‑33634).
- `install-plugins` - from `scripts/install-plugins.sh`, uses Jenkins CLI to install plugin bundle.

The login experience is driven by the Jenkins welcome file, which is copied into the user’s home and port‑substituted with `JENKINS_PORT`.

---

## Key Decisions

- **Post‑setup pipeline tools and plugins, not baked in**
  Keeping CI tools and plugins as post‑setup scripts (`install-pipeline-tools`, `install-plugins`) keeps the image lean and allows you to tailor installations per environment.

- **Trivy version pinning for supply chain safety**
  Trivy is pinned to `0.69.3` because `0.69.4` was compromised (CVE‑2026‑33634, exfiltrating secrets via malicious binaries). The README documents this decision with a reference link.

- **Systemd‑first design**
  Jenkins is treated as a real systemd service (`Type=notify`, `OOMScoreAdjust=-900`, explicit limits) rather than a simple process. This aligns the image with production‑style deployments.

- **Nginx as canonical entry point**
  All external traffic goes through Nginx, which normalizes headers, handles caching, exposes `/health`, and is the target for Cloudflare Tunnel HTTP mapping (port 80). Jenkins itself only listens on a local port.

- **Limited sudo for `jenkins`**
  Instead of granting full root, the sudoers entry gives Jenkins just enough power to manage services and view logs via scripts/aliases.

---

## Source Layout and Inputs

From [`iximiuz/rootfs/jenkins/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/README.md):

```text
jenkins/
├── Dockerfile
├── welcome
├── README.md
├── configs/
│   ├── nginx.conf                  # Upstream: 127.0.0.1:__JENKINS_PORT__
│   ├── jenkins.service             # ExecStart: --httpPort=__JENKINS_PORT__
│   ├── sudoers.d/
│   │   └── jenkins-user
│   └── systemd/
│       └── lab-init.service
└── scripts/
    ├── install-jenkins.sh          # Installs Java 21 + Jenkins LTS
    ├── install-pipeline-tools.sh   # Post-setup: installs 10 CI/CD tools (→ /usr/local/bin/)
    ├── install-plugins.sh          # Post-setup: installs Jenkins plugins (→ /usr/local/bin/)
    ├── configure-nginx.sh          # Enables site, systemd override
    ├── lab-init.sh                 # SSH keys + runtime dir setup
    ├── healthcheck.sh              # Build-time validation (8 sections)
    ├── customize-bashrc.sh         # Aliases → ~/.bashrc
    └── install-cloudflared.sh
```

All paths are under:

- Dockerfile: [`iximiuz/rootfs/jenkins/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/Dockerfile)
- Scripts: [`iximiuz/rootfs/jenkins/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/scripts)
- Configs: [`iximiuz/rootfs/jenkins/configs/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/configs)
- Welcome: [`iximiuz/rootfs/jenkins/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/welcome)

---

## Prerequisites

To build Jenkins Rootfs:

- Base image `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest` must already exist and be accessible.
- Local clone of `silver-stack` with the directory
  [`iximiuz/rootfs/jenkins`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins).
- Docker with Buildx if you want multi‑arch builds.
- Network access to fetch Jenkins, Java packages, and any CLI tools used by scripts.
- For CI: permissions to push to GHCR.

---

## Installation / Build Steps

### 1. Local Jenkins Rootfs build

From `iximiuz/rootfs/jenkins`:

```bash
IMAGE_NAME="ghcr.io/ibtisam-iq/jenkins-rootfs:latest"

docker build \
  --build-arg USER="ibtisam" \
  --build-arg JENKINS_PORT="8080" \
  -t "${IMAGE_NAME}" \
  .
```

The Dockerfile
[`iximiuz/rootfs/jenkins/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/Dockerfile)
performs these high‑level steps:

1. **Base and environment**

    - `FROM ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`.
    - `USER root`.
    - Build args: `USER`, `JENKINS_PORT`, `BUILD_DATE`, `VCS_REF`.
    - Labels: `created` and `revision` taken from build args.
    - Environment variables: `JENKINS_HOME`, `JENKINS_PORT`, `JAVA_HOME`, `PATH` extended with Java bin, `TZ=UTC`.

2. **Copy and parameterize configs**

    - Copies `configs/nginx.conf` to `/etc/nginx/sites-available/jenkins` and replaces `__JENKINS_PORT__` using `sed`.
    - Copies `configs/jenkins.service` to `/etc/systemd/system/jenkins.service` and replaces `__JENKINS_PORT__` similarly.
    - Copies `configs/sudoers.d/jenkins-user` into `/etc/sudoers.d/jenkins-user`.
    - Copies `configs/systemd/lab-init.service` into `/etc/systemd/system/lab-init.service`.

3. **Build‑time scripts**

    - Copies `scripts/` to `/opt/jenkins-scripts/` and marks all scripts executable.

4. **Install post‑setup scripts on PATH**

    - Installs `install-pipeline-tools.sh` as `/usr/local/bin/install-pipeline-tools`.
    - Installs `install-plugins.sh` as `/usr/local/bin/install-plugins`.
    - These are **not executed at build time**; they are meant for you to run via `sudo` after Jenkins is configured.

5. **Install Java and Jenkins**

    - Runs `/opt/jenkins-scripts/install-jenkins.sh ${JENKINS_PORT}` to install Java 21, Jenkins LTS, the `jenkins` user, and any required directories/services.

6. **Configure Nginx**

    - Runs `/opt/jenkins-scripts/configure-nginx.sh` to enable the Jenkins site, set up logs, and integrate with systemd.

7. **Enable systemd units**

    - Enables `lab-init`, `nginx`, and `jenkins` via `systemctl enable`. On boot, `lab-init` runs first, then Nginx and Jenkins.

8. **Healthcheck and cloudflared**

    - Executes `/opt/jenkins-scripts/healthcheck.sh ${USER}` which validates the installation across multiple sections (Java/Jenkins/Nginx/systemd/user).
    - Runs `/opt/jenkins-scripts/install-cloudflared.sh` to install `cloudflared`.

9. **Home ownership and shell customization**

    - `chown -R ${USER}:${USER} /home/${USER}` to correct ownership for any files written during build.
    - `USER $USER`, `ENV HOME=/home/$USER`.
    - Copies `welcome` to `$HOME/.welcome` and substitutes `__JENKINS_PORT__` using `sed`.
    - Binds `scripts/` as `/tmp/scripts` and runs `customize-bashrc.sh` to add aliases and helpers.

10. **Return to root for final image**

    - Switches back to `USER root` since systemd (PID 1) requires root.
    - Exposes ports `22`, `80`, and `JENKINS_PORT`.
    - `CMD ["/lib/systemd/systemd"]`.

> **Why this matters:** Understanding this flow is key when debugging build issues or extending Jenkins with new services or proxies.

---

### 2. Build and push via GitHub Actions

The canonical CI path is in
[`.github/workflows/build-jenkins-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-jenkins-rootfs.yml).

Key behavior:

- **Triggers**
    - On `push` to `main` affecting `iximiuz/rootfs/jenkins/**` (excluding `README.md`) or the workflow file.
    - On PRs with the same paths.
    - Manual `workflow_dispatch`.

- **Environment**
    - `IMAGE_NAME` is `ghcr.io/${{ github.repository_owner }}/jenkins-rootfs`.

- **Build**
    - Checkout repo.
    - Set up QEMU and Buildx for `amd64` and `arm64`.
    - Log into GHCR with `secrets.GITHUB_TOKEN`.
    - Use `docker/metadata-action` to create tags and labels, including:
        - `latest` on default branch.
        - `2.541.2-lts` tag.
        - `lts` tag.
        - `sha-<short-sha>` and date tags.
        - Labels referencing base image `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`.
    - Build and push with `docker/build-push-action` using:
        - `context: ./iximiuz/rootfs/jenkins`
        - `file: ./iximiuz/rootfs/jenkins/Dockerfile`
        - `platforms: linux/amd64,linux/arm64`
        - `build-args: USER=ibtisam, JENKINS_PORT=8080`.
    - Print the image digest at the end.

> **Why this matters:** Matching local build args to CI build args ensures parity between what you test locally and what iximiuz pulls from GHCR.

---

## Verification

### Local container test

As in the README:

```bash
docker run -d \
  --name jenkins-test \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  --tmpfs /tmp \
  --tmpfs /run \
  --tmpfs /run/lock \
  -p 8080:80 \
  -p 7022:22 \
  ghcr.io/ibtisam-iq/jenkins-rootfs:latest
```

Then:

```bash
# Check services
docker exec jenkins-test systemctl is-active lab-init nginx jenkins

# Get initial admin password
docker exec jenkins-test \
  cat /var/lib/jenkins/.jenkins/secrets/initialAdminPassword

# Test Nginx reverse proxy
docker exec jenkins-test curl -f http://localhost/health

# Jenkins UI from host
open http://localhost:8080
```

Optionally, test post‑setup scripts:

```bash
# Install pipeline tools
docker exec -it jenkins-test sudo install-pipeline-tools

# After completing setup wizard
docker exec -it jenkins-test sudo install-plugins
```

> **Why this matters:** This flow validates systemd, Jenkins, Nginx, Cloudflare support, and post‑setup scripts before wiring the image into iximiuz or production‑like flows.

---

### GHCR image check

```bash
skopeo inspect docker://ghcr.io/ibtisam-iq/jenkins-rootfs:lts \
  | jq '.Name,.Labels."org.opencontainers.image.base.name"'
```

Expected:

- Name: `ghcr.io/ibtisam-iq/jenkins-rootfs`
- Base name label: `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`.

---

## Integration with iximiuz Labs

Once the image is verified locally and pushed to GHCR, it can be launched as a custom iximiuz playground using the `labctl` CLI and a manifest file. Unlike iximiuz's built-in catalog labs, custom rootfs images cannot be started directly from the iximiuz UI - they require a manifest file to declare the machine drive source, resources, and tabs.

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
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/iximiuz/manifests/jenkins-server.yml \
  -o jenkins-server.yml
```

The manifest declares a single machine `jenkins-server` whose root drive is mounted directly from the published GHCR image:

```yaml
drives:
  - source: oci://ghcr.io/ibtisam-iq/jenkins-rootfs:latest
    mount: /
    size: 50GiB
```

The manifest can be edited before running - for example, to adjust `cpuCount`, `ramSize`, or `size` to match account quota or preferences.

Run `labctl playground create` pointing at the local manifest:

```bash
labctl playground create --base flexbox jenkins-server -f jenkins-server.yml
```

When the command succeeds, `labctl` prints the playground URL and its unique ID:

```
Creating playground from /path/to/<MANIFEST_FILENAME>
Playground URL: https://labs.iximiuz.com/playgrounds/jenkins-server-<unique-id>
jenkins-server-<unique-id>
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
   (e.g., `SilverStack Jenkins Server`). If the manifest title was
   customized before running, look for that name instead.
5. The playground card shows a **Start** button and a three-dot menu (⋮).

To start immediately, click **Start**.

To review or adjust settings before starting, click ⋮ → **Configure**. This opens the Playground Settings page where machine drives, resources, network, and UI tabs can be inspected before launch.

![](../../../assets/screenshots/jenkins-server-drive-config.png)

---

### Step 3 - Verify the running playground

Once started, the welcome banner is displayed automatically and shows the configured internal
ports, service status commands, and next steps.

Follow the instructions in the welcome file for post-setup tasks:
[`iximiuz/rootfs/jenkins/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/welcome)

![](../../../assets/screenshots/jenkins-server-welcome.png)

---

## Cloudflare Tunnel Configuration

To expose the service on a custom public domain, `cloudflared` is already installed in the image. The welcome page includes step-by-step instructions for configuring and connecting the tunnel. Follow those instructions on first login.

If any issues arise during Cloudflare Tunnel setup, refer to phase 4 in the following runbook:

> 📖 [self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs.md](../../../self-hosted/ci-cd/iximiuz/self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs.md#phase-4-implementation---creating-cloudflare-tunnels)

---

## Related

- Jenkins Rootfs README - [`iximiuz/rootfs/jenkins/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/README.md)
- Jenkins Dockerfile - [`iximiuz/rootfs/jenkins/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/Dockerfile)
- Jenkins scripts - [`iximiuz/rootfs/jenkins/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/scripts)
- Jenkins configs - [`iximiuz/rootfs/jenkins/configs/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/jenkins/configs)
- Jenkins welcome - [`iximiuz/rootfs/jenkins/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/jenkins/welcome)
- Jenkins build workflow - [`.github/workflows/build-jenkins-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-jenkins-rootfs.yml)
- Jenkins iximiuz manifest - [`iximiuz/manifests/jenkins-server.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/jenkins-server.yml)
