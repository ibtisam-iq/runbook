# Maintenance and Reset

Three reset scripts handle different scopes of cleanup: full cluster teardown,
Calico CNI removal, and Flannel CNI removal. All are destructive and
irreversible. They are designed for lab rebuilds, re-provisioning, or CNI
replacement — not for production incident recovery.

---

## Scripts

| Script | Scope | Path |
|---|---|---|
| `maintenance/reset-cluster.sh` | Full Kubernetes node reset | Complete |
| `maintenance/reset-calico.sh` | Calico CNI removal | Kubernetes + OS-level |
| `maintenance/reset-flannel.sh` | Flannel CNI removal | Kubernetes + OS-level |

---

## When to Use Each Script

| Scenario | Script |
|---|---|
| Rebuild the entire cluster from scratch | `reset-cluster.sh` |
| Replace Calico with Flannel (or remove Calico) | `reset-calico.sh` |
| Replace Flannel with Calico (or remove Flannel) | `reset-flannel.sh` |
| `detect-existing-cluster.sh` found strong indicators | `reset-cluster.sh` (run automatically) |
| `install-cni.sh` detected existing CNI | `reset-calico.sh` or `reset-flannel.sh` (run automatically) |

---

## Full Cluster Reset (`reset-cluster.sh`)

!!! danger "DESTRUCTIVE"
    This script permanently removes all Kubernetes data, certificates, and
    state from the node. Run on control plane nodes with extreme care. Data
    cannot be recovered after this script completes.

**Invocation:**

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/maintenance/reset-cluster.sh | sudo bash
```

The script requires typed confirmation before proceeding:

```
Type 'YES' to confirm full cluster destruction
```

**What the script does:**

**Step 1 — Stop kubelet:**

kubelet is stopped before `kubeadm reset` runs. containerd is intentionally
kept running because `kubeadm reset` uses the CRI to clean up containers and
sandboxes. Stopping containerd first would leave orphaned containers that
`kubeadm reset` cannot clean.

**Step 2 — `kubeadm reset -f`:**

`kubeadm reset` is the authoritative cleanup mechanism. It:

- Drains and unconfigures the node
- Removes kubeadm-managed static pod manifests
- Cleans up the kubelet configuration
- Removes certificates managed by kubeadm

The `-f` flag skips the interactive confirmation (the script already prompted
the operator).

**Step 3 — Remove residual directories:**

`kubeadm reset` does not remove all directories. The script removes the
remainder explicitly:

```bash
/etc/kubernetes        # All config, manifests, PKI
/var/lib/kubelet       # kubelet data
/var/lib/etcd          # etcd data (most critical)
~/.kube                # User kubeconfig
```

**Step 4 — Orphaned kube-apiserver check:**

If containerd was stopped before `kubeadm reset` ran (e.g. from a previous
failed attempt), the kube-apiserver process may remain running on port `6443`
as an orphan with no CRI ownership. The script checks for this with
`ss -ltnp | grep ':6443'` and terminates the process with `kill` or `kill -9`.

**Step 5 — Stop containerd:**

containerd is stopped last. A note is left in the log:

```
containerd left stopped intentionally
It will be started by the next silver-stack phase
```

This ensures the next run of `ensure-k8s-services.sh` starts containerd
cleanly as part of the new provisioning sequence.

**Post-reset state:**

- No Kubernetes processes running
- No `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`
- No user kubeconfig
- containerd installed but stopped
- kubelet installed but stopped
- CNI binaries still present in `/opt/cni/bin/` (not removed)
- OS prerequisites (swap, kernel modules, sysctl) still applied (not removed)

The node is ready for a fresh `init-controlplane.sh` run.

---

## Calico Reset (`reset-calico.sh`)

!!! warning "Work In Progress"
    `reset-calico.sh` currently exits at line 2 with `exit 0` before executing
    its cleanup logic. The full removal sequence exists in the file as commented
    working code. The complete removal is invoked manually using the commands
    below until this script is promoted.

**What a full Calico reset covers (when the script is complete):**

**Kubernetes layer:**

1. Scales `tigera-operator` Deployment to 0 replicas (stops reconciliation)
2. Removes finalizers from all resources in `calico-system` (pods, DaemonSets, Deployments)
3. Force-deletes all resources in `calico-system`
4. Patches and force-deletes `installation.operator.tigera.io/default`
5. Deletes `tigera-operator` Deployment
6. Deletes RoleBindings, ClusterRoleBindings, ClusterRoles, ServiceAccounts
7. Deletes all Tigera and projectcalico CRDs
8. Force-deletes `tigera-operator` and `calico-system` namespaces

**OS layer (run on every node):**

```bash
# Remove Calico CNI config files
sudo rm -f /etc/cni/net.d/10-calico.conflist /etc/cni/net.d/calico-kubeconfig

# Delete Calico network interfaces
sudo ip link delete vxlan.calico 2>/dev/null || true
sudo ip link list | grep -o 'cali[^[:space:]]*' | xargs -r -I {} sudo ip link delete {}

# Delete CNI and pod network namespaces
sudo ip netns list | grep -E 'cni-|cali-' | awk '{print $1}' | xargs -r ip netns delete

# Flush Calico iptables chains (filter, nat, mangle tables)
for table in filter nat mangle; do
  chains=$(sudo iptables -t "$table" -L | grep '^Chain cali-' | awk '{print $2}')
  for chain in $chains; do
    sudo iptables -t "$table" -F "$chain"
    sudo iptables -t "$table" -X "$chain"
  done
done

# Restart kubelet
sudo systemctl restart kubelet
```

**Verify after manual cleanup:**

```bash
kubectl get ns | grep -E '(calico-system|tigera-operator)'  # Should return nothing
kubectl get crd | grep -E '(tigera|projectcalico)'          # Should return nothing
ip link | grep cali                                          # Should return nothing
```

---

## Flannel Reset (`reset-flannel.sh`)

!!! warning "Work In Progress"
    `reset-flannel.sh` also exits early (`exit 0` at line 7) before its cleanup
    logic runs. The complete idempotent removal sequence exists below the early
    exit and is ready to be promoted.

**What the full Flannel reset covers (when promoted):**

**Detection:**

Checks for `kube-flannel` namespace (Kubernetes) and `flannel.1` interface
(OS). If neither is found, exits cleanly with "nothing to remove."

**Kubernetes layer:**

1. Deletes the `kube-flannel` namespace (with `--wait=true`)
2. Removes Flannel annotations from all nodes:
   `flannel.alpha.coreos.com/backend-data`, `backend-type`, `public-ip`

**OS layer:**

```bash
# Stop kubelet temporarily
sudo systemctl stop kubelet

# Remove CNI config
sudo rm -f /etc/cni/net.d/*flannel* /etc/cni/net.d/10-flannel.conflist

# Delete Flannel network interfaces
for iface in flannel.1 cni0 tunl0; do
  sudo ip link delete "$iface"
done

# Remove Flannel routes (10.244.x.x)
ip route | grep -E '10\.244\.' | while read -r route; do ip route del $route; done

# Remove CNI network namespaces
ip netns list | awk '{print $1}' | grep '^cni-' | while read -r ns; do ip netns delete "$ns"; done

# Remove Flannel filesystem state
sudo rm -rf /var/lib/cni/flannel /var/lib/cni/networks/10.244.0.0* /run/flannel /etc/flannel

# Restart kubelet
sudo systemctl start kubelet
```

**Verify after cleanup:**

```bash
ip link                   # No flannel.1, cni0
ip route                  # No 10.244.x routes
ls /etc/cni/net.d/        # No flannel files
kubectl get pods -A       # No kube-flannel pods
```
