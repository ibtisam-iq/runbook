# Deploy Metrics Server on Kubernetes

Metrics Server is a scalable, efficient in-cluster metrics aggregator. It collects resource usage data (CPU and memory) from kubelets across all nodes and exposes them through the Kubernetes Metrics API — enabling `kubectl top`, Horizontal Pod Autoscaler (HPA), and Vertical Pod Autoscaler (VPA) to function.

---

## Cluster-Specific Availability

Metrics Server is **not** available on all cluster types by default:

| Cluster Type | Metrics Server Available by Default? |
|---|---|
| `minikube` | No — enable via addon |
| `kind` | No — install manually |
| `kubeadm` / bare-metal | No — install manually |
| AWS EKS | No — install manually or enable as managed add-on |
| k3s | Yes — bundled |

---

## minikube

Enable Metrics Server as a built-in addon:

```bash
minikube addons enable metrics-server
```

Verify it is running:

```bash
minikube addons list | grep metrics-server
```

---

## kind

kind does not ship Metrics Server. Install it using the manifest method described in the [bare-metal section](#bare-metal--kubeadm) below.

---

## Bare-Metal / kubeadm

On bare-metal and kubeadm clusters, Metrics Server must be installed explicitly. Two installation methods are available.

### Option A — Helm

Add the Metrics Server Helm repository from [Artifact Hub](https://artifacthub.io/packages/helm/metrics-server/metrics-server):

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
```

Install the chart (latest available version: `3.13.1`):

```bash
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls"
```

!!! note "Why `--kubelet-insecure-tls`?"
    On bare-metal and kubeadm clusters, kubelets typically use self-signed certificates. Pass this flag to allow Metrics Server to scrape kubelet endpoints without certificate verification. Remove it when valid kubelet certificates are in place.

### Option B — Kubernetes Manifest

Apply the official release manifest directly from the [kubernetes-sigs/metrics-server](https://github.com/kubernetes-sigs/metrics-server) repository:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Patch the Deployment to add the `--kubelet-insecure-tls` argument (required on bare-metal):

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

---

## AWS EKS

On EKS, Metrics Server can be installed in two ways.

### Option A — Manual Install (Helm or Manifest)

Follow the same Helm or manifest steps from the [bare-metal section](#bare-metal--kubeadm) above. On EKS, kubelet certificates are valid, so **omit** the `--kubelet-insecure-tls` flag:

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system
```

Or via manifest:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Option B — EKS Managed Add-on (eksctl)

Install Metrics Server as a managed EKS add-on using `eksctl`:

```bash
eksctl create addon \
  --name metrics-server \
  --cluster $CLUSTER_NAME \
  --region $REGION
```

Verify the add-on status:

```bash
eksctl get addon \
  --name metrics-server \
  --cluster $CLUSTER_NAME \
  --region $REGION
```

!!! info "Managed Add-on Benefits"
    EKS managed add-ons are version-controlled and updated through the EKS API. AWS handles compatibility with the cluster version and applies security patches automatically.

---

## Verification

Confirm the Metrics Server pod is running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
```

Wait for the pod to reach `Running` state, then query node-level resource usage:

```bash
kubectl top nodes
```

Expected output:

```
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
control-plane  120m         6%     1024Mi          27%
worker-01      85m          4%     768Mi           20%
```

Query pod-level resource usage across all namespaces:

```bash
kubectl top pods -A
```

!!! warning "Allow time for data collection"
    Metrics Server requires approximately 60 seconds after startup before `kubectl top` returns data. If the command returns `error: metrics not available yet`, wait and retry.

---

## Troubleshooting

Check Metrics Server logs if `kubectl top` fails:

```bash
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=metrics-server \
  --tail=50
```

Confirm the `metrics.k8s.io` API is registered:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```

Expected output:

```
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        5m
```

An `AVAILABLE: False` status with a `TLS` error indicates the kubelet certificate issue — add `--kubelet-insecure-tls` as described above.

---

## Quick Reference

```bash
# --- minikube ---
minikube addons enable metrics-server

# --- Bare-Metal: Helm ---
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls"

# --- Bare-Metal: Manifest ---
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# --- EKS: Helm (no --kubelet-insecure-tls) ---
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm install metrics-server metrics-server/metrics-server --namespace kube-system

# --- EKS: Managed Add-on ---
eksctl create addon --name metrics-server --cluster <cluster-name> --region <region>

# --- Verify ---
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
kubectl top nodes
kubectl top pods -A
kubectl get apiservice v1beta1.metrics.k8s.io
```
