# Phase 5: Observability Stack

## What This Is

This runbook documents how I deployed the monitoring stack (Prometheus, Grafana, AlertManager with Slack) and the logging stack (Elasticsearch, Filebeat, Kibana) on the EKS cluster, and exposed all dashboards via HTTPRoutes on custom subdomains. This phase also hit a node capacity issue that required scaling the self-managed node group from 3 to 4 nodes.

This is Phase 5 of a 6-phase project.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| 1 | [CI Pipeline and DevSecOps](ci.md) | GitHub Actions workflows, Trivy scanning, GHCR image and chart publish |
| 2 | [AWS Infrastructure](aws-infrastructure.md) | DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes |
| 3 | [Cluster Add-ons and Gateway API](cluster-addons.md) | ALB Controller, EBS CSI, Gateway API, ExternalDNS |
| 4 | [GitOps with ArgoCD](gitops-argocd.md) | ArgoCD, Application manifest, Image Updater, CI-CD integration |
| **5** | **Observability Stack (this runbook)** | **kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes** |
| 6 | [Autoscaling, Load Testing, and Final Verification](autoscaling.md) | Metrics Server, HPA, scaling validation, full cluster audit |

At the end of this phase, the cluster has full metrics monitoring (Prometheus + Grafana), log aggregation (Elasticsearch + Filebeat + Kibana), and critical alert routing to Slack, all accessible via custom subdomains through the shared ALB.

### What I Did

```
Step 1   Deployed kube-prometheus-stack via Helm with Slack AlertManager config
Step 2   Created Slack webhook secret, installed the chart
Step 3   Applied HTTPRoutes + TargetGroupConfigs for Grafana and Prometheus
Step 4   Verified Grafana at grafana.ibtisam.qzz.io, Prometheus at prometheus.ibtisam.qzz.io
Step 5   Deployed ELK stack: ECK operator, Elasticsearch, Filebeat, Kibana
Step 6   Hit node capacity: Kibana pod stuck in Pending (3 nodes full)
Step 7   Scaled ASG from 3 to 4 nodes, 4th node joined, Kibana scheduled
Step 8   Applied HTTPRoute + TargetGroupConfig for Kibana
Step 9   Verified Kibana at kibana.ibtisam.qzz.io with container logs from all pods
```

| Item | Value |
|------|-------|
| Codebase | [`addons/kube-prometheus/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/kube-prometheus) and [`addons/elastic-logging/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/elastic-logging) |
| Grafana | `grafana.ibtisam.qzz.io` |
| Prometheus | `prometheus.ibtisam.qzz.io` |
| Kibana | `kibana.ibtisam.qzz.io` |

---

## Monitoring: kube-prometheus-stack

### Files Used

```
addons/kube-prometheus/
├── patch-values.yaml              # AlertManager Slack config, email default receiver
├── httproute-grafana.yaml         # grafana.ibtisam.qzz.io -> Grafana Service
├── httproute-prometheus.yaml      # prometheus.ibtisam.qzz.io -> Prometheus Service
├── target-grp-grafana.yaml        # ALB target group for Grafana (targetType: ip)
└── target-grp-prometheus.yaml     # ALB target group for Prometheus (targetType: ip)
```

### AlertManager Configuration

