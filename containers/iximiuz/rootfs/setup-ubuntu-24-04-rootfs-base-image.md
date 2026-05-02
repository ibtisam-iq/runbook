# Ubuntu 24.04 Rootfs: Base Image Build and Integration

## Context

Ubuntu 24.04 Rootfs is the **base image for all SilverStack iximiuz playground machines** - every other rootfs in this stack builds `FROM` this image.

It is used directly by images like Dev Machine, Jenkins, Nexus, and SonarQube, which assume this base is already systemd‑enabled, SSH‑ready, and equipped with a curated set of DevOps tools.

The image is defined under:

- README: [`iximiuz/rootfs/ubuntu/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/README.md)
- Dockerfile: [`iximiuz/rootfs/ubuntu/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/Dockerfile)
- Scripts: [`iximiuz/rootfs/ubuntu/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/ubuntu/scripts)
- System‑wide prompt: [`iximiuz/rootfs/ubuntu/configs/profile.d/00-prompt.sh`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/configs/profile.d/00-prompt.sh)
- Welcome banner: [`iximiuz/rootfs/ubuntu/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/welcome)
- CI workflow: [`.github/workflows/build-ubuntu-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-ubuntu-rootfs.yml)

Although it can be used directly as a playground rootfs by adapting manifests (for example by editing
[`iximiuz/manifests/dev-machine.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/dev-machine.yml)
to point at `ubuntu-24-04-rootfs` instead of Dev Machine), its **primary purpose** is to act as a **clean, consistent base for child images**.

---

## Objectives

Ubuntu 24.04 Rootfs must:

- Provide a **fully unminimized, systemd‑enabled Ubuntu 24.04** base with correct boot behavior in iximiuz microVMs.
- Configure **SSH** with key‑based auth only and appropriate defaults for playground use.
- Deliver a **sane default shell environment**: custom PS1 prompt, bash completion, vim, fzf, ripgrep, and Git configuration helpers.
- Ship a small but powerful **DevOps toolset** (arkade, jq/yq/fx, task/just, btop, cfssl, code‑server, websocat) that child images can rely on.
- Provide a consistent **per‑user experience** by creating a non‑root `$USER` (default `ibtisam`) with tuned `.bashrc`, `.gitconfig`, and `.vimrc`.
- Be built reproducibly via **GitHub Actions**, multi‑arch, tagged, and published to GHCR as `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs`.

---

## Architecture / Conceptual Overview

At a high level, the base rootfs image:

- Starts from the official `ubuntu:24.04` image and runs `unminimize` to get a full userland.
- Installs systemd, SSH, and a standard Linux troubleshooting toolkit (curl, traceroute, mtr, net-tools, nftables, socat, etc.).
- Cleans up container‑specific artifacts and ensures machine IDs are empty so each VM can generate its own identity at boot.
- Adds a **systemd “examiner” service** via the `set-up-systemd-examiner-service.sh` script so child images can easily inspect service state.
- Installs **system‑wide** tools via “get‑*” scripts (arkade, common CLIs, btop, cfssl, websocat, fx).
- Installs **user‑specific** tools and customizations twice: once for `root`, then again for the non‑root `$USER` created by `add-user.sh`.

The result is a **VM‑ready Ubuntu base** that behaves like a small server, not a minimal container. Child images can safely assume:

- systemd is PID 1 and can manage services.
- SSH is configured and enabled.
- The interactive `$USER` exists with a consistent shell experience.
- Utility tools and the “examiner” service are already present.

---

## Key Decisions

- **Use unminimized Ubuntu instead of slim images**
  Running `unminimize` ensures man pages, locales, and standard tools are available, which is valuable for hands‑on labs and debugging.

- **Mask noisy/irrelevant services**
  Services like `networkd-dispatcher` are masked to reduce noise in journald for lab environments where dynamic network configuration is not needed.

- **SSH key‑only authentication**
  Password authentication is disabled and SSH is tuned (e.g., `UseDNS no`, `AddressFamily inet`) to reduce latency and tighten security in shared environments.

- **Script‑driven base tooling**
  All tool installation and customization is handled by small scripts under `scripts/` so the Dockerfile remains readable and base behavior is easily extended or reused by other projects.

- **Single base for all rootfs images**
  For long‑term maintainability, all service images (Dev Machine, Jenkins, Nexus, SonarQube, etc.) share this common base, ensuring consistent behavior and reducing duplicated setup.

---

## Source Layout and Inputs

