# Cluster Bootstrap

!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Phases 7, 8 & 9 of 9** — The final automated phases: detect any existing cluster state, verify containerd and kubelet readiness, then run `kubeadm init` to bring up the control plane.

    **Prerequisite:** [Kubernetes Packages](kubernetes-packages.md) — all binaries must be installed on all nodes.  
    **Next step:** [Kubeconfig & CNI](kubeconfig-and-cni.md) — two manual post-init steps to make the cluster fully usable.

---

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
| `CONTROL_PLANE_IP` | Auto-detected from `hostname -I` | `--apiserver-advertise-address` for `kubeadm init` |
| `K8S_VERSION` | `1.32` | Minor version passed to version resolver |
| `HOSTNAME` | `$(hostname)` | `--node-name` for `kubeadm init` |
| `POD_CIDR` | `192.168.0.0/16` | `--pod-network-cidr` for `kubeadm init` |
| `CONTAINERD_METHOD` | `package` | Selects install path in Phase 4 |

All defaults are sensible — pressing Enter on every prompt produces a working
cluster on most Ubuntu VMs.

`cluster-params-2.sh` is an extended variant that exposes additional low-level
parameters for advanced deployments.

---

## Phase 7 — Detect Existing Cluster

`detect-existing-cluster.sh` runs before `kubeadm init` to protect against
accidentally initializing on a node that already has Kubernetes state.

**What it checks:**

| Check | What it looks for |
|---|---|
| Running API server process | `pgrep kube-apiserver` |
| Occupied ports | 6443 (API server), 2379 (etcd client), 10250 (kubelet) |
| Existing etcd data | `/var/lib/etcd` directory present and non-empty |
| Existing Kubernetes config | `/etc/kubernetes/manifests/kube-apiserver.yaml` |

**Outcomes:**

- **No indicators found** → proceeds to Phase 8
- **Weak indicators** (e.g. only occupied ports, no etcd data) → warns and continues
- **Strong indicators** (API server running, etcd data present) → prompts operator
  to confirm reset, then calls `reset-cluster.sh` automatically

---

## Phase 8 — Ensure Kubernetes Services

`ensure-k8s-services.sh` waits for both services to be in the correct state
before handing off to `kubeadm init`:

| Service | Expected state | Action if not ready |
|---|---|---|
| `containerd` | `active (running)` | Starts it, waits up to 30 seconds |
| `kubelet` | `enabled` (may be crash-looping — this is normal pre-init) | Enables it if disabled |

The script does not require kubelet to be *running* — only enabled. Kubelet
will crash-loop until `kubeadm init` writes its config. This is expected
behavior.

---

## Phase 9 — Bootstrap Control Plane

`bootstrap-controlplane.sh` runs `kubeadm init` with the parameters collected
in Phase 1:

```bash
kubeadm init \
  --apiserver-advertise-address="$CONTROL_PLANE_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --node-name="$HOSTNAME" \
  --kubernetes-version="$K8S_FULL_VERSION" \
  --cri-socket=unix:///run/containerd/containerd.sock
```

**After `kubeadm init` succeeds, the script:**

1. Prints the full `kubeadm join` command — copy this for your worker nodes
2. Prints the URL for the kubeconfig helper script
3. Prints the URL for the CNI installer script
4. Exits cleanly

**The script does NOT:**

- Configure kubeconfig automatically (deferred — see [Kubeconfig & CNI](kubeconfig-and-cni.md))
- Install a CNI plugin (deferred — see [Kubeconfig & CNI](kubeconfig-and-c