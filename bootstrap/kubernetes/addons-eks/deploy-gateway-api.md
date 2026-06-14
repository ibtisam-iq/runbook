# Deploy Gateway API on EKS

This runbook installs and configures the Kubernetes Gateway API on an EKS cluster using the **AWS Load Balancer Controller (LBC) as the Gateway API implementation**. In this model, the data plane is an AWS ALB or NLB provisioned by the LBC — not an in-cluster proxy. This is fundamentally different from bare-metal setups (NGINX Gateway Fabric, Envoy Gateway) where a proxy pod runs inside the cluster.

!!! note "Prerequisite"
    The AWS Load Balancer Controller must already be installed with `NLBGatewayAPI=true` and `ALBGatewayAPI=true` feature gates enabled before proceeding. See [Deploy AWS Load Balancer Controller](./deploy-aws-load-balancer-controller.md).

!!! note "Why three CRD sets?"
    Bare-metal runbooks install one CRD bundle. On EKS with AWS LBC, three are required:
    - **Standard** — registers `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`
    - **Experimental** — adds `TCPRoute`, `TLSRoute`, `UDPRoute` for NLB (L4) routing
    - **LBC-specific** — registers AWS-proprietary CRDs: `LoadBalancerConfiguration` and `TargetGroupConfiguration`

---

## Architecture Overview

```
Internet
   │
   ▼
AWS ALB / NLB          ← provisioned and managed by AWS LBC
   │
   ▼
Gateway (EKS resource) ← references LoadBalancerConfiguration for ALB settings
   │
   ▼
HTTPRoute              ← attaches to Gateway; routes to a Kubernetes Service
   │
   ▼
Service (ClusterIP)    ← AWS LBC registers pod IPs directly as ALB targets
   │                     (requires TargetGroupConfiguration with targetType: ip)
   ▼
Pod
```

The AWS LBC watches `Gateway` and `HTTPRoute` resources and translates them into ALB listeners, rules, and target groups — it does not run a proxy inside the cluster.

---

## Step 1: Install Standard Gateway API CRDs

Install the standard Gateway API CRDs. These register `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, and `ReferenceGrant` as valid Kubernetes resource types:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

Verify the CRDs are registered:

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

Expected output includes:

```text
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

---

## Step 2: Install Experimental Gateway API CRDs

Install the experimental bundle. This adds `TCPRoute`, `TLSRoute`, and `UDPRoute`, which are required for L4 (NLB) routing when `NLBGatewayAPI=true` is enabled on the LBC:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
```

!!! note
    The experimental install is a **superset** of the standard install. Applying it after the standard install is safe — it adds the L4 route CRDs and updates the existing ones in place. No resources are deleted.

Verify the additional CRDs:

```bash
kubectl get crds | grep gateway.networking.k8s.io
```

The output should now also include:

```text
tcproutes.gateway.networking.k8s.io
tlsroutes.gateway.networking.k8s.io
udproutes.gateway.networking.k8s.io
```

---

## Step 3: Install LBC-Specific Gateway CRDs

Install the AWS LBC-specific Gateway CRDs. These register two AWS-proprietary resource types that have no equivalent in the standard Gateway API spec:

- **`LoadBalancerConfiguration`** — carries ALB/NLB-specific settings (`scheme`, TLS certificates, access logs) that the standard `Gateway` spec cannot express
- **`TargetGroupConfiguration`** — tells the LBC whether to register targets as EC2 instance IPs or pod IPs; this concept does not exist in standard Kubernetes

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml
```

Verify:

```bash
kubectl get crds | grep gateway.k8s.aws
```

Expected output:

```text
loadbalancerconfigurations.gateway.k8s.aws
targetgroupconfigurations.gateway.k8s.aws
```

---

## Step 4: Create the GatewayClass

Create the `GatewayClass` that binds to the AWS LBC controller. This is a cluster-scoped resource — one per cluster is sufficient:

```yaml
# gateway-class.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: GatewayClass
metadata:
  name: aws-alb-gateway-class
spec:
  controllerName: gateway.k8s.aws/alb
```

```bash
kubectl apply -f gateway-class.yaml
```

Verify:

```bash
kubectl get gatewayclass
```

Expected output:

```text
NAME                   CONTROLLER             ACCEPTED   AGE
aws-alb-gateway-class  gateway.k8s.aws/alb    True       10s
```

The `ACCEPTED: True` status confirms the LBC has recognised this `GatewayClass` and taken ownership of it.

