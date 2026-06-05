# Install Calico

!!! abstract "Part of: [Install a CNI Plugin on Kubernetes](index.md)"
    **Calico installer** — Installs Calico using the Tigera Operator. Pod CIDR
    is auto-detected from the cluster. Encapsulation mode is prompted
    interactively (VXLAN default).

    **Prerequisite:** Kubernetes cluster running, kubeconfig configured, no
    existing CNI installed (or use the [dispatcher](index.md) to clean up first).

---

## Script

| Script | Path |
|---|---|
| `install-calico.sh` | `scripts/kubernetes/cni/install-calico.sh` |

Run directly (without the dispatcher):

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-calico.sh | sudo bash
```

---

## Defaults

| Parameter | Default | Notes |
|---|---|---|
| Calico version | Latest from GitHub API | Falls back to `v3.31.2` if API unreachable |
| Encapsulation mode | `VXLAN` | Prompted at Phase 4 — press Enter to keep default |
| Pod CIDR | Auto-detected | Read from `kube-system/kubeadm-config` ConfigMap |
| Working directory | `/tmp/calico-install` | Cleaned and recreated at each run |

---

## Installation Phases

### Phase 1 — Cluster Access Verification

Sources `ensure_kubeconfig` from the silver-stack library, then confirms
`kube-system` is reachable:

```bash
kubectl get ns kube-system
```

Exits immediately if the cluster is not accessible.

---

### Phase 2 — Pod CIDR Detection

Reads the Pod CIDR that was set during `kubeadm init` — the cluster itself is
the source of truth, not an environment variable:

```bash
kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' | grep podSubnet
```

Exits with an error if `podSubnet` cannot be parsed (e.g. cluster was not
bootstrapped with kubeadm).

---

### Phase 3 — Existing Calico Check

Checks for a live `Installation` CRD (`operator.tigera.io`):

```bash
kubectl get installation.operator.tigera.io default
```

If found, waits up to 60 seconds for automatic cleanup. If cleanup does not
complete within the timeout, the script prints manual recovery steps and exits.

---

### Phase 4 — Encapsulation Mode

Prompts the operator:

```
Encapsulation mode [VXLAN]:
```

Press **Enter** to keep `VXLAN`. Type `IPIP` (or any valid Calico
encapsulation value) to override. The value is patched directly into the
custom resources manifest at Phase 9.

---

### Phase 5 — Calico Version Resolution

Fetches the latest release tag from the GitHub API:

```bash
curl -fsSL https://api.github.com/repos/projectcalico/calico/releases/latest
```

Falls back to `v3.31.2` if the API is unreachable.

---

### Phase 6 — Workspace Preparation

Creates `/tmp/calico-install/`, removing any prior run's artifacts:

```bash
rm -rf /tmp/calico-install && mkdir -p /tmp/calico-install
```

---

### Phase 7 — Install Tigera Operator

Applies the operator CRDs and the operator itself in two sequential `kubectl create` calls:

```bash
kubectl create -f .../operator-crds.yaml
kubectl create -f .../tigera-operator.yaml
```

Both manifests are pulled from the official Calico release on GitHub at the
resolved version.

---

### Phase 8 — Download Custom Resources

Downloads the Calico `custom-resources.yaml` manifest to
`/tmp/calico-install/custom-resources.yaml` for patching:

```bash
curl -fsSL .../custom-resources.yaml -o /tmp/calico-install/custom-resources.yaml
```

---

### Phase 9 — Patch Custom Resources

Two `sed -i` substitutions are applied in-place before the manifest is
applied to the cluster:

| Field patched | Value source |
|---|---|
| `cidr:` | Pod CIDR detected in Phase 2 |
| `encapsulation:` | Encapsulation mode chosen in Phase 4 |

---

### Phase 10 — Apply Custom Resources

```bash
kubectl create -f /tmp/calico-install/custom-resources.yaml
```

This triggers the Tigera Operator to begin reconciling the Calico installation.

---

### Phase 11 — Stabilization Wait

Two readiness checks run in sequence:

1. Polls for `calico-system` namespace creation (up to 120s, 2s interval)
2. Waits for rollout readiness (up to 300s each):

```bash
kubectl -n calico-system rollout status deployment/calico-kube-controllers --timeout=300s
kubectl -n calico-system rollout status daemonset/calico-node --timeout=300s
```

Exits with error if either times out.

---

### Phase 12 — Verification

```bash
kubectl -n calico-system get pods
```

Confirms Calico pods exist post-install. A final `ok` banner is printed on success.

---

## Post-Install Checks

```bash
# All nodes should now show Ready
kubectl get nodes

# Calico pods should be Running
kubectl -n calico-system get pods

# Tigera operator should be Running
kubectl -n tigera-operator get pods
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Unable to detect Pod CIDR` | Cluster not bootstrapped with kubeadm | Manually set CIDR or use a kubeadm cluster |
| `calico-system namespace was not created` | Tigera Operator failed to start | Check `kubectl -n tigera-operator logs` |
| `Calico controllers failed to become ready` | Resource contention or wrong CIDR | Check events: `kubectl -n calico-system get events` |
| `existing Calico Installation detected` | Prior install not cleaned up | Run `reset-calico.sh` first, or use the [dispatcher](index.md) |
