# Kubeconfig and CNI Setup

After `kubeadm init` completes, the cluster is running but two manual steps
remain before it is usable: configuring `kubectl` access and installing a CNI
plugin. Neither is performed automatically by the entrypoint scripts.

---

## Scripts

| Script | Path |
|---|---|
| kubeconfig setup | `cluster/kubeconfig-helper.sh` |
| kubeconfig library | `lib/ensure_kubeconfig.sh` |
| CNI installer (dispatcher) | `cni/install-cni.sh` |
| Install Calico | `cni/install-calico.sh` |
| Install Flannel | `cni/install-flannel.sh` |

---

## Part 1 — kubeconfig Setup

### Why This Step Is Manual

`kubeadm init` writes `/etc/kubernetes/admin.conf` as root. Before `kubectl`
can be used as a normal user, this file must be copied to `~/.kube/config`
with correct ownership. `bootstrap-controlplane.sh` does not do this
automatically — it prints the helper URL instead and defers to the operator.

### Running the Helper

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cluster/kubeconfig-helper.sh | bash
```

When running as root (not via sudo), the script requires `--allow-root` to
proceed:

```bash
curl -fsSL .../cluster/kubeconfig-helper.sh | bash -s -- --allow-root
```

### What the Script Does

**User detection (sudo-aware):**

| Context | Detected user | kubeconfig written to |
|---|---|---|
| `sudo bash` | `$SUDO_USER` (the real user) | `/home/<user>/.kube/config` |
| `root` without sudo | `root` | `/root/.kube/config` (only with `--allow-root`) |
| Normal user | `$(whoami)` | `$HOME/.kube/config` |

**Steps:**

1. Detects the real user using `$SUDO_USER` when run via sudo
2. Prompts for confirmation before writing (shows which user will be configured)
3. Creates `~/.kube/` directory
4. Copies `/etc/kubernetes/admin.conf` to `~/.kube/config`
5. Sets ownership with `chown <user>:<user>` and permissions with `chmod 600`
6. Waits 10 seconds for the API server to stabilize, then runs `kubectl cluster-info`
7. Checks for CNI configuration in `/etc/cni/net.d/` — if absent, prints the
   CNI installer command

**Verify:**

```bash
kubectl cluster-info
kubectl get nodes
```

The node will show `NotReady` until a CNI plugin is installed. This is expected.

---

## Part 2 — CNI Installation

### Why CNI Is Required

Without a CNI plugin, pods cannot receive IP addresses and cannot communicate.
The node remains in `NotReady` state and the scheduler does not place any
workloads.

### Running the CNI Dispatcher

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-cni.sh | sudo bash
```

`install-cni.sh` runs a 5-phase safety flow before installing anything:

**Phase 1 — Cluster detection:**
Calls `ensure_kubeconfig` (from `lib/ensure_kubeconfig.sh`) then runs
`kubectl get ns kube-system`. If the cluster is not reachable, prints the
control plane init command and exits.

**Phase 2 — CNI binaries check:**
Checks if `/opt/cni/bin/` is populated. If not, runs
`runtime/install-cni-binaries.sh` automatically before proceeding.

**Phase 3 — Filesystem residue detection:**
Checks `/etc/cni/net.d/` for existing `.conf` or `.conflist` files.
If found, prompts to remove them before continuing to avoid CNI configuration
conflicts.

**Phase 4 — Active CNI pod detection:**
Checks for `calico-node` DaemonSet in `calico-system` and `kube-flannel-ds`
DaemonSet in `kube-flannel`. If either is found, requires typed `YES`
confirmation and then runs the corresponding reset script before proceeding.

**Phase 5 — CNI selection:**

```
1) Calico (default)
2) Flannel
0) Exit
```

---

### Calico (`install-calico.sh`)

Calico is installed via the **Tigera Operator** pattern.

**What the script does:**