!!! note "controllerName comparison"
    | Implementation | controllerName |
    |---|---|
    | AWS LBC | `gateway.k8s.aws/alb` |
    | NGINX Gateway Fabric | `gateway.nginx.org/nginx-gateway-controller` |
    | Envoy Gateway | `gateway.envoyproxy.io/gatewayclass-controller` |

---

## Step 5: Create the LoadBalancerConfiguration

Create a `LoadBalancerConfiguration` resource. This is an AWS LBC-specific CRD that carries ALB settings that the standard `Gateway` spec cannot express. The `Gateway` will reference this object via `infrastructure.parametersRef`:

```yaml
# alb-config.yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: LoadBalancerConfiguration
metadata:
  name: app-gw-lbconfig
  namespace: default
spec:
  scheme: internet-facing
  listenerConfigurations:
    - protocolPort: HTTPS:443
      defaultCertificate: <ACM-CERTIFICATE-ARN>
```

Replace `<ACM-CERTIFICATE-ARN>` with the ARN of the ACM certificate for the domain.

```bash
kubectl apply -f alb-config.yaml
```

Verify:

```bash
kubectl get loadbalancerconfiguration -n default
```

!!! note "Why this exists"
    AWS ALB has settings — scheme (internal vs internet-facing), TLS certificate ARNs, access log buckets — that the Kubernetes `Gateway` spec has no fields for. Rather than stuffing these into annotations, AWS invented this CRD so the configuration is structured and validatable. NGINX and Envoy do not need this because they are in-cluster proxies with no AWS-specific settings.

---

## Step 6: Create the Gateway

Create the `Gateway` resource. It references the `GatewayClass` created in Step 4 and the `LoadBalancerConfiguration` from Step 5. The `allowedRoutes.namespaces.from: All` setting is required because application `HTTPRoute` resources will be created in a different namespace (e.g. `boutique-app`) and need to attach to this `Gateway` in `default`:

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: app-alb-gateway
  namespace: default
spec:
  gatewayClassName: aws-alb-gateway-class
  infrastructure:
    parametersRef:
      kind: LoadBalancerConfiguration
      name: app-gw-lbconfig
      group: gateway.k8s.aws
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.example.com"
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      allowedRoutes:
        namespaces:
          from: All
```

Replace `*.example.com` with the wildcard domain for the cluster.

```bash
kubectl apply -f gateway.yaml
```

Verify the `Gateway` and confirm the ALB is being provisioned:

```bash
kubectl get gateway -n default
```

Expected output (ADDRESS populates once the ALB is fully provisioned, which takes 1–3 minutes):

```text
NAME              CLASS                   ADDRESS                                                             PROGRAMMED   AGE
app-alb-gateway   aws-alb-gateway-class   k8s-default-appalbga-xxxxxxxxxxxx.us-east-1.elb.amazonaws.com      True         90s
```

!!! warning "PROGRAMMED: Unknown"
    Immediately after `kubectl apply`, the `PROGRAMMED` status shows `Unknown`. This is normal — the LBC is provisioning the ALB in AWS. Wait 1–3 minutes and re-run `kubectl get gateway`. If it stays `Unknown` beyond 5 minutes, check LBC logs: `kubectl logs -n kube-system deploy/aws-load-balancer-controller`.

---

## Step 7: Verify End-to-End

Confirm all resources are in place:

```bash
# GatewayClass accepted by the LBC
kubectl get gatewayclass aws-alb-gateway-class

# Gateway provisioned with ALB address
kubectl get gateway app-alb-gateway -n default

# LoadBalancerConfiguration present
kubectl get loadbalancerconfiguration app-gw-lbconfig -n default

# All three CRD groups registered
kubectl get crds | grep -E 'gateway.networking.k8s.io|gateway.k8s.aws'
```

Confirm the ALB exists in AWS:

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(DNSName, `k8s-default`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
  --output table
```

---

## Attaching Application Routes

Once the `Gateway` is in place, application teams attach `HTTPRoute` and `TargetGroupConfiguration` resources from their own namespaces.

### TargetGroupConfiguration

This is required when using AWS LBC Gateway API with `ClusterIP` services. It tells the LBC to register pod IPs directly as ALB targets instead of EC2 node IPs:

```yaml
# target-group-config.yaml
apiVersion: gateway.k8s.aws/v1beta1
kind: TargetGroupConfiguration
metadata:
  name: app-tg-config
  namespace: boutique-app          # same namespace as the Service
spec:
  targetReference:
    name: frontend                 # must match the Kubernetes Service name
  defaultConfiguration:
    targetType: ip                 # pod IPs registered as targets
```

