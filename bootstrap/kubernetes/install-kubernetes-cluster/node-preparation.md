# Node Preparation

!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Phase 2 of 9** — Prepares every Linux node (control plane **and** workers) before any Kubernetes component is installed.

    **Prerequisite:** Phase 1 — cluster parameters must have been collected. This is done automatically by the entrypoint scripts.  
    **Next step:** [Container Runtime](container-runtime.md) — install containerd, runc, and crictl.

---

Three OS-level changes are required before Kubernetes can run on any node —
control plane or worker. These are applied in Phase 2 of both entrypoint
scripts and must complete successfully before the container runtime is
installed.

---

## Scripts

| Script | Path |
|---|---|
| Disable swap | `scripts/kubernetes/node/disable-swap.sh` |
| Load kernel modules | `scripts/kubernetes/node/load-kernel-modules.sh` |
| Apply sysctl parameters | `scripts/kubernetes/node/apply-sysctl.sh` |

All three are called sequentially by `init-controlplane.sh` and
`init-worker-node.sh`. They can also be run individually:

```bash
BASE="https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes"

curl -fsSL "$BASE/node/disable-swap.sh"        | sudo bash
curl -fsSL "$BASE/node/load-kernel-modules.sh" | sudo bash
curl -fsSL "$BASE/node/apply-sysctl.sh"        | sudo bash
```

---

## 1 — Disable Swap

**Why:** The kubelet refuses to start (or behaves unpredictably) when swap is
active. Kubernetes assumes memory limits are enforced by the Linux cgroups
hierarchy, which swap undermines.

**What the script does:**

1. Runs `swapoff -a` — disables all swap immediately (survives until reboot
   without the next step)
2. Removes any active swap entries from `/etc/fstab` using `sed` — makes
   the change permanent across reboots

**Verify after running:**

```bash
free -h          # Swap row should show 0
cat /etc/fstab   # No uncommented swap lines
```

!!! warning "Idempotent but not reversible during session"
    Running the script a second time is safe. `swapoff` returns non-zero if
    swap is already off — the script treats this as a warning, not a failure.

---

## 2 — Load Kernel Modules

**Why:** Two kernel modules are required by the container networking stack:

| Module | Purpose |
|---|---|
| `overlay` | Used by the overlayfs storage driver inside containers |
| `br_netfilter` | Allows iptables to see bridged network traffic — required for pod-to-pod communication rules |

Without `br_netfilter`, `net.bridge.bridge-nf-call-iptables = 1` (applied in
the next step) has no effect.

**What the script does:**

1. Writes `/etc/modules-load.d/k8s.conf` with both module names — ensures
   modules are loaded on every subsequent boot
2. Installs `kmod` if `modprobe` is not available
3. Runs `modprobe overlay` and `modprobe br_netfilter` — loads them
   immediately into the running kernel

**Verify after running:**

```bash
lsmod | grep overlay
lsmod | grep br_netfilter
cat /etc/modules-load.d/k8s.conf
```

---

## 3 — Apply sysctl Parameters

**Why:** Three kernel networking parameters must be set for Kubernetes
networking to function correctly.

| Parameter | Value | Purpose |
|---|---|---|
| `net.bridge.bridge-nf-call-iptables` | `1` | Ensures iptables processes bridged IPv4 traffic (pod networking rules) |
| `net.bridge.bridge-nf-call-ip6tables` | `1` | Same for IPv6 traffic |
| `net.ipv4.ip_forward` | `1` | Enables IP forwarding — required for pod-to-pod routing across nodes |

**What the script does:**

1. Writes the three parameters to `/etc/sysctl.d/k8s.conf`
2. Applies them immediately with `sysctl -p /etc/sysctl.d/k8s.conf`

**Verify after running:**

```bash
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
# All three should return = 1
```

---

## What Breaks If These Are Skipped

| Skipped step | Consequence |
|---|---|
| Swap not disabled | kubelet fails to start or `kubeadm init` preflight fails |
| `overlay` not loaded | containerd cannot use overlayfs — container starts fail |
| `br_netfilter` not loaded | Pod networking rules silently ignored — pods cannot communicate |
| `ip_forward` not set | Inter-node pod routing broken in multi-node clusters |

---

## Order Dependency

These three scripts have no dependency on each other and can run in any order.
The entrypoints run them in the order shown above for clarity, but the order
does not matter for correctness.
