# Architecture & Internals

!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Reference** — Explains how the automation layer is structured, how scripts execute,
    and what the shared `common.sh` library provides. Read this if you want to understand
    or extend the scripts — not required to run the cluster.

---

## Directory Structure

```
scripts/kubernetes/
├── entrypoints/     ← Start here. Two scripts: control plane and worker.
├── cluster/         ← kubeadm init logic, cluster parameters wizard, safety guards
├── node/            ← OS prerequisites: swap, kernel modules, sysctl
├── runtime/         ← containerd, runc, crictl, CNI binaries
├── packages/        ← kubelet, kubeadm, kubectl, helm, k9s — with version pinning
├── cni/             ← Calico and Flannel installers
├── maintenance/     ← Reset scripts
├── manifests/       ← KinD cluster YAML configurations
└── lib/             ← Shared library: logging, remote execution, kubeconfig helpers
```

---

## Execution Paths

### Path 1 — Bare-Metal / VM Cluster (kubeadm)

| Entrypoint | Node Role | Phases |
|---|---|---|
| `entrypoints/init-controlplane.sh` | Control plane | Preflight → Params → Node prep → Runtime prereqs → Containerd → K8s packages → CLI tools → Detect existing → Ensure services → kubeadm init |
| `entrypoints/init-worker-node.sh` | Worker | Preflight → Params → Node prep → Runtime prereqs → Containerd → K8s packages |

Run the control plane entrypoint first. Copy the `kubeadm join` token it prints, then run
the worker entrypoint on each worker node.

### Path 2 — Local Development Cluster (KinD)

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/create-kind-cluster.sh | bash
```

See [KinD Local Cluster](kind-local-cluster.md) for full details.

---

## Script Execution Model

Scripts never assume a local filesystem layout. Every script:

1. Creates a temp file via `mktemp`
2. Downloads `common.sh` into it via `curl -fsSL`
3. Sources it into the running shell
4. Deletes the temp file
5. Proceeds with its own logic

This makes every script safe to run via `curl | bash` on a completely fresh node.

---

## Common Library (`common.sh`)

Every script sources `common.sh` at runtime:

```bash
LIB_URL="https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/lib/common.sh"
```

`common.sh` provides:

| Function | Purpose |
|---|---|
| `info`, `ok`, `warn`, `error` | Colored log output |
| `blank`, `cmd`, `item`, `banner`, `footer` | Structured output helpers |
| `require_root` | Exits if not running as root |
| `confirm_sudo_execution` | Detects and warns on sudo context |
| `run_remote_script` | Downloads and executes a remote script with a label |
| `source_remote_library` | Sources a remote script into current shell |
| `confirm_or_abort` | Requires typed `YES` before destructive actions |

---

## Dry Run Mode

All scripts accept `--dry-run`. When set, `DRY_RUN=1` is exported. Operations
that would modify system state are skipped and logged instead.

```bash
curl -fsSL <script-url> | sudo bash -s -- --dry-run
```

---

## Full Phase Reference — Control Plane Init

| Phase | Script | Purpose |
|---|---|---|
| Preflight | `scripts/lib/preflight.sh` | OS, architecture, and connectivity checks |
| 1 | `cluster/cluster-params.sh` | Interactive wizard: IP, version, hostname, Pod CIDR, containerd method |
| 2 | `node/disable-swap.sh` + `load-kernel-modules.sh` + `apply-sysctl.sh` | OS prerequisites |
| 3 | `runtime/install-cni-binaries.sh` + `install-crictl.sh` | Runtime prerequisites |
| 4 | `runtime/install-containerd.sh` | Containerd install and config |
| 4 (post) | `runtime/config-crictl.sh` | crictl endpoint config |
| Version | `lib/k8s-version-resolver.sh` | Resolve patch version from MAJOR.MINOR |
| 5 | `packages/install-kubeadm-kubelet.sh` | kubelet + kubeadm install |
| 6 | `packages/install-controlplane-cli.sh` | kubectl + helm + k9s (control plane only) |
| 7 | `cluster/detect-existing-cluster.sh` | Block unsafe re-init |
| 8 | `cluster/ensure-k8s-services.sh` | containerd + kubelet readiness |
| 9 | `cluster/bootstrap-controlplane.sh` | `kubeadm init` |
