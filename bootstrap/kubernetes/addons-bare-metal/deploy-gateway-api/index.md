# Kubernetes Gateway API

Gateway API is the **modern successor to the Ingress API**. Rather than a
single monolithic resource, it introduces a role-oriented, three-resource
model that separates infrastructure concerns from application routing concerns.

!!! warning "Ingress API is frozen"
    The Kubernetes project no longer adds features to the Ingress API. For all
    new deployments, use Gateway API.

    **Reference:** [Gateway API — Kubernetes Docs](https://kubernetes.io/docs/concepts/services-networking/gateway/)

---

## The Three-Resource Model

Gateway API builds on three interdependent resources. None of them work standalone:

| Resource | Answers the question | Owned by |
|---|---|---|
| `GatewayClass` | Which controller handles this? | Cluster infrastructure team |
| `Gateway` | What ports, hostnames, and TLS to expose? | Cluster operator |
| `HTTPRoute` / `GRPCRoute` | How to route requests to which backend? | Application developer |

A `Gateway` references a `GatewayClass`. An `HTTPRoute` or `GRPCRoute`
references a `Gateway` via `parentRefs`. This chain must be complete for
traffic to flow.

---

## What Must Be Installed

Two things must exist on the cluster before any of these resources can be created:

```
Installation Layer
├── 1. Gateway API CRDs   ← registers GatewayClass, Gateway, HTTPRoute, GRPCRoute as valid kinds
└── 2. Gateway Controller ← the actual proxy (NGINX or Envoy) that implements those resources
```

!!! note "Why CRDs must come first"
    Without Gateway API CRDs installed, `kubectl apply -f gateway.yaml` fails
    with `no matches for kind "Gateway"`. Kubernetes does not know the resource
    type yet. CRDs register the vocabulary; the controller acts on it.

---

## Available Controllers

| Controller | Maintained By | Notable Feature |
|---|---|---|
| **NGINX Gateway Fabric** | F5 / NGINX | Gateway API native, familiar NGINX core |
| **Envoy Gateway** | CNCF / Envoy | Most complete Gateway API support, production-grade |
| Traefik | Traefik Labs | Supports both Ingress and Gateway API simultaneously |
| Kong | Kong Inc. | API gateway features on top of Gateway API |
| Istio | CNCF | Full service mesh + Gateway API support |
| Contour | VMware / CNCF | Lightweight, Envoy-based |

!!! info
    This runbook covers **[NGINX Gateway Fabric](./deploy-nginx-gateway-fabric.md)** and **[Envoy Gateway](deploy-envoy-gateway.md)** only.
    The Gateway API concepts are identical across all controllers — only
    installation steps differ.

---

## Key Difference Between the Two Controllers

Before running any command, understand what each controller does and does not
do automatically:

| | NGINX Gateway Fabric | Envoy Gateway |
|---|---|---|
| **Gateway API CRDs** | ❌ Install separately first | ✅ Bundled in Helm chart |
| **GatewayClass** | ✅ Auto-created (`nginx`) | ❌ Must apply manually |
| **Install namespace** | `nginx-gateway` | `envoy-gateway-system` |
| **`gatewayClassName` in YAML** | `nginx` | `eg` |
| **Proxy Service name** | `ngf-nginx-gateway-fabric` (static) | `envoy-<name>-<ns>-<hash>` (dynamic per Gateway) |

---

## Resource Spec Reference

### GatewayClass

`GatewayClass` is cluster-scoped (no namespace). It binds a name to a
controller. Only one `GatewayClass` per controller is needed cluster-wide.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: <class-name>           # e.g., nginx or eg
spec:
  controllerName: <controller> # e.g., gateway.nginx.org/nginx-gateway-controller
```

### Gateway

`Gateway` is namespace-scoped. It defines what ports and hostnames the proxy
listens on, and which routes are allowed to attach.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <gateway-name>
  namespace: <namespace>
spec:
  gatewayClassName: <class-name>   # must match GatewayClass name above
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "<domain.com>"
      allowedRoutes:
        namespaces:
          from: Same              # or All, or Selector
```

!!! note "Cross-namespace routes"
    By default, a Gateway only accepts routes from the **same namespace**.
    Set `allowedRoutes.namespaces.from: All` to allow routes from any namespace.

### HTTPRoute

`HTTPRoute` is namespace-scoped. It defines path/host-based routing rules
and binds to a Gateway via `parentRefs`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <route-name>
  namespace: <namespace>
spec:
  parentRefs:
    - name: <gateway-name>         # must match the Gateway above
  hostnames:
    - "<domain.com>"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>
          port: <port>
```

### GRPCRoute

`GRPCRoute` follows the same structure as `HTTPRoute` but targets gRPC
services. The Gateway must support HTTP/2 — gRPC requires it.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: <route-name>
  namespace: <namespace>
spec:
  parentRefs:
    - name: <gateway-name>
  hostnames:
    - "<grpc-domain.com>"
  rules:
    - backendRefs:
        - name: <service-name>
          port: 50051
```

!!! tip "Match specific gRPC methods"
    Narrow a `GRPCRoute` to a specific service and method:

    ```yaml
    rules:
      - matches:
          - method:
              service: com.example
              method: Login
        backendRefs:
          - name: <service-name>
            port: 50051
    ```

---

## Installation Runbooks

- [Deploy NGINX Gateway Fabric](./deploy-nginx-gateway-fabric.md)
- [Deploy Envoy Gateway](./deploy-envoy-gateway.md)
