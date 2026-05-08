# Install Terraform

Terraform is an open-source Infrastructure as Code (IaC) tool by HashiCorp.
It lets you define, provision, and manage cloud and on-premises infrastructure
using declarative configuration files.

!!! warning "Ubuntu and its derivatives only — x86_64 architecture only"
    This script targets Ubuntu-based systems on `x86_64` (`amd64`) hardware.
    ARM64, RHEL, Fedora, and macOS are not supported by this installer.

!!! info "Not for production use"
    This installer is designed for lab and learning environments. For
    production CI/CD pipelines, pin a specific Terraform version explicitly
    rather than always resolving the latest.

---

## What Gets Installed

| Component | Version | Location |
|---|---|---|
| `terraform` binary | Latest stable (auto-resolved) | `/usr/local/bin/terraform` |

!!! note "Version resolution strategy"
    The script resolves the latest stable version automatically:
    1. Queries the GitHub releases API first
    2. Falls back to the HashiCorp releases index if GitHub is unavailable

    The resolved version is printed before download begins.

---

## Prerequisites

- Ubuntu or an Ubuntu-based OS
- `x86_64` (`amd64`) architecture
- `curl` available
- Run as root or with `sudo`

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/installers/install-terraform.sh | sudo bash
```

!!! note "Idempotent — safe to re-run"
    If Terraform is already installed, the script prints the current version
    and exits without reinstalling.

---

## What the Script Does

1. Runs preflight checks (OS, connectivity, root access, architecture)
2. Resolves the latest stable Terraform version from GitHub API
   (falls back to HashiCorp releases index if GitHub is unavailable)
3. Downloads the `linux_amd64` `.zip` from `releases.hashicorp.com`
4. Installs `unzip` silently if not present
5. Extracts the binary, makes it executable, and moves it to
   `/usr/local/bin/terraform`

---

## Verify

```bash
terraform version
```

!!! tip
    Run `terraform -install-autocomplete` after installation to enable
    shell tab completion for Terraform commands.
