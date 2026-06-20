# Phase 6: Autoscaling, Load Testing, and Final Verification

## What This Is

This runbook documents the final phase of the project: configuring HPA on the frontend service, observing scaling behavior under load, and running a full cluster verification to confirm every component across all 6 phases is operational. This is both the validation phase and the closing audit of the entire deployment.

This is Phase 6 of a 6-phase project.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| 1 | [CI Pipeline and DevSecOps](ci.md) | GitHub Actions workflows, Trivy scanning, GHCR image and chart publish |
| 2 | [AWS Infrastructure](aws-infrastructure.md) | DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes |
| 3 | [Cluster Add-ons and Gateway API](cluster-addons.md) | ALB Controller, EBS CSI, Gateway API, ExternalDNS |
| 4 | [GitOps with ArgoCD](gitops-argocd.md) | ArgoCD, Application manifest, Image Updater, CI-CD integration |
| 5 | [Observability Stack](observability.md) | kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes |
| **6** | **Autoscaling, Load Testing, and Final Verification (this runbook)** | **Metrics Server, HPA, scaling validation, full cluster audit** |

At the end of this phase, the platform is fully validated: HPA scales pods under load, and a comprehensive cluster audit confirms every pod is Running, every service is reachable, every HTTPRoute is attached, and zero Ingress resources exist (Gateway API only).

### What I Did

```
Step 1   Applied HPA manifest for the frontend Deployment (5% CPU target)
Step 2   HPA showed cpu: <unknown> - Metrics Server was missing
Step 3   Installed Metrics Server via Helm
Step 4   Verified: kubectl top nodes returned real metrics
Step 5   HPA started reading CPU values, traffic pushed CPU above 5%
Step 6   HPA scaled frontend from 1 to 2 replicas
Step 7   Load dropped, HPA scaled back down to 1 replica
Step 8   Ran full cluster verification: nodes, namespaces, pods, services, Gateway API, Helm releases
```

| Item | Value |
|------|-------|
| HPA manifest | [`manifests/hpa-frontend.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/manifests/hpa-frontend.yaml) |
| Target | `Deployment/frontend` in `boutique-app` namespace |
| CPU threshold | 5% (intentionally low for demo) |
| Min/Max replicas | 1 to 5 |

---

## HPA Configuration

I applied the HPA manifest from [`manifests/hpa-frontend.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/manifests/hpa-frontend.yaml):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
  namespace: boutique-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 5
```

!!! abstract "Decision: 5% CPU Threshold Is Intentional"

    The 5% threshold is not a production value. In production, typical HPA thresholds are 50-80%. I set it to 5% intentionally so that normal browsing traffic on the boutique app would be enough to trigger scaling without needing a dedicated load generator. The objective was to observe and validate the scaling behavior, not to tune for production capacity.

!!! info "Decision: HPA on Frontend Only"

    I configured HPA only on the frontend service, not on all 10 services. The goal was to observe scaling behavior end to end, not to autoscale every service. In a production deployment, each service would have its own HPA with thresholds tuned to its resource profile.

```bash
kubectl apply -f hpa-frontend.yaml

kubectl get hpa -n boutique-app
# NAME           REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# frontend-hpa   Deployment/frontend   cpu: <unknown>/5%   1         5         1          19s
```

The `<unknown>` immediately indicated a problem: HPA could not read CPU metrics.

---

## Missing Metrics Server

I described the HPA to see the error:

```bash
kubectl describe hpa -n boutique-app frontend-hpa
```

```
Conditions:
  ScalingActive   False   FailedGetResourceMetric
    the HPA was unable to compute the replica count:
    failed to get cpu utilization: unable to get metrics for resource cpu:
    unable to fetch metrics from resource metrics API:
    the server could not find the requested resource (get pods.metrics.k8s.io)
```

The Metrics Server was not installed. I had forgotten to include it in Phase 3 (Cluster Add-ons). Without it, the `metrics.k8s.io` API does not exist, and HPA has no CPU data to act on.

!!! failure "Bug: Metrics Server Not Installed"

    HPA requires Metrics Server to read pod CPU and memory utilization. EKS does not install it by default. I had planned to install it in Phase 3 alongside the other add-ons but forgot. The fix was straightforward: install via Helm.

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server

helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system
```

After about 30 seconds, the Metrics API became available:

```bash
kubectl top nodes
# NAME                           CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
# ip-10-0-1-106.ec2.internal     71m          3%       1543Mi          46%
# ip-10-0-2-41.ec2.internal      63m          3%       1676Mi          50%
# ip-10-0-2-91.ec2.internal      133m         6%       3013Mi          91%
# ip-10-0-3-20.ec2.internal      112m         5%       1795Mi          54%
```

---

## Scaling Behavior Observed

With Metrics Server running, HPA started reading real CPU values. The frontend Deployment had `requests.cpu: 100m` and `limits.cpu: 200m`. The 5% threshold meant scaling would trigger at just 5m of CPU usage per pod.

