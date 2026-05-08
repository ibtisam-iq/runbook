# Install Ansible

Ansible is an open-source IT automation tool that configures systems,
deploys applications, and orchestrates multi-step workflows over SSH —
without requiring an agent on managed nodes.

!!! warning "Ubuntu and its derivatives only"
    This script uses the official `ppa:ansible/ansible` PPA, which is
    only available for Ubuntu-based systems. It is not supported on RHEL,
    Fedora, Alpine, or other distributions.

!!! info "Not for production use"
    This installer is designed for lab and learning environments. For
    production, manage Ansible through a virtualenv or a pinned package
    version to avoid unexpected upgrades.

---

## What Gets Installed

| Component | Source | Purpose |
|---|---|---|
| `software-properties-common` | Ubuntu APT | Required to add PPAs |
| `ansible` | `ppa:ansible/ansible` (official) | Automation engine |

---

## Prerequisites

- Ubuntu or an Ubuntu-based OS
- `curl` available
- Run as root or with `sudo`

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/installers/install-ansible.sh | sudo bash
```

!!! note "Idempotent — safe to re-run"
    The script checks both the `ansible` binary in `PATH` and the
    `ansible` Python package. If either is present, it exits without
    reinstalling.

---

## What the Script Does

1. Runs preflight checks (OS, connectivity, root access)
2. Installs `software-properties-common` (required to manage PPAs)
3. Adds the official `ppa:ansible/ansible` repository
4. Installs `ansible` via `apt-get`
5. Runs a dual post-install check — verifies both `ansible` binary
   in `PATH` and the Python package import

---

## Verify

```bash
ansible --version
```

!!! tip "Test connectivity to a managed node"
    ```bash
    ansible all -i "<target-ip>," -m ping --ask-pass
    ```
    The trailing comma in the inventory string is intentional — it tells
    Ansible this is an inline host list, not an inventory file path.