From [`iximiuz/rootfs/ubuntu/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/README.md):

```text
ubuntu/
├── Dockerfile
├── welcome
├── configs/
│   └── profile.d/
│       └── 00-prompt.sh       # System-wide PS1 prompt
└── scripts/
    ├── add-user.sh
    ├── customize-bashrc.sh
    ├── customize-git.sh
    ├── customize-vimrc.sh
    ├── get-arkade.sh
    ├── get-btop.sh
    ├── get-cfssl.sh
    ├── get-code-server.sh
    ├── get-common-tools.sh
    ├── get-fzf.sh
    ├── get-websocat.sh
    └── set-up-systemd-examiner-service.sh
```

Key components:

- Dockerfile: [`iximiuz/rootfs/ubuntu/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/Dockerfile)
- Prompt script: [`configs/profile.d/00-prompt.sh`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/configs/profile.d/00-prompt.sh)
- Scripts directory: [`iximiuz/rootfs/ubuntu/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/ubuntu/scripts)
- Welcome: [`iximiuz/rootfs/ubuntu/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/welcome)

> **Why this matters:** Every child image expects these base behaviors and tools; if you change the base scripts or Dockerfile, it can affect the entire stack.

---

## Prerequisites

To build Ubuntu 24.04 Rootfs:

- Docker (with Buildx for multi‑arch if you want to mirror CI).
- A local checkout of `[github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack)` with the `iximiuz/rootfs/ubuntu` tree.
- Network access to fetch packages and GitHub releases referenced by the `get-*` scripts.
- For CI, a GitHub repository with permissions to push to GHCR.

---

## Installation / Build Steps

### 1. Local base image build

From `iximiuz/rootfs/ubuntu`:

```bash
IMAGE_NAME="ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest"

docker build \
  --build-arg USER="ibtisam" \
  --build-arg ARKADE_BIN_DIR="/usr/local/bin" \
  --build-arg BTOP_VERSION="1.4.4" \
  --build-arg CFSSL_VERSION="1.6.5" \
  --build-arg WEBSOCAT_VERSION="1.14.1" \
  -t "${IMAGE_NAME}" \
  .
```

The Dockerfile performs the following major steps:

1. **Unminimize Ubuntu and install base packages**

    - Starts from `ubuntu:24.04`.
    - Copies `unminimize` from `ubuntu:22.04`.
    - Installs system packages: systemd, SSH prerequisites, debugging tools (`curl`, `htop`, `mtr`, `traceroute`, etc.).
    - Runs `yes | unminimize` to restore full userland.
    - Masks `networkd-dispatcher.service` to reduce noise.
    - Clears MOTD, removes `/.dockerenv`, and empties machine IDs so each VM gets its own identity.

2. **Configure SSH**

    - Installs `openssh-server`.
    - Appends configuration enabling only key‑based auth, optimizing for IPv4, disabling DNS lookups, and raising `MaxAuthTries` to tolerate multiple keys.
    - Masks `sshd-keygen` units, disables the SSH socket, removes socket overrides, enables `ssh.service`, and removes any pre‑generated host keys so they are created at first boot.

3. **Systemd examiner service**

    - Copies `examiner*` binaries into `/usr/local/bin`.
    - Runs `set-up-systemd-examiner-service.sh` from scripts to register a systemd service for examining system state.

4. **System‑wide prompt and tools**

    - Copies `configs/profile.d/00-prompt.sh` into `/etc/profile.d` and marks it executable to set a consistent PS1 prompt system‑wide.
    - Runs the following scripts under `scripts/` to install tools globally:
        - `get-arkade.sh` - installs `arkade` into `ARKADE_BIN_DIR` (default `/usr/local/bin`).
        - `get-common-tools.sh` - fetches `jq`, `yq`, `fx`, `task`, `just`, etc.
        - `get-btop.sh` - installs `btop` at the version given by `BTOP_VERSION`.
        - `get-cfssl.sh` - installs `cfssl` at `CFSSL_VERSION`.
        - `get-websocat.sh` - installs `websocat` at `WEBSOCAT_VERSION`.
    - Pipes `curl https://fx.wtf/install.sh | sh` to install `fx`.

5. **Root user customizations**

    - Runs `get-fzf.sh`, `customize-bashrc.sh`, `customize-git.sh`, and `customize-vimrc.sh` to tune the root user’s shell, Git config, and vimrc.

6. **Create non‑root user**

    - Executes `add-user.sh` to create the `$USER` (default `ibtisam`) with appropriate groups and home directory.
    - Switches to `USER $USER` and sets `HOME=/home/$USER`.

7. **User‑specific tools and welcome**

    - Copies `welcome` to `$HOME/.welcome` so the base image itself has a friendly banner on login.
    - Runs `get-code-server.sh`, `get-fzf.sh`, `customize-bashrc.sh`, `customize-git.sh` (with `USER=$USER`), and `customize-vimrc.sh` again for the non‑root user.

