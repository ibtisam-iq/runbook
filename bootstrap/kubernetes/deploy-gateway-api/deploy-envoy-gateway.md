# Deploy Envoy Gateway

Envoy Gateway is the CNCF-maintained Gateway API controller built on Envoy
Proxy. It has the most complete Gateway API conformance of any controller and
is production-grade.

!!! info "Official Documentation"
    [https://gateway.envoyproxy.io/docs/tasks/quickstart/](https://gateway.envoyproxy.io/docs/tasks/quickstart/)

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` configured
- Helm installed
- All nodes show `Ready` status

---

## Step 1 — Install CRDs and Controller (Single Command)

Unlike NGF, Envoy Gateway **bundles Gateway API CRDs inside its Helm chart**.
One command installs both:

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  -n envoy-gateway-system \
  --create-namespace
```

Wait for the controller to be ready:

```bash
kubectl rollout status deployment/envoy-gateway -n envoy-gateway-system
```

Verify CRDs were installed:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

---

## Step 2 — Create GatewayClass (Manual)

Unlike NGF, Envoy Gateway does **not** auto-create a `GatewayClass`. Must apply it manually:

```yaml
# gatewayclass.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

```bash
kubectl apply -f gatewayclass.yaml
```

Verify:

```bash
kubectl get gatewayclass eg
```

Expected output:

```
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       10s
```

!!! warning "ACCEPTED must be True"
    If `ACCEPTED` is not `True`, the controller pod is not healthy. Check:

    ```bash
    kubectl logs -n envoy-gateway-system deploy/envoy-gateway
    ```

---

## Step 3 — Create a Gateway

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <gateway-name>
  namespace: <namespace>
spec:
  gatewayClassName: eg
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

!!! note "Envoy creates a Service per Gateway"
    After applying the Gateway resource, Envoy Gateway automatically creates
    a dedicated proxy Service and Deployment for it. The Service name follows
    the pattern `envoy-<gateway-name>-<namespace>-<hash>`. This is different
    from NGF, which has one static Service for the whole controller.

---

## Step 4 — Route Traffic with HTTPRoute

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

Envoy creates a Service per Gateway. Its name is dynamic:

```bash
kubectl get svc -n envoy-gateway-system
```

```
NAME                              TYPE       PORT(S)
envoy-<name>-<ns>-<hash>          NodePort   80:3XXXX/TCP,443:3XXXX/TCP
```

!!! warning "Service name is dynamic"
    The Envoy Gateway proxy Service name is generated at runtime and changes
    if the Gateway resource is deleted and recreated. Always use
    `kubectl get svc -n envoy-gateway-system` to find the current name.

Access the application at `http://<NodeIP>:<NodePort>`.

!!! tip "Assign a real IP with MetalLB"
    To expose ports 80/443 directly on bare-metal instead of a random
    NodePort, deploy MetalLB — see
    [deploy-metallb-load-balancer.md](../deploy-metallb-load-balancer.md).
