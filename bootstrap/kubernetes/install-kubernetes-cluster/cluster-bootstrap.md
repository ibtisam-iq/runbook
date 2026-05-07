# Cluster Bootstrap

The cluster bootstrap layer covers the five steps that take a prepared node
(runtime installed, packages installed) through to a running Kubernetes control
plane: parameter collection, existing-state detection, service readiness
verification, and `kubeadm init`.

---

## Scripts

| Script | Phase | Path |
|---|---|---|
| Cluster parameters wizard | 1 | `cluster/cluster-params.sh` |
| Cluster parameters wizard (advanced) | 1 | `cluster/cluster-params-2.sh` |
| Detect existing cluster | 7 | `cluster/detect-existing-cluster.sh` |
| Ensure Kubernetes services | 8 | `cluster/ensure-k8s-services.sh` |
| Bootstrap control plane | 9 | `cluster/bootstrap-controlplane.sh` |

---

## Phase 1 — Cluster Parameters

`cluster-params.sh` is sourced (not executed) into the entrypoint shell so
its exports remain available across all subsequent phases.

**Interactive prompts:**

| Parameter | Default | What it controls |
|---|---|---|
| Node IP | Auto-detected from primary network interface | `--apiserver-advertise-address`, `--control-plane-endpoint` |
| Kubernetes version | `1.36` | Passed to version resolver |
| Node hostname | `hostname` output | `--node-name` in `kubeadm init` |
| Pod CIDR | `10.244.0.0/16` | `--pod-network-cidr` in `kubeadm init` |
| Containerd method | `package` | Routes `install-containerd.sh` dispatcher |

**Exported variables (available to all downstream scripts):**

```bash
CONTROL_PLANE_IP        # e.g. 192.168.1.100
K8S_VERSION             # e.g. 1.36
NODE_NAME               # e.g. k8s-control-plane
POD_CIDR                # e.g. 10.244.0.0/16
CONTAINERD_INSTALL_METHOD  # package | binary
```

### Advanced Wizard (`cluster-params-2.sh`)

`cluster-params-2.sh` is a hardened variant that adds:

- Detects the currently installed `kubelet` version (if any)
- Enforces a **maximum one-minor-version** upgrade or downgrade rule — rejects
  a requested version that is more than one minor step away
- Validates version input with a retry loop (up to 5 attempts) before aborting
- Uses the same exports as `cluster-params.sh` and is a drop-in replacement

Use `cluster-params-2.sh` on nodes that may have a previous Kubernetes
installation or in environments where version discipline must be enforced.

---

## Phase 7 — Detect Existing Cluster

`detect-existing-cluster.sh` prevents running `kubeadm init` on a node that
already has Kubernetes state. It classifies detected state into two categories:

### Strong Indicators (block init, offer full reset)

These indicate a control plane is running or was initialized:

| Check type | What is checked |
|---|---|
| Filesystem | `/var/lib/etcd`, `/etc/kubernetes/manifests/etcd.yaml`, `kube-apiserver.yaml`, `kube-scheduler.yaml`, `kube-controller-manager.yaml` |
| Ports | `6443` (API server), `2379/2380` (etcd), `10250` (kubelet), `10257/10259` (controller-manager, scheduler) |

When strong indicators are found:

1. The script prints all detected items
2. Prompts: press Enter to run `reset-cluster.sh` automatically, or Ctrl+C to abort
3. On confirmation, runs `reset-cluster.sh` via `run_remote_script`
4. Exits cleanly — the entrypoint continues from Phase 8

### Weak Indicators (offer targeted cleanup)

These indicate leftover node state from a previous kubeadm run that was not
fully cleaned:

| Path | What it means |
|---|---|
| `/var/lib/kubelet` | kubelet data directory not cleaned |
| `/etc/kubernetes/pki` | certificates from a previous cluster |
| `/etc/kubernetes/admin.conf` | previous kubeconfig |
| `~/.kube` | user kubeconfig |

When only weak indicators are found, the script offers a targeted cleanup
(no `kubeadm reset`) and removes only those specific paths.

### Clean Node

If neither strong nor weak indicators are found, the script exits `0` silently
and the entrypoint proceeds to Phase 8 immediately.

---

## Phase 8 — Ensure Kubernetes Services

`ensure-k8s-services.sh` verifies that `containerd` and `kubelet` are in the
correct state before `kubeadm init` runs.

**For each service (`containerd`, `kubelet`):**

1. Checks if the service is enabled — enables it if not
2. Checks if the service is active — starts it if not

**Special handling for kubelet:**

kubelet is expected to crashloop before `kubeadm init` because there is no
cluster configuration yet. The script starts it anyway and logs:

```
kubelet started (crashloop is normal at this stage)
```

This ensures systemd has ownership of kubelet so `kubeadm init` can
communicate with it cleanly.

**Post-phase state:**

- `containerd` is running and its socket is available
- `kubelet` is started (crashlooping is acceptable)
- The node is ready for `kubeadm init`

---

## Phase 9 — Bootstrap Control Plane

`bootstrap-controlplane.sh` runs the actual `kubeadm init` command.

**Pre-flight validation:**

The script verifies all required variables are exported before proceeding:

```
CONTROL_PLANE_IP, NODE_NAME, POD_CIDR, K8S_VERSION
K8S_PATCH_VERSION, K8S_IMAGE_TAG  (from version resolver)
```

**Image pre-pull:**

```bash
kubeadm config images pull   --kubernetes-version v1.36.0   --cri-socket unix:///var/run/containerd/containerd.sock
```

Pre-pulling images before `kubeadm init` reduces the chance of init timing out
on slow network connections.

**kubeadm init flags:**

```bash
kubeadm init   --control-plane-endpoint "${CONTROL_PLANE_IP}:6443"   --upload-certs   --pod-network-cidr "${POD_CIDR}"   --apiserver-advertise-address "${CONTROL_PLANE_IP}"   --kubernetes-version "${K8S_IMAGE_TAG}"   --node-name "${NODE_NAME}"   --cri-socket unix:///var/run/containerd/containerd.sock
```

| Flag | Purpose |
|---|---|
| `--control-plane-endpoint` | Sets the stable endpoint for the API server (enables HA later) |
| `--upload-certs` | Uploads control plane certificates to a kubeadm Secret so additional control plane nodes can join without manual certificate distribution |
| `--pod-network-cidr` | Must match the CIDR configured in the CNI plugin |
| `--apiserver-advertise-address` | The IP address the API server listens on and advertises to other cluster members |
| `--kubernetes-version` | Pins the exact patch version (`v1.36.0`) to prevent pulling the latest unintentionally |
| `--cri-socket` | Explicit CRI socket path — avoids auto-detection failures when multiple runtimes are present |

**Post-init output:**

After a successful `kubeadm init`, the script prints two optional helper
commands:

```bash
# Configure kubectl access
curl -fsSL .../cluster/kubeconfig-helper.sh | bash

# Install CNI plugin
curl -fsSL .../cni/install-cni.sh | sudo bash
```

These are printed as guidance. The `kubeadm init` output itself also contains
the authoritative `kubeadm join` token for workers and additional control plane
nodes — copy this output before proceeding.
