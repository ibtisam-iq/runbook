# Install a Kubernetes Cluster with kubeadm

Spin up a production-grade Kubernetes cluster on **any Linux server** — VM, EC2, bare-metal, microVM, or cloud VPS — with a single `curl | bash` command.

No local cloning. No manual step-by-step guides. No forgetting to disable swap.

---

## The Problem This Solves

Setting up Kubernetes with kubeadm is not one command. It is 30+ manual steps
spread across the official documentation: disable swap, load kernel modules,
set sysctl parameters, install containerd, configure its cgroup driver, install
runc, install crictl, add the Kubernetes APT repo, pin versions, run kubeadm
init, configure kubectl, install a CNI — and if you miss one step or run them
in the wrong order, the cluster silently breaks or never comes up at all.

**SilverStack fills the gap:** a fully automated, idempotent, version-aware
bash automation layer that bootstraps a real upstream Kubernetes cluster via
kubeadm on any server you own or rent.

---

## Who Is This For

- A DevOps engineer who spun up an EC2 instance, a Hetzner VPS, or a DigitalOcean
  Droplet and needs a real Kubernetes cluster in minutes for testing Ingress,
  Gateway API, Helm charts, or service mesh configurations
- Anyone running a disposable lab on iximiuz, Killercoda, or a local microVM
  who does not want to re-type 30 steps every time
- Someone who wants to understand what a proper kubeadm bootstrap actually does
  — this code is readable, every phase is labeled, every decision is explained

> **Not for production.** This is a lab and learning tool. The scripts are
> designed for fresh, disposable servers. They assume you are the owner and
> root on the machine.

---

## Requirements

| Requirement | Details |
|---|---|
| OS | Ubuntu 22.04 or 24.04 (Debian-based) |
| Architecture | `x86_64` (amd64) or `aarch64` (arm64) |
| RAM | 2 GB minimum per node (4 GB recommended for control plane) |
| CPU | 2 vCPUs minimum |
| Disk | 20 GB free |
| Network | Outbound internet access (to download packages) |
| User | Root or sudo access |
| Existing cluster | None (the script detects and safely resets existing state) |

---

## Quick Start — Two Commands for a Full Cluster

### Step 1 — Initialize the Control Plane

Run this on the node that will be your control plane:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-controlplane.sh | sudo bash
```

The script will:

1. Ask you 5 questions (your node IP, Kubernetes version, hostname, Pod CIDR,
   containerd install method) — all have sensible defaults, just press Enter
2. Disable swap, load kernel modules, apply sysctl settings
3. Install containerd with the correct cgroup driver configuration
4. Resolve the exact patch version for your chosen Kubernetes minor version
5. Install kubelet, kubeadm, kubectl, helm, and k9s
6. Detect and safely clean any existing Kubernetes state
7. Run `kubeadm init` with all required flags
8. Print the `kubeadm join` token for your worker nodes

**Total time:** 5–10 minutes on a fresh server with good internet.

After it finishes, run the kubeconfig helper (as your normal user, not root):

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cluster/kubeconfig-helper.sh | bash
```

Then install a CNI plugin so your nodes become Ready:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-cni.sh | sudo bash
# Choose: 1) Calico  or  2) Flannel
```

### Step 2 — Join Worker Nodes

Run this on each worker node, then run the `kubeadm join ...` command that
`init-controlplane.sh` printed at the end:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-worker-node.sh | sudo bash
# Then paste the kubeadm join command from the control plane output
```

### Verify

```bash
kubectl get nodes          # All nodes should be Ready
kubectl get pods -A        # All system pods should be Running
kubectl cluster-info
```

---

## Local Development — KinD Cluster

If you are on your laptop and Docker is already running, use the KinD path
instead — no server required:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/create-kind-cluster.sh | bash
```

Two cluster configurations are available:

| Manifest | Topology | CNI | Best for |
|---|---|---|---|
| `kind-default.yaml` | 1 control plane + 1 worker | Flannel (built-in) | Quick local testing |
| `kind-calico.yaml` | 2 control planes + 2 workers | Calico (manual post-install) | NetworkPolicy, HA topology testing |

> **Prerequisites:** Docker Desktop or Docker Engine running locally, `kind`
> CLI installed, `kubectl` installed.

---

## Dry Run Mode

Every script accepts `--dry-run`. In this mode the script runs all preflight
checks, resolves versions, and prints what it would do — but makes no system
changes.

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-controlplane.sh | sudo bash -s -- --dry-run
```

Use this to validate that your server meets all requirements before committing
to the full install.

---

## What Gets Installed

### On Every Node (control plane and workers)

| Component | Version strategy | Why |
|---|---|---|
| `containerd` | Package method: Docker's `containerd.io` APT repo | Stable, bundled runc, industry standard |
| `runc` | Bundled with containerd.io (or binary if binary method chosen) | OCI container runtime |
| `crictl` | Pinned (`v1.30.0`) | CRI debugging tool |
| CNI binaries | Pinned (`v1.9.0`) | Low-level networking primitives |
| `kubelet` | Exact patch version, `apt-mark hold` | Cluster node agent |
| `kubeadm` | Exact patch version, `apt-mark hold` | Cluster bootstrap tool |

### Control Plane Only (additional)