1. Verifies cluster access
2. Detects Pod CIDR from the cluster's `kubeadm-config` ConfigMap
   (`kube-system/kubeadm-config` → `ClusterConfiguration.podSubnet`)
3. Checks for an existing `installation.operator.tigera.io/default` resource
   — if found, waits up to 60 seconds for it to be removed before continuing
4. Prompts for encapsulation mode (default: `VXLAN`, can override with `IPIP`)
5. Resolves the latest Calico version from GitHub API (fallback: `v3.31.2`)
6. Applies Tigera Operator CRDs:

    ```bash
    kubectl create -f .../operator-crds.yaml
    kubectl create -f .../tigera-operator.yaml
    ```

7. Downloads `custom-resources.yaml` to `/tmp/calico-install/`
8. Patches `cidr:` and `encapsulation:` fields using `sed`
9. Applies the patched manifest
10. Waits for `calico-system` namespace to appear
11. Waits for `calico-kube-controllers` Deployment and `calico-node` DaemonSet
    to become ready (timeout: 300 seconds each)

**Verify:**

```bash
kubectl -n calico-system get pods
kubectl get nodes   # Should show Ready
```

If the Tigera operator gets stuck on an existing `Installation/default`
resource, the script prints explicit manual recovery commands:

```bash
kubectl scale deployment tigera-operator -n tigera-operator --replicas=0
kubectl patch installation.operator.tigera.io default --type=json   -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl delete installation.operator.tigera.io default --grace-period=0 --force
```

---

### Flannel (`install-flannel.sh`)

Flannel is installed via a **manifest-patching** approach — simpler than
Calico's operator model.

**What the script does:**

1. Verifies cluster access
2. Detects Pod CIDR from `kubeadm-config` ConfigMap (same method as Calico)
3. Downloads the latest Flannel manifest from:
   `https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml`
4. Patches the `"Network":` value in the ConfigMap section of the manifest
   with the detected Pod CIDR using `sed`
5. Applies the patched manifest with `kubectl apply -f`
6. Waits for `kube-flannel` namespace to appear
7. Waits for `kube-flannel-ds` DaemonSet to be ready (timeout: 300 seconds,
   polled every 15 seconds)

**Verify:**

```bash
kubectl -n kube-flannel get pods -l app=flannel
kubectl get nodes   # Should show Ready
```

---

## Choosing Between Calico and Flannel

| Aspect | Calico | Flannel |
|---|---|---|
| Architecture | Tigera Operator + CRDs | Single manifest (DaemonSet + ConfigMap) |
| Network policy | Full Kubernetes NetworkPolicy + Calico-specific policies | Basic (no native NetworkPolicy enforcement) |
| Encapsulation | VXLAN (default) or IPIP | VXLAN |
| Complexity | Higher (operator, CRDs, namespaces: `calico-system`, `tigera-operator`) | Lower (single namespace: `kube-flannel`) |
| Reset complexity | High — CRDs, finalizers, interfaces, iptables chains | Moderate — namespace, interfaces, routes |
| Best for | Production, NetworkPolicy enforcement, multi-tenant | Simple clusters, labs, single-tenant |

---

## `ensure_kubeconfig` Library

`lib/ensure_kubeconfig.sh` is a helper function sourced by `install-cni.sh`,
`install-calico.sh`, and `install-flannel.sh`. It resolves the correct
`KUBECONFIG` path:

```bash
ensure_kubeconfig() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    export KUBECONFIG="$(getent passwd $SUDO_USER | cut -d: -f6)/.kube/config"
  else
    export KUBECONFIG="$HOME/.kube/config"
  fi
  [[ -f "$KUBECONFIG" ]] || error "Kubeconfig not found at: $KUBECONFIG"
}
```

This prevents `kubectl` from defaulting to `/root/.kube/config` when the CNI
scripts are run with `sudo`, which would cause cluster access failures if
kubeconfig was set up for a non-root user.
