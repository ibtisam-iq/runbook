# Install Flannel

!!! abstract "Part of: [Install a CNI Plugin on Kubernetes](index.md)"
    **Flannel installer** — Installs Flannel using the official latest-release
    manifest, patched with the cluster's detected Pod CIDR. Simpler and faster
    than Calico — no operator, no CRDs.

    **Prerequisite:** Kubernetes cluster running, kubeconfig configured, no
    existing CNI installed (or use the [dispatcher](index.md) to clean up first).

---

## Script

| Script | Path |
|---|---|
| `install-flannel.sh` | `scripts/kubernetes/cni/install-flannel.sh` |

Run directly (without the dispatcher):

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-flannel.sh | sudo bash
```

---

## Defaults

| Parameter | Default | Notes |
|---|---|---|
| Flannel version | Always latest | Pulled from `flannel-io/flannel/releases/latest` |
| Encapsulation | VXLAN | Hardcoded in Flannel manifest — not configurable |
| Pod CIDR | Auto-detected | Read from `kube-system/kubeadm-config` ConfigMap |
| Working directory | `/tmp/flannel-install` | Cleaned and recreated at each run |

---

## Installation Phases

### Phase 1 — Cluster Access Verification

Sources `ensure_kubeconfig`, then confirms the cluster is reachable:

```bash
kubectl get ns kube-system
```

Exits immediately if the cluster is not accessible.

---

### Phase 2 — Pod CIDR Detection

Reads the Pod CIDR from the `kubeadm-config` ConfigMap — same approach as the
Calico installer. The cluster is the source of truth:

```bash
kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' | grep podSubnet
```

Exits with an error if `podSubnet` cannot be parsed.

---

### Phase 3 — Workspace Preparation

```bash
rm -rf /tmp/flannel-install && mkdir -p /tmp/flannel-install
```

---

### Phase 4 — Download Flannel Manifest

Downloads `kube-flannel.yml` from the official Flannel latest release:

```bash
curl -fsSL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \
  -o /tmp/flannel-install/kube-flannel.yml
```

Always pulls the latest release — no version pinning.

---

### Phase 5 — Patch Pod CIDR

A single `sed -i` substitution patches the `Network` field in the Flannel
ConfigMap inside the manifest before it is applied:

```bash
sed -i 's|"Network": ".*"|"Network": "<detected-pod-cidr>"|' kube-flannel.yml
```

This ensures Flannel uses the same CIDR that was configured during `kubeadm init`.

---

### Phase 6 — Apply Flannel Manifest

```bash
kubectl apply -f /tmp/flannel-install/kube-flannel.yml
```

This creates the `kube-flannel` namespace, ServiceAccount, ClusterRole,
ConfigMap, and DaemonSet in a single apply.

---

### Phase 7 — Stabilization Wait

Two checks run in sequence:

1. Polls for `kube-flannel` namespace creation (up to 120s, 2s interval)
2. Polls for DaemonSet readiness (up to 300s, 15s interval):

```bash
kubectl -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=5s
```

Prints elapsed time every 15 seconds. Exits with error if the DaemonSet is not
ready within 300 seconds.

---

### Phase 8 — Verification

```bash
kubectl -n kube-flannel get pods -l app=flannel
```

Confirms Flannel pods exist after install. A final `ok` banner is printed on success.

---

## Post-Install Checks

```bash
# All nodes should now show Ready
kubectl get nodes

# Flannel pods should be Running
kubectl -n kube-flannel get pods

# Flannel DaemonSet status
kubectl -n kube-flannel get ds kube-flannel-ds
```

---

## Flannel vs Calico — Quick Reference

| | Flannel | Calico |
|---|---|---|
| Install complexity | Low | High |
| NetworkPolicy support | No | Yes |
| Encapsulation | VXLAN only | VXLAN or IPIP |
| Operator required | No | Yes (Tigera) |
| Suitable for | Labs, simple clusters | Production, policy enforcement |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Unable to detect Pod CIDR` | Cluster not bootstrapped with kubeadm | Manually set CIDR in manifest |
| `kube-flannel namespace was not created` | `kubectl apply` failed silently | Re-check kubeconfig and cluster connectivity |
| `Flannel daemonset not ready within 300s` | Node resource contention | Check `kubectl -n kube-flannel describe ds kube-flannel-ds` |
| Nodes still `NotReady` after install | CIDR mismatch | Verify `kubectl -n kube-flannel get cm kube-flannel-cfg -o yaml` |
