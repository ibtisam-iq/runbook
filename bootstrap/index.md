# Bootstrap

Installation runbooks for platform tools — from a raw Linux server to a fully
operational component, using only `curl | bash`. No local cloning required.

---

## What This Section Covers

Each runbook in this section documents how to install a specific platform tool
or component on a Linux server (EC2, bare-metal, VPS, microVM, or any cloud
instance). Scripts are hosted in
[silver-stack](https://github.com/ibtisam-iq/silver-stack) and designed to be
idempotent, version-aware, and safe to re-run.

---

## Kubernetes

| Runbook | What it does |
|---|---|
| [Install a Kubernetes Cluster with kubeadm](kubernetes/install-kubernetes-cluster/index.md) | Bootstraps a full kubeadm-based Kubernetes cluster on any Linux server — control plane init, worker join, CNI install |
| [Node Preparation](kubernetes/install-kubernetes-cluster/node-preparation.md) | Disables swap, loads kernel modules, applies sysctl — Phase 2 of 9 |
| [Container Runtime](kubernetes/install-kubernetes-cluster/container-runtime.md) | Installs containerd, runc, crictl, CNI binaries — Phases 3 & 4 |
| [Kubernetes Packages](kubernetes/install-kubernetes-cluster/kubernetes-packages.md) | Installs kubelet, kubeadm, kubectl with version pinning — Phases 5 & 6 |
| [Cluster Bootstrap](kubernetes/install-kubernetes-cluster/cluster-bootstrap.md) | Runs `kubeadm init`, joins workers — Phases 7–9 |
| [Kubeconfig & CNI](kubernetes/install-kubernetes-cluster/kubeconfig-and-cni.md) | Configures kubectl access, installs Calico or Flannel |
| [Maintenance & Reset](kubernetes/install-kubernetes-cluster/maintenance-and-reset.md) | Tears down cluster, removes CNI, rebuilds from scratch |
| [KinD Local Cluster](kubernetes/install-kubernetes-cluster/kind-local-cluster.md) | Local development cluster using KinD + Docker |
| [Architecture & Internals](kubernetes/install-kubernetes-cluster/kubernetes-overview.md) | Directory structure, script execution model, common.sh library |

---

## Components

Individual tool installers — standalone scripts for a single binary or service.
Content is being added.

---

!!! tip "How to use this section"
    Start with the top-level install page for the tool you need (e.g.
    **Install a Kubernetes Cluster with kubeadm**). It gives you the full
    end-to-end procedure. The sub-pages under each install are deep-dive
    references — read them when you want to understand what a specific phase
    does or troubleshoot a failure.
