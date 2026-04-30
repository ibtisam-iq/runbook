# Kubernetes Gateway API - Complete Setup Guide

## About This Guide

The Kubernetes Gateway API is a **spec** - a set of CRDs (`GatewayClass`, `Gateway`, `HTTPRoute`) defined by the Kubernetes project. The spec itself does nothing. It needs a **controller** - a concrete implementation - to actually process those resources and serve traffic.

Multiple controllers implement the Gateway API spec:

| Controller | Maintained by | Notes |
|---|---|---|
| **NGINX Gateway Fabric** | F5 / NGINX | Gateway API native, familiar nginx core |
| **Envoy Gateway** | CNCF / Envoy | Most complete Gateway API support, production-grade |
| **Traefik** | Traefik Labs | Supports both Ingress and Gateway API simultaneously |
| **Kong** | Kong Inc. | API gateway features on top of Gateway API |
| **Istio** | CNCF | Full service mesh + Gateway API support |
| **Contour** | VMware | Lightweight, envoy-based |

All of them are valid. You pick one based on your requirements.

> **This guide covers two controllers specifically: NGINX Gateway Fabric and Envoy Gateway.** Traefik, Kong, Istio, and others follow the same Gateway API concepts but have their own installation steps - refer to their official documentation for those.

**Why does the controller choice matter so early?**
Because it affects the installation sequence itself - not just YAML values. Some controllers bundle Gateway API CRDs inside their Helm chart; others require you to install CRDs separately first. Some auto-create the `GatewayClass`; others require you to apply it manually. The table below in the [Controller Choice Changes Both Steps](#controller-choice-changes-both-steps) section maps out exactly what differs between the two controllers covered here.

---

## Conceptual Overview

The Gateway API is the modern successor to the `Ingress` API. Before touching any commands, understand the three-resource model that everything builds on:

```
┌─────────────────────────────────────────────────────────────┐
│                    Gateway API Stack                        │
│                                                             │
│  GatewayClass  →  "which controller handles this?"          │
│  Gateway       →  "what ports/hostnames/TLS to expose?"     │
│  HTTPRoute     →  "how to route requests to backends?"      │
└─────────────────────────────────────────────────────────────┘
```

These three resources depend on each other in sequence - a `Gateway` references a `GatewayClass`, and an `HTTPRoute` references a `Gateway`. None of them work standalone.

---

## What You Need to Install

Two things must be installed on the cluster before you can create any of those three resources:

```
Installation Layer
├── 1. Gateway API CRDs        ← teaches Kubernetes what GatewayClass/Gateway/HTTPRoute ARE
└── 2. Gateway Controller      ← the actual proxy that IMPLEMENTS those resources
```

**Why CRDs first?** Kubernetes rejects any `kubectl apply` for a resource kind it doesn't recognize. The Gateway API CRDs register `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, etc. as valid kinds in the cluster. Without them, even `kubectl apply -f gateway.yaml` fails with `no matches for kind "Gateway"`.

**Why a controller?** CRDs alone are just schema definitions - they teach Kubernetes the vocabulary but nothing acts on it. The controller watches for `Gateway` resources and spins up actual proxy pods (NGINX or Envoy) that serve real traffic.

---

## Controller Choice Changes Both Steps

This is the most important thing to understand before running any command:

| | NGINX Gateway Fabric (NGF) | Envoy Gateway |
|---|---|---|
| **Gateway API CRDs** | ❌ Install separately first | ✅ Bundled inside Helm chart |
| **GatewayClass** | ✅ Auto-created (name: `nginx`) | ❌ You must apply it manually |
| **Install namespace** | `nginx-gateway` | `envoy-gateway-system` |
| **`gatewayClassName`** in your YAML | `nginx` | `eg` |
| **Proxy service name** | `ngf-nginx-gateway-fabric` (static) | `envoy-<namespace>-<gateway>-<hash>` (dynamic per Gateway) |

---

## Installation: NGINX Gateway Fabric

> **Official docs:** https://docs.nginx.com/nginx-gateway-fabric/install/helm/

### Step 1 - Install Gateway API CRDs

NGF does **not** bundle CRDs. Install them using NGF's version-pinned reference so the CRD version matches the controller exactly:

```bash
kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.5.1" \
  | kubectl apply -f -
```

> **Why NGF's URL and not the upstream one?**
> The upstream CRD repo (`kubernetes-sigs/gateway-api`) and NGF may be on different release cadences. Using NGF's pinned reference guarantees compatibility between CRD schema version and the controller's expected API version.

Verify:
```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected Output:
```text
ibtisam@dev-machine:~ $ k get crd | grep gateway.networking.k8s.io
backendtlspolicies.gateway.networking.k8s.io            2026-04-28T11:20:25Z
gatewayclasses.gateway.networking.k8s.io                2026-04-28T11:20:25Z
gateways.gateway.networking.k8s.io                      2026-04-28T11:20:25Z
grpcroutes.gateway.networking.k8s.io                    2026-04-28T11:20:25Z
httproutes.gateway.networking.k8s.io                    2026-04-28T11:20:26Z
listenersets.gateway.networking.k8s.io                  2026-04-28T11:20:26Z
referencegrants.gateway.networking.k8s.io               2026-04-28T11:20:26Z
tlsroutes.gateway.networking.k8s.io                     2026-04-28T11:20:26Z
```

### Step 2 - Install NGF Controller

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace \
  -n nginx-gateway \
  --set nginx.service.type=NodePort    # required for bare-metal (explained below)
```

Wait for it to be ready:
```bash
kubectl rollout status deployment/ngf-nginx-gateway-fabric -n nginx-gateway
```

#### Step 3 - Verify GatewayClass (Auto-Created)

NGF automatically creates a `GatewayClass` named `nginx` on startup. Verify it was accepted by the cluster:

```bash
kubectl get gatewayclass nginx
# NAME    CONTROLLER                                   ACCEPTED   AGE
# nginx   gateway.nginx.org/nginx-gateway-controller   True       30s
```

`ACCEPTED=True` means the controller is running and has claimed this class. Any `Gateway` you create with `gatewayClassName: nginx` will now be handled by NGF.

---

## Installation: Envoy Gateway

> **Official docs:** https://gateway.envoyproxy.io/docs/tasks/quickstart/#installation

### Step 1 - Install (CRDs + Controller in one command)

Envoy Gateway bundles Gateway API CRDs inside its Helm chart:

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  -n envoy-gateway-system \
  --create-namespace
```

Wait:
```bash
kubectl rollout status deployment/envoy-gateway -n envoy-gateway-system
```

### Step 2 - Create GatewayClass (Manual - not auto-created)

Unlike NGF, Envoy does **not** create a `GatewayClass` automatically:

```bash
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
```

Verify:
```bash
kubectl get gatewayclass eg
# NAME   CONTROLLER                                         ACCEPTED
# eg     gateway.envoyproxy.io/gatewayclass-controller     True
```

---

## Bare-Metal: The NodePort Problem

On bare-metal or any cluster without a cloud load balancer, the Gateway controller's Service stays in `<pending>` external IP forever if left as `LoadBalancer` type. With `NodePort`, it gets assigned high-range ports (e.g., `30080`, `31443`) - but external traffic arrives on standard ports `80` and `443`.

**Where to find your NodePorts:**

```bash
# For NGF
kubectl get svc -n nginx-gateway
# NAME                          TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)
# ngf-nginx-gateway-fabric      NodePort   10.96.x.x     <none>        80:30XXX/TCP,443:31XXX/TCP

# For Envoy - service name is dynamic, created per Gateway resource
kubectl get svc -n envoy-gateway-system
# NAME                                       TYPE       PORT(S)
# envoy-bankapp-bankapp-gateway-<hash>       NodePort   80:30XXX/TCP,443:31XXX/TCP
```

> **Which node's IP to use?**
> In a single-node cluster (bare-metal/EC2 kubeadm), there is only one node - use `hostname -I` or `curl ifconfig.me` for the public IP. In a multi-node cluster, the NodePort is open on **every** node. Use the IP of the node that is your public-facing entry point, or apply iptables rules on all nodes that can receive external traffic.

---

## Bare-Metal: Two Fix Methods

### Method A - iptables Port Forwarding

Intercepts packets at the network layer before they reach any process. Traffic arriving on port `80` is redirected to the NodePort. The proxy pod never knows the difference - it still binds to the NodePort, iptables does the translation transparently.

```bash
# Replace 30080 and 31443 with your actual NodePorts from above
HTTP_NODEPORT=30080
HTTPS_NODEPORT=31443

sudo iptables -t nat -A PREROUTING -p tcp --dport 80  -j REDIRECT --to-port $HTTP_NODEPORT
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port $HTTPS_NODEPORT

# Persist across reboots
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

Verify rules were added:
```bash
sudo iptables -t nat -L PREROUTING -n --line-numbers
```

---

### Method B - `hostNetwork: true` Patch

Makes the proxy pod bind directly to ports `80` and `443` on the host's network interface. No NodePort involved - traffic goes straight to the pod. This eliminates the translation layer entirely.

Two ways to apply this patch - both produce the same result:

#### Option 1: kubectl patch (imperative - instant, no YAML file needed)

```bash
# For NGF
kubectl patch deployment ngf-nginx-gateway-fabric -n nginx-gateway \
  --type=json \
  -p='[
    {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
    {"op": "add", "path": "/spec/template/spec/dnsPolicy",  "value": "ClusterFirstWithHostNet"}
  ]'

# For Envoy Gateway
kubectl patch deployment envoy-gateway -n envoy-gateway-system \
  --type=json \
  -p='[
    {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true},
    {"op": "add", "path": "/spec/template/spec/dnsPolicy",  "value": "ClusterFirstWithHostNet"}
  ]'
```

#### Option 2: Kustomize patch (declarative - repeatable, version-controlled)

```yaml
# For NGF
patches:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: ngf-nginx-gateway-fabric
      namespace: nginx-gateway
    patch: |-
      - op: add
        path: /spec/template/spec/hostNetwork
        value: true
      - op: add
        path: /spec/template/spec/dnsPolicy
        value: ClusterFirstWithHostNet
```

```yaml
# For Envoy Gateway
patches:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: envoy-gateway
      namespace: envoy-gateway-system
    patch: |-
      - op: add
        path: /spec/template/spec/hostNetwork
        value: true
      - op: add
        path: /spec/template/spec/dnsPolicy
        value: ClusterFirstWithHostNet
```

#### Verify the patch (both methods)

```bash
# Confirm pod restarted cleanly
kubectl rollout status deployment/<name> -n <namespace>

# Confirm hostNetwork is active
kubectl get deployment <name> -n <namespace> \
  -o jsonpath='{.spec.template.spec.hostNetwork}'
# Expected: true

# Confirm ports 80/443 are now bound on the host
sudo ss -tlnp | grep -E ':80|:443'
# Should show the nginx/envoy process
```

> **Important:** If anything else is already bound to port `80` or `443` on the host OS (a previous `ingress-nginx` with hostNetwork, Apache, or a standalone nginx process), the pod will crash with `address already in use`. The `ss` check above catches this before applying the patch.

> **Why `dnsPolicy: ClusterFirstWithHostNet`?** When `hostNetwork: true` is set, the pod inherits the node's DNS resolver by default - breaking in-cluster DNS resolution (e.g., `bankapp-service.bankapp.svc.cluster.local`). `ClusterFirstWithHostNet` restores cluster DNS while keeping host networking active.

---

### Method A vs B - Which to Choose?

| | iptables | hostNetwork |
|---|---|---|
| Cluster changes | None | Deployment patch required |
| Port conflicts | None | Port 80/443 must be free on host OS |
| Works with NodePort service | ✅ Yes | ✅ Yes (NodePort service can be removed) |
| Survives pod reschedule | ✅ Yes | ✅ Yes |
| Multi-node cluster | Apply iptables on each entry node | Only the node where the pod lands gets 80/443 |
| Recommended for | Single-node, quick setup | Production bare-metal with DaemonSet |