> **Why this matters:** All child images (Dev Machine, Jenkins, etc.) assume this base layer already has systemd, SSH, prompt, core tools, and an interactive `$USER` ready to go.

---

### 2. Build and push via GitHub Actions

The canonical build path is defined in
[`.github/workflows/build-ubuntu-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-ubuntu-rootfs.yml).

Key behavior:

- **Triggers**
    - Runs on `push` to `main` when anything under `iximiuz/rootfs/ubuntu/**` (except `README.md`) changes, or when the workflow itself changes.
    - Runs on pull requests touching the same paths.
    - Supports manual `workflow_dispatch` runs.

- **Environment**
    - `IMAGE_NAME` is `ghcr.io/${{ github.repository_owner }}/ubuntu-24-04-rootfs`.

- **Build steps**
    - Checkout repo (`actions/checkout@v4`).
    - Set up QEMU and Buildx for `amd64` and `arm64`.
    - Log into GHCR using `secrets.GITHUB_TOKEN`.
    - Run `docker/metadata-action` to generate tags and labels, including:
        - `latest` on the default branch.
        - `sha-<short-sha>` tags.
        - A date tag `YYYY-MM-DD`.
        - License, base image name (`ubuntu:24.04`), URL, source, vendor, documentation, and authors.
    - Run `docker/build-push-action` with:
        - `context: ./iximiuz/rootfs/ubuntu`
        - `file: ./iximiuz/rootfs/ubuntu/Dockerfile`
        - `platforms: linux/amd64,linux/arm64`
        - `push: true` for non‑PR events.
        - `build-args` matching the local example (`USER`, `ARKADE_BIN_DIR`, `BTOP_VERSION`, `CFSSL_VERSION`, `WEBSOCAT_VERSION`).
    - Print the final image digest.

> **Why this matters:** Treating the workflow as the canonical builder ensures every child image sees a consistent base with reproducible tags and metadata.

---

## Verification

### Local VM behavior (quick check)

Run the container with systemd:

```bash
docker run -d \
  --name ubuntu-rootfs-test \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -p 7022:22 \
  ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest
```

Inside:

```bash
docker exec ubuntu-rootfs-test systemctl is-system-running
docker exec ubuntu-rootfs-test systemctl status ssh
docker exec ubuntu-rootfs-test bash -lc 'echo $PS1'
docker exec ubuntu-rootfs-test bash -lc 'cat ~/.welcome'
```

Expected to see:

- systemd running without errors.
- SSH service active.
- Custom prompt applied.
- Ubuntu 24.04 Rootfs welcome banner visible.

### GHCR image check

After CI or a manual push, verify that the registry holds the expected tags:

```bash
skopeo inspect docker://ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest \
  | jq '.Name,.Labels."org.opencontainers.image.title",.Labels."org.opencontainers.image.base.name"'
```

Expected:

- Name: `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs`
- Title label: `Ubuntu 24.04 Rootfs`
- Base name label: `ubuntu:24.04`.

---

## Integration and Usage

### As a base for child images

The primary integration pattern is in child Dockerfiles that start with:

```dockerfile
FROM ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest
```

Examples include the Dev Machine Dockerfile at
[`iximiuz/rootfs/dev/machine/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/machine/Dockerfile), which layers workstation tooling on top of this base.

Any new service image (e.g., future rootfs for databases, gateways, or other tools) should **reuse this base** instead of re‑implementing systemd + SSH + tooling.

### Optional: direct use as a playground rootfs

Ubuntu 24.04 Rootfs is not primarily wired with its own manifest, but it can be used directly as a playground VM by modifying an existing manifest such as
[`iximiuz/manifests/dev-machine.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/dev-machine.yml), replacing the drive source:

```yaml
drives:
  - source: oci://ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest
    mount: /
    size: 50GiB
```

Then:

```bash
labctl playground create --base flexbox ubuntu-base -f <your-ubuntu-manifest>.yml
```

This gives you a “raw” base VM with the prompt, tooling, and welcome from Ubuntu 24.04 Rootfs, but typically you will use Dev Machine or other child images instead.

---

## Related

- Ubuntu 24.04 Rootfs README - [`iximiuz/rootfs/ubuntu/README.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/README.md)
- Ubuntu 24.04 Rootfs Dockerfile - [`iximiuz/rootfs/ubuntu/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/Dockerfile)
- Ubuntu scripts - [`iximiuz/rootfs/ubuntu/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/ubuntu/scripts)
- Welcome banner - [`iximiuz/rootfs/ubuntu/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/ubuntu/welcome)
- Build workflow - [`.github/workflows/build-ubuntu-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-ubuntu-rootfs.yml)
- Example consumer (Dev Machine) - [`iximiuz/rootfs/dev/machine/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/machine/Dockerfile)
