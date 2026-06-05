# Deploy Ingress-NGINX Controller

An **Ingress** is a Kubernetes API object that exposes HTTP/HTTPS routes from
outside the cluster to Services inside it. It lets to define path-based or
host-based routing rules in one place, rather than creating individual
LoadBalancer Services per application.

An Ingress object alone does nothing — it requires an **Ingress Controller**
to read those rules and configure the underlying proxy (NGINX, Traefik,
HAProxy, etc.) accordingly.

!!! warning "Ingress API is frozen — consider Gateway API for new projects"
    The Kubernetes project officially recommends using
    [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
    instead of Ingress. The Ingress API is generally available and will not be
    removed, but it is **no longer receiving new features or updates**.
    For greenfield deployments, evaluate Gateway API first.

    **References:**
    - [Ingress Controllers — Kubernetes Docs](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)
    - [Gateway API — Kubernetes Docs](https://kubernetes.io/docs/concepts/services-networking/gateway/)

---

## Available Ingress Controllers

Kubernetes does not ship a built-in Ingress Controller. Choose one based
on the use case. The most commonly used controllers are:

| Controller | Underlying Proxy | Best For | Maintained By |
|---|---|---|---|
| **ingress-nginx** | NGINX | General purpose, bare-metal, cloud | Kubernetes community |
| Traefik | Traefik | Dynamic config, Let's Encrypt native | Traefik Labs |
| AWS Load Balancer Controller | ALB / NLB | EKS-native workloads | AWS |
| HAProxy Ingress | HAProxy | High-performance, fine-grained control | HAProxy Technologies |
| Istio Ingress | Envoy | Service mesh environments | Istio community |
| Contour | Envoy | Multi-team clusters, HTTPProxy CRD | VMware / CNCF |

!!! note
    This runbook focuses exclusively on **ingress-nginx**, the community-maintained
    NGINX-based controller. It is the most widely used controller for both
    bare-metal and cloud clusters.

    **Reference:** [ingress-nginx Installation Guide](https://kubernetes.github.io/ingress-nginx/deploy/)

---

## How Platform Affects Deployment

The `ingress-nginx` controller is deployed differently depending on where the
cluster runs. The key difference is **how traffic enters the cluster**:

| Platform | Install Method | Service Type Created | External Access |
|---|---|---|---|
| **minikube** | `minikube addons enable ingress` | ClusterIP (addon-managed) | Via minikube tunnel |
| **Bare-metal / kubeadm** | `kubectl apply` (baremetal manifest) | `NodePort` (30000–32767) | `<NodeIP>:<NodePort>` |
| **AWS (EKS)** | `kubectl apply` (aws manifest) | `LoadBalancer` → NLB | AWS Network Load Balancer DNS |
| **GKE / Azure / DO** | `kubectl apply` (cloud manifest) | `LoadBalancer` | Cloud provider LB |
| **Helm (any platform)** | `helm upgrade --install` | Configurable | Depends on values |

!!! info "Why bare-metal uses NodePort"
    Cloud environments have a load balancer API that Kubernetes can call
    automatically when a `Service` of type `LoadBalancer` is created. Bare-metal
    servers have no such API. The baremetal manifest therefore uses `NodePort`,
    which binds a random high port (30000–32767) on every node. To expose ports 80/443 directly,
    deploy MetalLB — see [deploy-metallb-load-balancer.md](./deploy-metallb-load-balancer.md).

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` configured
- All nodes show `Ready` status:

```bash
kubectl get nodes
```

- Helm installed (optional — only needed for Helm-based install)

---

## Step 1 — Deploy the Controller

Choose the method that matches the environment.

### Option A — Manifest (Platform-Specific)

#### minikube

```bash
minikube addons enable ingress
```

#### Bare-metal / kubeadm (this runbook's primary target)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml
```

#### AWS (EKS)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/aws/deploy.yaml
```

#### GKE / Azure / Oracle Cloud / Other Cloud

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
```

---

### Option B — Helm (Any Platform)

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

!!! tip "Helm install is idempotent"
    Running the above command again on an already-installed controller will
    **upgrade** it, not duplicate it. Safe to re-run.

To inspect all available Helm values before installing:

```bash
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx
```

---

## Step 2 — Verify the Controller is Running

Wait for the controller pod to become ready (up to 2 minutes on first install —
two Jobs run to generate the admission webhook SSL certificate):

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

Then verify pods and the Service:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

!!! note "Expected output — bare-metal"
    The `ingress-nginx-controller` Service will show `TYPE: NodePort` and
    `EXTERNAL-IP: <none>`. This is correct — external access goes through
    `<NodeIP>:<NodePort>`.

!!! note "Expected output — cloud"
    The `ingress-nginx-controller` Service will show `TYPE: LoadBalancer` and
    an `EXTERNAL-IP` assigned by the cloud provider. DNS records for the
    applications should point to this IP or FQDN.

---

## Step 3 — Check the Controller Version

```bash
POD_NAMESPACE=ingress-nginx
POD_NAME=$(kubectl get pods -n $POD_NAMESPACE \
  -l app.kubernetes.io/name=ingress-nginx \
  --field-selector=status.phase=Running -o name)

kubectl exec $POD_NAME -n $POD_NAMESPACE -- /nginx-ingress-controller --version
```

---

### Firewall Requirements

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| `8443` | TCP | Between all cluster nodes | Admission webhook |
| `80` | TCP | Public → cluster nodes | HTTP traffic |
| `443` | TCP | Public → cluster nodes | HTTPS traffic |

!!! warning "GKE Private Clusters"
    On GKE private clusters, the control plane cannot reach port `8443` on
    worker nodes by default. Add a firewall rule explicitly:

    ```bash
    gcloud compute firewall-rules create allow-master-to-webhook \
      --allow tcp:8443 \
      --target-tags <node-tag>
    ```

---

### What Gets Created

Running the baremetal manifest creates the following resources:

- `Namespace`: `ingress-nginx`
- `Deployment`: `ingress-nginx-controller` (runs the NGINX proxy)
- `Service`: `ingress-nginx-controller` of type `NodePort`
- `Service`: `ingress-nginx-controller-admission` (webhook)
- `IngressClass`: `nginx` (set as cluster default)
- RBAC resources: `ClusterRole`, `ClusterRoleBinding`, `Role`, `RoleBinding`
- `ValidatingWebhookConfiguration`: validates Ingress objects on creation

!!! info
    The controller watches Ingress objects across **all namespaces** by default.
    To restrict it to a single namespace, set `--watch-namespace=<namespace>` in
    the controller args, or use `controller.scope` in Helm values.

---

## Step 4 — Use ingress-nginx in an Ingress Resource

Once the controller is running, reference it in Ingress manifests using
the `ingressClassName` field. This tells Kubernetes which controller should
handle this Ingress object.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <ingress-name>
  namespace: <namespace>
  annotations:
    # Optional: kept for compatibility with older controllers (pre-1.18)
    kubernetes.io/ingress.class: nginx
spec:
  ingressClassName: nginx       # Must match the IngressClass name
  rules:
    - host: <domain.com>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: <port>
```

Apply it:

```bash
kubectl apply -f <ingress-manifest>.yaml
```

Verify the Ingress received an address:

```bash
kubectl get ingress -n <namespace>
```

Expected output:

```
NAME             CLASS   HOSTS              ADDRESS         PORTS
<ingress-name>   nginx   <domain.com>       192.168.1.240   80, 443
```

!!! note "Where does the ADDRESS come from?"
    On **bare-metal with MetalLB**, the address is the IP assigned by MetalLB
    to the `ingress-nginx-controller` Service. On **cloud**, it is the cloud
    load balancer IP. On **minikube**, run `minikube tunnel` to populate it.

!!! tip "ingressClassName vs annotation"
    `spec.ingressClassName: nginx` is the current standard (Kubernetes ≥ 1.18).
    The annotation `kubernetes.io/ingress.class: nginx` is a legacy fallback.
    Both can coexist for backward compatibility, but prefer `ingressClassName`
    in all new manifests.

!!! warning "No IngressClass = controller ignores the Ingress"
    If `ingressClassName` is omitted and no IngressClass is marked as cluster
    default, the controller will silently ignore the Ingress object. Always
    specify `ingressClassName: nginx` explicitly to avoid this.