```bash
kubectl get hpa -n boutique-app
# frontend-hpa   Deployment/frontend   cpu: 2%/5%   1   5   1   6m30s
```

Normal idle traffic kept CPU at 2% (below threshold, no scaling). I accessed the app at `app.ibtisam.qzz.io` and browsed through products, added items to cart, and placed orders. The traffic pushed CPU above the 5% threshold:

```bash
kubectl get hpa -n boutique-app
# frontend-hpa   Deployment/frontend   cpu: 9%/5%   1   5   1   7m24s
```

CPU at 9%, above the 5% target. HPA scaled the frontend from 1 to 2 replicas:

```bash
kubectl get hpa -n boutique-app
# frontend-hpa   Deployment/frontend   cpu: 1%/5%   1   5   2   7m59s
```

Two replicas running, CPU per pod dropped to 1% (load distributed). After I stopped browsing, the CPU stayed below threshold for the stabilization window and HPA scaled back down:

```bash
kubectl get hpa -n boutique-app
# frontend-hpa   Deployment/frontend   cpu: 2%/5%   1   5   1   14m
```

Back to 1 replica. The full scale-out and scale-in cycle completed successfully.

![ArgoCD app tree showing HPA scale-out](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/08_argo_app_tree_hpa_frontend_scale_out.png?raw=true)

---

## Final State

The entire 6-phase project is complete. The platform is fully operational:

```
CI Pipeline (Phase 1)
  └── Code push -> GitHub Actions -> Trivy scan -> GHCR push

AWS Infrastructure (Phase 2)
  ├── Route 53: ibtisam.qzz.io (delegated)
  ├── ACM: *.ibtisam.qzz.io (wildcard cert)
  └── EKS: 4 self-managed nodes

Cluster Add-ons (Phase 3)
  ├── AWS Load Balancer Controller (Gateway API enabled)
  ├── EBS CSI Driver + gp3 StorageClass
  ├── Gateway API (shared ALB, HTTP + HTTPS)
  └── ExternalDNS (auto DNS records)

GitOps (Phase 4)
  ├── ArgoCD + Image Updater (digest strategy)
  ├── 10 microservices deployed via Helm chart from GHCR
  └── CI -> GHCR -> Image Updater -> ArgoCD -> pods roll

Observability (Phase 5)
  ├── Prometheus + Grafana + AlertManager (Slack)
  └── Elasticsearch + Filebeat + Kibana

Autoscaling (Phase 6)
  ├── Metrics Server
  └── HPA: frontend scales 1-5 based on CPU
```

Five subdomains, one ALB, one wildcard cert, zero manual DNS records:

| Subdomain | Service | Phase |
|-----------|---------|-------|
| `app.ibtisam.qzz.io` | Online Boutique frontend | 4 |
| `argocd.ibtisam.qzz.io` | ArgoCD server UI | 4 |
| `grafana.ibtisam.qzz.io` | Grafana dashboards | 5 |
| `prometheus.ibtisam.qzz.io` | Prometheus UI | 5 |
| `kibana.ibtisam.qzz.io` | Kibana log search | 5 |

After confirming the scaling cycle, I ran a full cluster verification: all nodes, namespaces, pods, services, Gateway API resources, and Helm releases across every namespace. Key findings from the audit:

- **4 nodes**, all `Ready`, Kubernetes `v1.36.1-eks`
- **9 namespaces** active: `argocd`, `boutique-app`, `default`, `external-dns`, `kube-system`, `kube-node-lease`, `kube-public`, `logging`, `monitoring`
- **All pods `Running`** across all namespaces, zero `CrashLoopBackOff`, zero `Pending`
- **5 HTTPRoutes** attached to the shared Gateway: `app`, `argocd`, `grafana`, `prometheus`, `kibana`
- **Zero Ingress resources** in the entire cluster (Gateway API only)
- **1 GatewayClass**, **1 Gateway** with `Programmed: True` and ALB DNS name assigned
- Node memory utilization ranged from 46% to 91% (node running Elasticsearch at 91%)

The complete output (960 lines) is recorded in the verification terminal session below.

---

## Terminal Sessions and Evidence

| # | Session | What It Covers | Link |
|---|---------|----------------|------|
| 1 | Scaling Behavior and Reliability | HPA apply, Metrics Server missing, Helm install, CPU monitoring, scale-out 1->2, scale-in 2->1 | [`07_observe_scaling_behavior_and_validate_reliability.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/07_observe_scaling_behavior_and_validate_reliability.txt) |
| 2 | Full Cluster Verification | All nodes, namespaces, pods, services, Gateway API resources, Helm releases, storage classes, HPA status across the entire cluster | [`08_verification_of_pods_services_and_resources.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/08_verification_of_pods_services_and_resources.txt) |

| # | Screenshot | What It Shows | Link |
|---|------------|---------------|------|
| 1 | ArgoCD HPA Scale-Out | ArgoCD app tree showing frontend HPA with multiple replicas during scale-out | [`08_argo_app_tree_hpa_frontend_scale_out.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/08_argo_app_tree_hpa_frontend_scale_out.png) |
