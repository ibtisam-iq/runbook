# Install Docker

Docker is an open-source platform for building, shipping, and running
applications in isolated containers. It packages code and all dependencies
together so the application runs consistently across environments.

!!! warning "Ubuntu and its derivatives only"
    This script targets Ubuntu-based systems (Debian family). It is not
    supported on RHEL, Fedora, Alpine, or macOS.

!!! info "Not for production use"
    This installer is designed for local development, lab clusters, and
    CI environments. For production, follow the
    [official Docker hardening guide](https://docs.docker.com/engine/security/).

---

## What Gets Installed

| Component | Purpose |
|---|---|
| `docker-ce` | Docker Engine (daemon + CLI) |
| `docker-ce-cli` | Docker CLI |
| `containerd.io` | Low-level container runtime |
| `docker-buildx-plugin` | Multi-platform image build support |
| `docker-compose-plugin` | `docker compose` subcommand |

---

## Prerequisites

- Ubuntu or an Ubuntu-based OS
- `curl` available
- Run as root or with `sudo`

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/installers/install-docker.sh | sudo bash
```

!!! note "Idempotent — safe to re-run"
    If Docker is already installed, the script detects it, validates the
    daemon state, repairs it if inactive, and exits without reinstalling.

---

## What the Script Does

1. Runs preflight checks (OS, connectivity, root access)
2. Installs `ca-certificates` and `curl` as prerequisites
3. Adds the official Docker APT repository and GPG key
4. Installs all five Docker components in one `apt-get install`
5. Enables and starts the Docker daemon via `systemctl`
6. Adds the invoking user to the `docker` group

---

## Post-Install

Apply the `docker` group to the current shell session without logging out:

```bash
newgrp docker
```

Verify the installation:

```bash
docker version
docker compose version
```

!!! tip "Optional: Set up a short alias with tab completion"
    Add these lines to `~/.bashrc` to use `d` as a shorthand for `docker`:

    ```bash
    alias d='docker'
    if declare -f __start_docker > /dev/null 2>&1; then
        complete -F __start_docker d
    fi
    ```

    Reload the shell to apply:

    ```bash
    source ~/.bashrc
    ```