The [`patch-values.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/addons/kube-prometheus/patch-values.yaml) configures AlertManager with two receivers: Slack for critical alerts and email as the default fallback. The Slack webhook URL is stored in a Kubernetes Secret, not in the values file.

```bash
cd addons/kube-prometheus/

# Create the Slack webhook secret before installing the chart
kubectl create namespace monitoring

kubectl create secret generic alertmanager-slack-webhook \
  --from-literal=slack-webhook-url="<REDACTED>" \
  -n monitoring
```

The AlertManager config in `patch-values.yaml` mounts this secret and routes critical alerts to the `#alertmanager` Slack channel:

```yaml
alertmanager:
  alertmanagerSpec:
    secrets:
      - alertmanager-slack-webhook
  config:
    route:
      receiver: 'email-default'
      routes:
        - receiver: 'slack-notification'
          matchers:
            - severity = "critical"
    receivers:
      - name: 'slack-notification'
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/alertmanager-slack-webhook/slack-webhook-url
            channel: '#alertmanager'
            send_resolved: true
      - name: 'email-default'
```

### Installation

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

helm upgrade -i kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 86.2.3 \
  -f patch-values.yaml \
  -n monitoring --create-namespace
```

After the chart deployed, I retrieved the Grafana admin password:

```bash
kubectl get secret --namespace monitoring \
  -l app.kubernetes.io/component=admin-secret \
  -o jsonpath="{.items[0].data.admin-password}" | base64 --decode ; echo
```

### Exposing Grafana and Prometheus

I applied the HTTPRoutes and TargetGroupConfigurations via kustomize:

```bash
kubectl apply -k .
# httproute.gateway.networking.k8s.io/grafana-route created
# httproute.gateway.networking.k8s.io/prometheus-route created
# targetgroupconfiguration.gateway.k8s.aws/grafana-tg-config created
# targetgroupconfiguration.gateway.k8s.aws/prometheus-tg-config created
```

ExternalDNS picked up the new HTTPRoutes and created DNS records automatically. Both dashboards were accessible within a few minutes:

```bash
kubectl get httproutes.gateway.networking.k8s.io -A
# NAMESPACE      NAME              HOSTNAMES                         AGE
# argocd         argocd-server     ["argocd.ibtisam.qzz.io"]         45m
# boutique-app   http-app-route    ["app.ibtisam.qzz.io"]            35m
# monitoring     grafana-route     ["grafana.ibtisam.qzz.io"]        2m15s
# monitoring     prometheus-route  ["prometheus.ibtisam.qzz.io"]     2m15s
```

![Prometheus target health](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/05_prometheus_kube_prometheus_stack_target_health.png?raw=true)

![Grafana pod metrics dashboard](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/06_grafana_boutique_app_pod_metrics_dashboard.png?raw=true)

---

## Logging: Elastic Stack (ELK)

### Files Used

```
addons/elastic-logging/
├── patch-values-elasticsearch.yaml    # Elasticsearch CR config
├── patch-values-filebeat.yaml         # Filebeat DaemonSet with Kubernetes autodiscover
├── patch-values-kibana.yaml           # Kibana CR referencing Elasticsearch
├── httproute-kibana.yaml              # kibana.ibtisam.qzz.io -> Kibana Service
├── target-grp-kibana.yaml             # ALB target group for Kibana (targetType: ip)
└── storage-class-gp3.yaml             # gp3 StorageClass (already created in Phase 3)
```

### Components

| Component | What It Does | How It Is Deployed |
|-----------|--------------|-------------------|
| ECK Operator | Manages Elasticsearch and Kibana CRs as Kubernetes-native resources | Helm chart `elastic/eck-operator` |
| Elasticsearch | Search and analytics engine, stores all log data | Helm chart `elastic/eck-elasticsearch` (1 node, gp3 PVC) |
| Filebeat | DaemonSet that runs on every node, collects container logs from `/var/log/containers/` and ships to Elasticsearch | Helm chart `elastic/eck-beats` with [`patch-values-filebeat.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/addons/elastic-logging/patch-values-filebeat.yaml) |
| Kibana | Web UI for searching and visualizing logs | Helm chart `elastic/eck-kibana` |

### Installation

```bash
cd addons/elastic-logging/

kubectl create namespace logging

helm repo add elastic https://helm.elastic.co
helm repo update

# ECK Operator (manages ES and Kibana CRs)
helm upgrade -i eck-operator elastic/eck-operator \
  --version 3.4.0 -n logging

# Elasticsearch (1 node, uses gp3 PVC)
helm upgrade -i eck-elasticsearch elastic/eck-elasticsearch \
  --version 0.19.0 -n logging

# Filebeat DaemonSet (container log collection)
helm upgrade -i eck-beats elastic/eck-beats \
  --version 0.19.0 -f patch-values-filebeat.yaml -n logging

# Kibana (log visualization UI)
helm upgrade -i eck-kibana elastic/eck-kibana \
  --version 0.19.0 -f patch-values-kibana.yaml -n logging
```

### Node Capacity Issue

After the ELK stack deployed, Filebeat ran on all 3 nodes (DaemonSet), Elasticsearch started (1 StatefulSet pod), but **Kibana was stuck in Pending**:

```bash
kubectl get pods -n logging
# eck-kibana-kb-65699f8b-sq8bq    0/1     Pending     0          3m18s

kubectl describe pod -n logging eck-kibana-kb-65699f8b-sq8bq
# Conditions:
#   PodScheduled   False
# Events:
#   FailedScheduling: 0/3 nodes are available: insufficient cpu/memory
```

The 3 self-managed nodes were at capacity. The boutique app (10 services), monitoring stack (Prometheus, Grafana, AlertManager, node-exporter, kube-state-metrics), and now Elasticsearch + Filebeat had consumed all available resources.

!!! failure "Bug: Kibana Pending Due to Node Capacity"

    3 nodes were not enough to run the full stack (10 app services + monitoring + logging). The Kibana pod requested 2Gi memory and could not be scheduled. I scaled the Auto Scaling Group from 3 to 4 nodes via the AWS Console. The 4th node joined the cluster within 2 minutes and Kibana was scheduled on it.

```bash
# After scaling ASG to 4 nodes
kubectl get nodes
# NAME                           STATUS   ROLES    AGE   VERSION
# ip-10-0-1-106.ec2.internal     Ready    <none>   81m   v1.36.1-eks-0de9cde
# ip-10-0-2-91.ec2.internal      Ready    <none>   81m   v1.36.1-eks-0de9cde
# ip-10-0-3-20.ec2.internal      Ready    <none>   81m   v1.36.1-eks-0de9cde
# ip-10-0-3-xxx.ec2.internal     Ready    <none>   2m    v1.36.1-eks-0de9cde

kubectl get pods -n logging
# eck-kibana-kb-65699f8b-sq8bq    1/1     Running   0          ...
```

