# Deploy NGINX Gateway Fabric

NGINX Gateway Fabric (NGF) is the Gateway API-native controller maintained
by F5/NGINX. Unlike `ingress-nginx`, it implements the Gateway API spec
natively — no Ingress objects, no annotations.

!!! info "Official Documentation"
    [https://docs.nginx.com/nginx-gateway-fabric/install/helm/](https://docs.nginx.com/nginx-gateway-fabric/install/helm/)

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` configured
- Helm installed
- All nodes show `Ready` status

---

## Step 1 — Install Gateway API CRDs

NGF does **not** bundle Gateway API CRDs. Install them using NGF's
version-pinned reference to guarantee compatibility:

```bash
kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.5.1" \
  | kubectl apply -f -
```

!!! warning "Use NGF's CRD URL, not the upstream one"
    The upstream `kubernetes-sigs/gateway-api` repo and NGF may be on
    different release cadences. NGF's pinned reference guarantees the CRD
    schema version matches exactly what the controller expects.

Verify:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected output:

```
backendtlspolicies.gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

---

## Step 2 — Install NGF Controller

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace \
  -n nginx-gateway \
  --set nginx.service.type=NodePort    # required for bare-metal
```

Wait for the controller to be ready:

```bash
kubectl rollout status deployment/ngf-nginx-gateway-fabric -n nginx-gateway
```

!!! note "Why NodePort for bare-metal?"
    On bare-metal clusters without a cloud load balancer, a `LoadBalancer`
    Service stays in `<pending>` for `EXTERNAL-IP` indefinitely. `NodePort`
    exposes the controller on a high-range port (30000–32767) on every node.
    See [deploy-metallb-load-balancer.md](../deploy-metallb-load-balancer.md)
    to assign a real IP instead.

---

## Step 3 — Verify GatewayClass (Auto-Created)

NGF automatically creates a `GatewayClass` named `nginx` on startup:

```bash
kubectl get gatewayclass nginx
```

Expected output:

```
NAME    CONTROLLER                                   ACCEPTED   AGE
nginx   gateway.nginx.org/nginx-gateway-controller   True       30s
```

!!! warning "ACCEPTED must be True"
    If `ACCEPTED` shows `False` or `Unknown`, the controller is not running
    correctly. Check pod logs:

    ```bash
    kubectl logs -n nginx-gateway deploy/ngf-nginx-gateway-fabric
    ```

---

## Step 4 — Create a Gateway

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <gateway-name>
  namespace: <namespace>
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "<domain.com>"
      allowedRoutes:
        namespaces:
          from: Same
```

```bash
kubectl apply -f gateway.yaml
```

---

## Step 5 — Route Traffic with HTTPRoute

```yaml
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <route-name>
  namespace: <namespace>
spec:
  parentRefs:
    - name: <gateway-name>
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

```bash
kubectl apply -f httproute.yaml
```

Verify:

```bash
kubectl get httproute -n <namespace>
kubectl get gateway -n <namespace>
```

---

## Find NodePort (Bare-Metal)

On bare-metal, traffic reaches the controller via NodePort:

```bash
kubectl get svc -n nginx-gateway
```

```
NAME                      TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)
ngf-nginx-gateway-fabric  NodePort   10.96.x.x    <none>        80:3XXXX/TCP,443:3XXXX/TCP
```

Access the application at `http://<NodeIP>:<NodePort>`.

!!! tip "Get the node IP"
    ```bash
    kubectl get nodes -o wide
    ```
