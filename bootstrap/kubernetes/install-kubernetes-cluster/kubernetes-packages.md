# Kubernetes Packages

!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Phases 5 & 6 of 9** — Installs Kubernetes binaries with exact version pinning. All nodes get kubelet and kubeadm; the control plane additionally gets kubectl, helm, and k9s.

    **Prerequisite:** [Container Runtime](container-runtime.md) — containerd must be installed and running.  
    **Next step:** [Cluster Bootstrap](cluster-bootstrap.md) — detect existing state, verify services, and run `kubeadm init`.

---

Phase 5 and Phase 6 install the Kubernetes binaries. Worker nodes receive
`kubelet` and `kubeadm` only. Control plane nodes additionally receive
`kubectl`, `helm`, and `k9s`.

---

## Scripts

| Script | Phase | Installed on |
|---|---|---|
| `packages/install-kubeadm-kubelet.sh` | 5 | All nodes |
| `packages/install-controlplane-cli.sh` | 6 | Control plane only |
| `lib/k8s-version-resolver.sh` | Pre-5 | Sourced by both |

---

## Version Resolution

Before any package is installed, the version resolver is sourced into the
running shell. It accepts a `MAJOR.MINOR` string and resolves the exact
patch release via the official Kubernetes release API.

**Input:**

```bash
export K8S_VERSION="1.36"   # Set during cluster-params wizard (Phase 1)
```

**What `k8s-version-resolver.sh` does:**

1. Queries `https://dl.k8s.io/release/stable-1.36.txt` → gets `v1.36.0`
2. Strips the `v` prefix → `1.36.0`
3. Converts to Debian package revision → `1.36.0-1.1`
4. Exports `K8S_FULL_VERSION=1.36.0` and `K8S_PKG_VERSION=1.36.0-1.1`

**Why this matters:** APT package names require the full revision string
(`kubelet=1.36.0-1.1`). Floating version installs (`apt install kubelet`) would
install whatever is latest in the repo — potentially a different version than
you intended or tested.

---

## Phase 5 — kubelet and kubeadm (All Nodes)

**`install-kubeadm-kubelet.sh`**

1. Adds the Kubernetes APT repo for the resolved minor version:
   `https://pkgs.k8s.io/core:/stable:/v1.36/deb/`
2. Installs:
   - `kubelet=$K8S_PKG_VERSION`
   - `kubeadm=$K8S_PKG_VERSION`
3. Runs `apt-mark hold kubelet kubeadm` — prevents accidental upgrades via
   `apt upgrade`

```bash
kubelet --version   # e.g. Kubernetes v1.36.0
kubeadm version     # e.g. kubeadm version: v1.36.0
apt-mark showhold   # Should list: kubelet, kubeadm
```

---

## Phase 6 — Control Plane CLI Tools (Control Plane Only)

**`install-controlplane-cli.sh`** is called only by `init-controlplane.sh`.
Worker nodes skip this phase entirely.

### kubectl

Installed from the same APT repo as kubelet:

```bash
kubectl=$K8S_PKG_VERSION
apt-mark hold kubectl
```

Version-matched to the cluster to avoid skew warnings.

### helm

Installed via the official Helm installer script:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

This always installs the latest stable Helm 4 release. Helm does not need
to match the Kubernetes version exactly.

```bash
helm version   # e.g. v4.x.x
```

### k9s

Installed as a binary from GitHub releases (`v0.50.16`):

1. Downloads the architecture-appropriate tarball
2. Extracts the `k9s` binary to `/usr/local/bin/k9s`

```bash
k9s version
```

---

## Why kubelet Is Not Started Here

After installation, `kubelet` is enabled as a systemd service but does not
start successfully yet — it has no cluster configuration. It will restart
repeatedly (this is normal) until `kubeadm init` writes its configuration in
Phase 9. Phase 8 (`ensure-k8s-services.sh`) waits for this condition before
proceeding.