### Exposing Kibana

```bash
kubectl apply -f httproute-kibana.yaml
kubectl apply -f target-grp-kibana.yaml
```

Kibana was accessible at `kibana.ibtisam.qzz.io`. I navigated to Discover, created a data view for `filebeat-*`, and confirmed container logs were flowing from all nodes and pods across the cluster.

![Kibana logs discover view](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/07_kibana_boutique_app_logs_discover_view.png?raw=true)

---

## Final State

At the end of Phase 5, all observability components were operational:

```
monitoring namespace
  ├── Prometheus (scraping all targets)
  ├── Grafana (pod metrics dashboards)
  ├── AlertManager (Slack integration for critical alerts)
  ├── node-exporter, kube-state-metrics
  ├── HTTPRoute: grafana.ibtisam.qzz.io
  └── HTTPRoute: prometheus.ibtisam.qzz.io

logging namespace
  ├── ECK Operator
  ├── Elasticsearch (1 node, gp3 PVC)
  ├── Filebeat DaemonSet (4 pods, one per node)
  ├── Kibana (log search and visualization)
  ├── HTTPRoute: kibana.ibtisam.qzz.io
  └── All container logs flowing: /var/log/containers/* -> Filebeat -> Elasticsearch -> Kibana

Cluster nodes: 4 (scaled from 3 during this phase)

HTTPRoutes (all served by single shared ALB):
  - argocd.ibtisam.qzz.io      (Phase 4)
  - app.ibtisam.qzz.io          (Phase 4)
  - grafana.ibtisam.qzz.io      (this phase)
  - prometheus.ibtisam.qzz.io   (this phase)
  - kibana.ibtisam.qzz.io       (this phase)
```

All 5 subdomains served through a single ALB, DNS records auto-created by ExternalDNS, TLS terminated by the ACM wildcard certificate from Phase 2.

!!! abstract "Decision: Monitoring and Logging Deployed via Helm, Not ArgoCD"

    The monitoring and logging stacks were installed directly via Helm from the bastion host, not managed by ArgoCD Applications. This was a deliberate choice for two reasons.

    First, **independence from the thing being monitored.** If ArgoCD breaks or enters a crash loop, Prometheus, Grafana, and the ELK stack remain operational because they have no dependency on ArgoCD. Debugging a broken ArgoCD deployment requires observability tools that are not themselves managed by ArgoCD.

    Second, **platform vs. application separation.** In production microservices architectures, companies typically split ownership: the platform/SRE team manages observability infrastructure (monitoring, logging, service mesh, ingress controllers) via Helm, Terraform, or a dedicated platform ArgoCD project. Application teams manage their workloads via ArgoCD. This project follows the same pattern: the boutique app is ArgoCD-managed (Phase 4), the platform stack is Helm-managed (this phase).

    The alternative is the **app-of-apps** pattern where ArgoCD manages everything including itself. Both approaches are valid. For this project scope, the manual Helm approach was simpler and demonstrated the separation of concerns clearly.

---

## Terminal Sessions and Evidence

| # | Session | What It Covers | Link |
|---|---------|----------------|------|
| 1 | kube-prometheus-stack Monitoring | Slack secret creation, Helm install, Grafana password retrieval, HTTPRoute/TargetGroup apply, verification | [`05_kube_prometheus_stack_monitoring.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/05_kube_prometheus_stack_monitoring.txt) |
| 2 | Elastic Stack Logging | ECK operator install, Elasticsearch/Filebeat/Kibana deploy, Kibana Pending debug, ASG scaling, HTTPRoute apply | [`06_elastic_stack_logging.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/06_elastic_stack_logging.txt) |

| # | Screenshot | What It Shows | Link |
|---|------------|---------------|------|
| 1 | Prometheus Targets | All kube-prometheus-stack targets healthy and scraping | [`05_prometheus_kube_prometheus_stack_target_health.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/05_prometheus_kube_prometheus_stack_target_health.png) |
| 2 | Grafana Dashboard | Boutique app pod metrics (CPU, memory, network) | [`06_grafana_boutique_app_pod_metrics_dashboard.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/06_grafana_boutique_app_pod_metrics_dashboard.png) |
| 3 | Kibana Discover | Container logs from all pods flowing through Filebeat | [`07_kibana_boutique_app_logs_discover_view.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/07_kibana_boutique_app_logs_discover_view.png) |

---

## Next Phase

[Phase 6: Autoscaling and Load Testing](autoscaling.md) covers deploying Metrics Server, configuring HPA on the frontend deployment, generating load, and verifying horizontal scaling.
