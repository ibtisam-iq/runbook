# K3s Cluster

!!! abstract ""
    **Alternative path — Lightweight Kubernetes via K3s** — Installs a fully functional Kubernetes cluster using K3s, a single-binary distribution from Rancher. Use this instead of the kubeadm flow when a minimal footprint and fast bootstrap are needed.

    **Prerequisite:** A Linux server with `systemd`. No prior Kubernetes tooling required.

---

K3s packages the Kubernetes control plane, container runtime (containerd), and
several default components into a single binary. The installer script handles
everything from download to service registration.

---

## Install K3s

Run the official installer on the server node.

```bash
curl -sfL https://get.k3s.io | sh -
```

The installer downloads the K3s binary, registers a `systemd` service, and
starts the cluster automatically.

!!! info "Existing `kubectl` in PATH"
    If a system `kubectl` already exists at `/usr/bin/kubectl`, the installer skips
    creating a symlink at `/usr/local/bin/kubectl`. The system `kubectl` has no
    knowledge of K3s's kubeconfig and will fail until the kubeconfig is configured
    explicitly.

---

## Configure kubectl

The kubeconfig is written to `/etc/rancher/k3s/k3s.yaml` during installation.
Copy it to the standard location so `kubectl` can reach the cluster.

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
```

To persist the kubeconfig path across sessions, add it to the shell profile.

```bash
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

---

## Verify the Cluster

Check that the node is registered and ready.

```bash
kubectl get nodes
```

Confirm that the core system workloads are running.

```bash
kubectl get deploy -A
```

Check the default storage class.

```bash
kubectl get sc
```

Check the installed ingress class.

```bash
kubectl get ingressclass
```

---

## Default Components

K3s installs the following components automatically on every fresh cluster.

| Component | Purpose |
|---|---|
| `coredns` | Cluster DNS resolution |
| `local-path-provisioner` | Dynamic local persistent volumes |
| `metrics-server` | CPU and memory metrics via `kubectl top` |
| `traefik` | Default ingress controller |

!!! tip "Confirming installed deployments"
    ```bash
    kubectl get deploy -A
    ```
    All four deployments appear in `kube-system` and should be `1/1` within a
    minute of installation.

---

## Disable Default Components

Pass `--disable` flags to the installer to skip specific components at install
time.

```bash
# Disable Traefik (use when deploying a custom ingress controller)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -

# Disable local-path-provisioner (use when deploying a custom storage backend)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable local-storage" sh -

# Disable both
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable local-storage" sh -
```

!!! warning "Disable at install time"
    Components must be disabled during initial installation. Removing them from a
    running cluster requires uninstalling K3s and reinstalling with the appropriate
    flags.

---

## Add Worker Nodes

K3s runs as a single-node cluster by default. To expand it, join additional
nodes as agents.

**Step 1.** Retrieve the node token from the server.

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

**Step 2.** On each agent node, run the installer with the server URL and token.

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<SERVER_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  sh -
```

Replace `<SERVER_IP>` with the server node's IP address and `<NODE_TOKEN>` with
the token from Step 1.

**Step 3.** Verify the new node appears on the server.

```bash
kubectl get nodes
```

!!! note "Agent node kubeconfig"
    Agent nodes do not generate a kubeconfig. All `kubectl` interactions happen
    from the server node or from a remote machine with the server's kubeconfig.

---

## Uninstall K3s

The installer places an uninstall script on the system during setup.

```bash
# Uninstall the server node
/usr/local/bin/k3s-uninstall.sh

# Uninstall an agent node
/usr/local/bin/k3s-agent-uninstall.sh
```
