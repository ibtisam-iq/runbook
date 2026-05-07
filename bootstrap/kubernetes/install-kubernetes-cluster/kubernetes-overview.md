# Kubernetes Automation Overview

This document describes the structure, execution model, and two deployment paths
of the silver-stack Kubernetes automation layer.

---

## What This Layer Does

The `scripts/kubernetes/` tree automates the full lifecycle of a kubeadm-based
Kubernetes cluster — from raw OS prerequisites through CNI installation — using
only `curl | bash` invocations. No local cloning is required. All scripts
download and source `common.sh` at runtime from the silver-stack GitHub
repository.

A separate, parallel path supports local development clusters using **KinD**
(Kubernetes-in-Docker) with declarative YAML manifests.

---

## Execution Paths

### Path 1 — Bare-Metal / VM Cluster (kubeadm)

Two entrypoint scripts cover the full cluster lifecycle:

| Entrypoint | Node Role | Phases |
|---|---|---|
| `entrypoints/init-controlplane.sh` | Control plane | Preflight → Params → Node prep → Runtime prereqs → Containerd → K8s packages → CLI tools → Detect existing → Ensure services → kubeadm init |
| `entrypoints/init-worker-node.sh` | Worker | Preflight → Params → Node prep → Runtime prereqs → Containerd → K8s packages |

Run the control plane entrypoint first, then run the worker entrypoint on each worker node and join using the `kubeadm join` token printed by `init-controlplane.sh`.

**Control plane:**

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-controlplane.sh | sudo bash
```

**Worker node:**

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-worker-node.sh | sudo bash
```

### Path 2 — Local Development Cluster (KinD)

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/create-kind-cluster.sh | bash
```

The script prompts for a manifest choice:

- `kind-default.yaml` — 1 control plane + 1 worker, default CNI (Flannel), API on host port 6444
- `kind-calico.yaml` — 2 control planes + 2 workers, default CNI disabled, Calico required post-creation, extensive NodePort mappings (30000–30010)

See [`kind-local-cluster.md`](kind-local-cluster.md) for full details.

---

## Directory Structure

```
scripts/kubernetes/
├── entrypoints/          # User-facing entry scripts (curl | bash)
├── cluster/              # Orchestration, safety guards, kubeadm init
├── node/                 # OS-level prerequisites (swap, kernel, sysctl)
├── runtime/              # Container runtime (containerd, runc, crictl, CNI binaries)
├── packages/             # Kubernetes binaries (kubeadm, kubelet, kubectl, helm, k9s)
├── cni/                  # CNI plugin installation (Calico, Flannel)
├── maintenance/          # Cluster and CNI reset scripts
├── manifests/            # KinD cluster YAML manifests
└── lib/                  # Shared library scripts (sourced, not executed)
```

---

## Common Library (`common.sh`)

Every script in this layer sources `common.sh` at runtime:

```bash
LIB_URL="https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/lib/common.sh"
```

`common.sh` provides:

- Logging helpers: `info`, `ok`, `warn`, `error`, `blank`, `cmd`, `item`, `banner`, `footer`
- `require_root` — exits if not running as root
- `confirm_sudo_execution` — detects and warns on sudo context
- `run_remote_script` — downloads and executes a remote script with a label
- `source_remote_library` — sources a remote script into current shell
- `confirm_or_abort` — requires typed `YES` before destructive actions

---

## Dry Run Mode

All scripts accept `--dry-run` as a flag. When set, `DRY_RUN=1` is exported and
passed to `common.sh` helpers. Operations that would modify system state are
skipped or logged without execution.

```bash
curl -fsSL <script-url> | sudo bash -s -- --dry-run
```

---

## Script Execution Model

Scripts never assume a local filesystem layout. Each script:

1. Creates a temp file via `mktemp`
2. Downloads `common.sh` into it via `curl -fsSL`
3. Sources it
4. Deletes the temp file
5. Proceeds with its own logic

This makes every script safe to run via `curl | bash` on a fresh node.

---

## Phase Reference — Control Plane Init

| Phase | Script | Purpose |
|---|---|---|
| Preflight | `scripts/lib/preflight.sh` | OS/arch/connectivity checks |
| 1 | `cluster/cluster-params.sh` | Interactive wizard: IP, version, hostname, Pod CIDR, containerd method |
| 2 | `node/disable-swap.sh` + `load-kernel-modules.sh` + `apply-sysctl.sh` | OS prerequisites |
| 3 | `runtime/install-cni-binaries.sh` + `install-crictl.sh` | Runtime prerequisites |
| 4 | `runtime/install-containerd.sh` | Containerd install + config |
| 4 (post) | `runtime/config-crictl.sh` | crictl endpoint config |
| Version | `lib/k8s-version-resolver.sh` | Resolve patch version from MAJOR.MINOR |
| 5 | `packages/install-kubeadm-kubelet.sh` | kubelet + kubeadm install |
| 6 | `packages/install-controlplane-cli.sh` | kubectl + helm + k9s (control plane only) |
| 7 | `cluster/detect-existing-cluster.sh` | Block unsafe re-init |
| 8 | `cluster/ensure-k8s-services.sh` | containerd + kubelet readiness |
| 9 | `cluster/bootstrap-controlplane.sh` | `kubeadm init` |

---

## Post-Init Steps (Manual)

After `init-controlplane.sh` completes, two manual steps remain:

```bash
# 1. Configure kubectl access
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cluster/kubeconfig-helper.sh | bash

# 2. Install a CNI plugin
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-cni.sh | sudo bash
```

See [`kubeconfig-and-cni.md`](kubeconfig-and-cni.md) for full details.