```bash
kubectl apply -f target-group-config.yaml
```

!!! note "Why TargetGroupConfiguration is AWS-only"
    AWS ALB/NLB require an explicit choice between `instance` (EC2 node) and `ip` (pod) as the target registration type. Kubernetes has no native concept for this. NGINX and Envoy do not need this CRD because they proxy traffic inside the cluster and never register targets in AWS target groups.

### HTTPRoute

```yaml
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: boutique-app
spec:
  hostnames:
    - "app.example.com"            # must match Gateway listener hostname pattern
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: default           # Gateway lives in default namespace
      name: app-alb-gateway
      sectionName: http
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: default
      name: app-alb-gateway
      sectionName: https
  rules:
    - backendRefs:
        - name: frontend
          port: 80
```

```bash
kubectl apply -f httproute.yaml
```

Verify the route attached to the Gateway:

```bash
kubectl get httproute -n boutique-app
```

Expected output:

```text
NAME        HOSTNAMES              PARENT                       AGE
app-route   ["app.example.com"]    default/app-alb-gateway      30s
```

---

## Comparison: Bare-Metal vs EKS Gateway API

| Concern | Bare-Metal (NGINX / Envoy) | EKS (AWS LBC) |
|---|---|---|
| **Data plane** | In-cluster proxy pod | AWS ALB / NLB (external) |
| **CRD sets needed** | 1 (Standard only) | 3 (Standard + Experimental + LBC-specific) |
| **GatewayClass** | Auto (NGINX) or manual (Envoy) | Always manual |
| **LoadBalancerConfiguration** | Not needed | Required |
| **TargetGroupConfiguration** | Not needed | Required per Service |
| **TLS termination** | Handled by proxy pod | Handled by ALB (ACM cert ARN) |
| **`allowedRoutes.from`** | `Same` (single namespace) | `All` (cross-namespace) |
| **ALB in AWS Console** | No AWS resource created | ALB visible in EC2 → Load Balancers |

---

## Quick Sequence

```bash
export REGION=$(aws configure get region)
export CERT_DOMAIN="ibtisam.qzz.io"       # domain used to issue the ACM cert
export ROUTE_DOMAIN="argocd.ibtisam.qzz.io"  # domain used in HTTPRoute / Gateway listeners

export CERT_ARN=$(aws acm list-certificates \
  --region "$REGION" \
  --query "CertificateSummaryList[?DomainName=='${CERT_DOMAIN}'].CertificateArn | [0]" \
  --output text)

echo "CERT_ARN: $CERT_ARN"
```

```bash
# Step 1: Standard CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

# Step 2: Experimental CRDs (L4 routes for NLB)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml

# Step 3: LBC-specific CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml

# Verify all CRDs
kubectl get crds | grep -E 'gateway.networking.k8s.io|gateway.k8s.aws'

mkdir -p k8s/gateway-api

cat <<'EOF' > k8s/gateway-api/gateway-config.yaml
---
# Step 4 — GatewayClass
apiVersion: gateway.networking.k8s.io/v1beta1
kind: GatewayClass
metadata:
  name: aws-alb-gateway-class
spec:
  controllerName: gateway.k8s.aws/alb
---
# Step 5 — LoadBalancerConfiguration
apiVersion: gateway.k8s.aws/v1beta1
kind: LoadBalancerConfiguration
metadata:
  name: app-gw-lbconfig
  namespace: default
spec:
  scheme: internet-facing
  listenerConfigurations:
    - protocolPort: HTTPS:443
      defaultCertificate: "${CERT_ARN}"
---
# Step 6 — Gateway
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: app-alb-gateway
  namespace: default
spec:
  gatewayClassName: aws-alb-gateway-class
  infrastructure:
    parametersRef:
      kind: LoadBalancerConfiguration
      name: app-gw-lbconfig
      group: gateway.k8s.aws
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.${ROUTE_DOMAIN}"
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.${ROUTE_DOMAIN}"
      allowedRoutes:
        namespaces:
          from: All
EOF

envsubst < k8s/gateway-api/gateway-config.yaml \
  > k8s/gateway-api/gateway-config-rendered.yaml

kubectl apply -f k8s/gateway-api/gateway-config-rendered.yaml

# Step 7: Verify
kubectl get gatewayclass
kubectl get gateway -n default
kubectl get loadbalancerconfiguration -n default
```
