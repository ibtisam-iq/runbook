# Install a CNI Plugin on Kubernetes

A CNI (Container Network Interface) plugin is required before any node in the
cluster can reach `Ready` state. This runbook covers installing **Calico** or
**Flannel** on an existing Kubernetes cluster using the silver-stack automation.

---

## Quick Start

Run the dispatcher on **control plane node** after `kubeadm init` has
completed and kubeconfig is configured:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-cni.sh | sudo bash
```

The script walks through every phase interactively. There is no need to
choose Calico or Flannel upfront — it asks at the end.

---

## Scripts

| Script | Role | Path |
|---|---|---|
| `install-cni.sh` | Dispatcher — orchestrates the full flow | `cni/install-cni.sh` |
| `install-calico.sh` | Installs Calico via Tigera Operator | `cni/install-calico.sh` |
| `install-flannel.sh` | Installs Flannel from latest release manifest | `cni/install-flannel.sh` |

---

## Prerequisites

- A running Kubernetes cluster (`kubeadm init` completed successfully)
- kubeconfig configured and `kubectl` working — see [Kubeconfig & CNI](../../cluster-kubeadm/ref-kubeconfig-and-cni.md)
- No CNI plugin currently installed (or a supported one — Calico or Flannel — that the dispatcher can clean up safely)
- Running as root or via `sudo`

---

## What the Dispatcher Does

`install-cni.sh` is the only script you run directly. It orchestrates five
sequential phases before handing off to the CNI-specific installer:

| Phase | What happens |
|---|---|
| 1 — Cluster detection | Verifies `kube-system` namespace is reachable via `kubectl` |
| 2 — CNI binaries | Checks `/opt/cni/bin`; installs binaries if missing |
| 3 — Filesystem residue | Removes leftover `.conf` / `.conflist` files from `/etc/cni/net.d` |
| 4 — Active CNI detection | Detects running Calico or Flannel daemonsets; offers safe cleanup |
| 5 — CNI selection & install | Prompts for choice (Calico = default, Flannel); runs installer |

At each destructive step the script pauses and waits for `Enter` or typed
`YES` — nothing is removed silently.

---

## Choosing a CNI

| | Calico | Flannel |
|---|---|---|
| **Install method** | Tigera Operator + CRDs | Single manifest (`kube-flannel.yml`) |
| **Pod CIDR** | Auto-detected from `kubeadm-config` | Auto-detected from `kubeadm-config` |
| **Encapsulation** | VXLAN (default) or IPIP — prompted at install | VXLAN (hardcoded) |
| **Namespace** | `calico-system` + `tigera-operator` | `kube-flannel` |
| **Complexity** | Higher — operator-managed, more CRDs | Lower — single manifest |
| **Use when** | Need NetworkPolicy, BGP, or advanced routing | Need a simple, fast overlay network |

---

## CNI-Specific Runbooks

- [Install Calico](install-calico.md) — 12-phase deep dive: Tigera Operator, custom resources, CIDR patching, encapsulation config
- [Install Flannel](install-flannel.md) — 8-phase deep dive: manifest download, CIDR patching, daemonset readiness

---

## Dry Run

Both the dispatcher and individual installers accept `--dry-run`:

```bash
curl -fsSL .../install-cni.sh | sudo bash -s -- --dry-run
```

`DRY_RUN=1` is exported to `common.sh` — state-modifying operations are
logged but not executed.

---

## Limitations

!!! warning "Supported CNIs only"
    This script detects and removes **only** Calico and Flannel. If another
    CNI (Weave, Cilium, etc.) is installed, `install-cni.sh` will not detect
    it and is not suitable for that environment.