| Component | Install method | Why |
|---|---|---|
| `kubectl` | Same APT repo as kubelet | Cluster management CLI |
| `helm` | Official Helm installer script (Helm 4) | Kubernetes package manager |
| `k9s` | Binary from GitHub releases (`v0.50.16`) | Terminal-based cluster UI |

---

## How Version Pinning Works

You provide a `MAJOR.MINOR` string (e.g. `1.36`). The scripts:

1. Query `https://dl.k8s.io/release/stable-1.36.txt` to get the exact patch
   version (`v1.36.0`)
2. Convert it to the Debian package revision (`1.36.0-1.1`)
3. Install `kubelet=1.36.0-1.1` and `kubeadm=1.36.0-1.1` — no floating
   version installs
4. Run `apt-mark hold` on both — prevents accidental upgrade

This means your cluster will never silently move to a new patch version.

---

## CNI Options

Two CNI plugins are supported. The script prompts you to choose after
`kubeadm init`.

### Calico (recommended for most cases)

Installed via the **Tigera Operator**. Supports full Kubernetes NetworkPolicy
plus Calico-native policies.

- The script auto-detects your Pod CIDR from the cluster's ConfigMap — no
  manual CIDR editing
- Supports VXLAN (default) or IPIP encapsulation
- Resolves the latest stable Calico version automatically

```bash
kubectl -n calico-system get pods   # Verify
kubectl get nodes                   # Should show Ready
```

### Flannel (simpler, no NetworkPolicy)

Installed via a patched manifest. Good for single-tenant labs where
NetworkPolicy enforcement is not needed.

```bash
kubectl -n kube-flannel get pods    # Verify
kubectl get nodes                   # Should show Ready
```

---

## Resetting a Cluster

To wipe the cluster and start fresh (useful in disposable labs):

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/maintenance/reset-cluster.sh | sudo bash
```

The script:
1. Requires typed `YES` confirmation — will not run silently
2. Stops kubelet
3. Runs `kubeadm reset -f`
4. Removes `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`, `~/.kube`
5. Detects and kills any orphaned `kube-apiserver` process
6. Leaves containerd installed but stopped — ready for the next init

> After reset, run `init-controlplane.sh` again. CNI binaries, OS prerequisites
> (swap, sysctl), and installed binaries (kubectl, helm, k9s) are **not**
> removed by reset and do not need to be re-installed.

---

## Safety Features

These are things the scripts do that manual guides do not:

| Feature | How it works |
|---|---|
| **Existing cluster detection** | Before running `kubeadm init`, scans for running API servers, etcd, occupied ports (6443, 2379, 10250). Offers safe reset if found. Will not blindly overwrite. |
| **Sudo-aware kubeconfig** | Detects `$SUDO_USER` to configure kubeconfig for the real user, not root. |
| **Version skew guard** | The advanced cluster parameters wizard refuses to install a version more than one minor step away from what is already installed. |
| **Idempotent installs** | All binary installers check if the binary exists before downloading. Re-running a script on a partially provisioned node is safe. |
| **CNI conflict detection** | The CNI installer detects existing CNI configs and running CNI pods before installing a new one. Prompts for cleanup first. |
| **Dry run mode** | Every script supports `--dry-run` — validates without modifying the system. |

---

## Known Limitations

| Limitation | Detail |
|---|---|
| Ubuntu/Debian only | Scripts use `apt-get` and Debian package format. CentOS, RHEL, and Fedora are not supported. |
| `reset-calico.sh` and `reset-flannel.sh` are incomplete | Both scripts currently exit early without running their cleanup logic. Manual cleanup commands are documented in the [Maintenance & Reset runbook](./maintenance-and-reset.md). |
| No HA control plane setup | The `--upload-certs` flag is passed to `kubeadm init` (enabling future HA joins), but the scripts do not automate joining a second control plane node. |
| No offline/air-gapped mode | All scripts download from the internet at runtime. Air-gapped environments are not supported. |
| Single-OS tested | Tested on Ubuntu 22.04 and 24.04. Behaviour on other Debian-based distributions is not guaranteed. |

---

## Under the Hood

The automation is organized into clearly separated layers:

```
entrypoints/     ← Start here. Two scripts: control plane and worker.
cluster/         ← kubeadm init logic, cluster parameters wizard, safety guards
node/            ← OS prerequisites: swap, kernel modules, sysctl
runtime/         ← containerd, runc, crictl, CNI binaries
packages/        ← kubelet, kubeadm, kubectl, helm, k9s — with version pinning
cni/             ← Calico and Flannel installers
maintenance/     ← Reset scripts
manifests/       ← KinD cluster YAML configurations
lib/             ← Shared library: logging, remote execution, kubeconfig helpers
```

For a deep dive into what each script does, see the internal runbooks:

- [Node Preparation](node-preparation.md)
- [Container Runtime](container-runtime.md)
- [Kubernetes Packages](kubernetes-packages.md)
- [Cluster Bootstrap](cluster-bootstrap.md)
- [Kubeconfig & CNI](kubeconfig-and-cni.md)
- [Maintenance & Reset](maintenance-and-reset.md)
- [KinD Local Cluster](kind-local-cluster.md)

---

## Source

All scripts are open source and available at:

**[github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack)**

`scripts/kubernetes/` is the root of everything described on this page.
