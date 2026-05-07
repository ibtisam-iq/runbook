# KinD Local Cluster

The KinD (Kubernetes-in-Docker) path provides a local development cluster
without the full kubeadm bare-metal setup. It uses two declarative YAML
manifests to configure the cluster topology.

---

## Scripts and Manifests

| File | Path |
|---|---|
| Cluster creation script | `entrypoints/create-kind-cluster.sh` |
| Default CNI manifest | `manifests/kind-default.yaml` |
| Calico CNI manifest | `manifests/kind-calico.yaml` |

---

## Prerequisites

```bash
# Docker must be running
docker info

# kind CLI must be installed
kind version

# kubectl must be installed
kubectl version --client
```

---

## Running the Entrypoint

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/create-kind-cluster.sh | bash
```

The script prompts for a manifest choice and creates the cluster using
`kind create cluster --config <manifest>`.

---

## Manifest Comparison

| Feature | `kind-default.yaml` | `kind-calico.yaml` |
|---|---|---|
| Cluster name | `ibtisam` | `ibtisam` |
| Control plane nodes | 1 | 2 |
| Worker nodes | 1 | 2 |
| CNI | Default (Flannel — built-in) | Calico (must install manually) |
| `disableDefaultCNI` | `false` | `true` |
| Pod subnet | `10.244.0.0/16` | `10.244.0.0/16` |
| Service subnet | `10.96.0.0/12` | `10.96.0.0/12` |
| API server host port | `6444` | `6445` |
| NodePort host mappings | `3000` → `30000` | `8081` → `30000`, `30001–30010` (1:1) |

---

## `kind-default.yaml` — Single Control Plane + Default CNI

Designed for minimal local development. One control plane node and one worker
node run with Flannel as the default CNI (no additional setup required).

**Node layout:**

```
control-plane: ibtisam-iq    (kindest/node:v1.32.3)
worker:        worker         (kindest/node:v1.32.3)
```

**Port mappings on the control plane container:**

| Container port | Host port | Purpose |
|---|---|---|
| `6443` | `6444` | Kubernetes API server (avoids conflict with host port 6443) |
| `30000` | `3000` | NodePort service access from host |

**Global kubeadm patch:**

```yaml
kind: ClusterConfiguration
apiServer:
  extraArgs:
    authorization-mode: Node,RBAC
```

**containerd patch:**

```toml
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"
```

**Start the cluster:**

```bash
kind create cluster --config manifests/kind-default.yaml
kubectl cluster-info --context kind-ibtisam
kubectl get nodes
```

---

## `kind-calico.yaml` — Multi-Node HA + Calico CNI

Designed for testing NetworkPolicy, multi-node scheduling, and HA control plane
scenarios. The default CNI is disabled so Calico can be installed after cluster
creation.

**Node layout:**

```
control-plane: ibtisam-iq    (kindest/node:v1.32.3)
control-plane: ibtisam-x     (kindest/node:v1.32.3)
worker:        worker-a       (kindest/node:v1.32.3)
worker:        worker-b       (kindest/node:v1.32.3)
```

**Port mappings on the first control plane container:**

| Container port | Host port |
|---|---|
| `6443` | `6445` |
| `30000` | `8081` |
| `30001–30010` | `30001–30010` (1:1 passthrough) |

The 1:1 passthrough mappings (`30001–30010`) allow direct NodePort access from
the host using `curl http://<host-ip>:30001/` without port translation.

**Create the cluster:**

```bash
kind create cluster --config manifests/kind-calico.yaml
```

**Install Calico after cluster creation:**

Because `disableDefaultCNI: true` is set, nodes remain `NotReady` until Calico
is installed. Use the silver-stack CNI installer:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/cni/install-cni.sh | sudo bash
# Select: 1) Calico
```

Or apply Calico directly (the manifest comments in `kind-calico.yaml` show the
manual approach with CIDR patching):

```bash
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
sed -i 's/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/' calico.yaml
sed -i 's/#   value: "192.168.0.0\/16"/  value: "10.244.0.0\/16"/' calico.yaml
kubectl apply -f calico.yaml
```

**Verify Calico is ready:**

```bash
kubectl -n calico-system get pods
kubectl get nodes   # All nodes should show Ready
```

---

## Cluster Management

```bash
# List clusters
kind get clusters

# Delete a cluster
kind delete cluster --name ibtisam

# Export kubeconfig
kind export kubeconfig --name ibtisam

# Get nodes (Docker containers)
docker ps --filter label=io.x-k8s.kind.cluster=ibtisam
```

---

## KinD vs kubeadm

| Aspect | KinD | kubeadm (bare-metal/VM) |
|---|---|---|
| Infrastructure | Docker containers | Physical/virtual machines |
| Setup time | Seconds | 5–15 minutes |
| Persistence | Lost when containers are deleted | Persistent |
| Use case | Local dev, CI pipelines, testing | Staging, production |
| CNI options | Default (Flannel) or Calico | Calico or Flannel via silver-stack |
| NetworkPolicy testing | Yes (with Calico manifest) | Yes (with Calico) |
