# Deploy kube-prometheus-stack on EKS

## Official sources

| Resource | URL |
|---|---|
| ArtifactHub (chart) | https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack |
| GitHub (helm-charts) | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| GitHub (prometheus-operator) | https://github.com/prometheus-operator/prometheus-operator |
| Prometheus docs | https://prometheus.io/docs/introduction/overview/ |
| Grafana Helm chart | https://github.com/grafana/helm-charts/tree/main/charts/grafana |

Always check ArtifactHub for the latest chart version before installing.
The `--version` flag in every command below pins the chart to a specific
release; replace it with the current version if a newer one is available.

---

The **kube-prometheus-stack** Helm chart is the standard way to deploy a
full Kubernetes monitoring stack in one release. It bundles:

- **Prometheus** — scrapes and stores time-series metrics from nodes, pods,
  and Kubernetes components
- **Grafana** — visualises those metrics through pre-built dashboards
- **Alertmanager** — routes alerts to Slack, PagerDuty, email, etc.
- **kube-state-metrics** — exposes metrics about Kubernetes object state
  (Deployments, Pods, ReplicaSets)
- **prometheus-node-exporter** — runs as a DaemonSet and exposes hardware
  and OS metrics for each node
- **Prometheus Operator** — manages Prometheus and Alertmanager instances
  via CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`)

The data flow is:

```
EKS Nodes        → prometheus-node-exporter (DaemonSet)  → :9100/metrics
Kubernetes API   → kube-state-metrics                    → :8080/metrics
Pod /metrics     → ServiceMonitor CRDs                   → scraped by Prometheus
All              → Prometheus TSDB                       → queried by Grafana
Rule evaluation  → Alertmanager                          → Slack / email / PagerDuty
```

---

## Deployment pattern

The chart's own `values.yaml` is never modified. Two thin override files are
layered on top of it — one for Grafana and one for Prometheus — and passed to
`helm upgrade --install` using `-f`. Helm deep-merges them; each override file
declares only the keys it changes.

```
chart defaults (values.yaml)
        +
grafana-values.yaml          ← ingress, hostname, admin password reference
        +
prometheus-values.yaml       ← ingress, hostname, retention, storage
        =
final rendered manifests
```

This keeps upgrades clean: bump `--version`, re-run the same command, done.

---

## Requirements

Ensure the following before starting:

- An EKS cluster is running and `kubectl` is configured.
- Helm is installed.
- The AWS Load Balancer Controller is deployed and managing an ALB.
- An ACM certificate exists for the domain.
- DNS is configured (Route 53 or Cloudflare) and the ALB hostname is known.

Set the following variables:

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CERT_ARN=<acm-certificate-arn>
export ALB_GROUP_NAME=<alb-ingress-group-name>   # e.g. ecom-eks
export GRAFANA_HOST=grafana.<your-domain>
export PROMETHEUS_HOST=prometheus.<your-domain>
```

---

## Step 1 — Add the Helm repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
```

---

## Step 2 — Inspect the chart defaults (optional but recommended)

Dump the full default values to understand what is available to override:

```bash
helm show values prometheus-community/kube-prometheus-stack \
  --version 86.2.0 > /tmp/kube-prometheus-stack-defaults.yaml
```

!!! note
    This file is for reference only. Never commit it or pass it to `helm install`.
    The chart's defaults are applied automatically. Pass only override files that
    change specific keys.

---

## Step 3 — Create the override values files

Create a dedicated directory for the monitoring override files:

```bash
mkdir -p helm-values/monitoring
```

### `grafana-values.yaml`

This file overrides Grafana-specific settings only: ingress, hostname, and
admin credentials reference.

```bash
cat <<'EOF' > helm-values/monitoring/grafana-values.yaml
grafana:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/certificate-arn: "${CERT_ARN}"
      alb.ingress.kubernetes.io/group.name: "${ALB_GROUP_NAME}"
      alb.ingress.kubernetes.io/healthcheck-path: /api/health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - "${GRAFANA_HOST}"
EOF
```

Substitute the variables before applying:

```bash
envsubst < helm-values/monitoring/grafana-values.yaml \
  > helm-values/monitoring/grafana-values-rendered.yaml
```

!!! note
    `envsubst` replaces shell variable references (`${CERT_ARN}` etc.) with
    their current values and writes the result to a separate rendered file.
    Commit `grafana-values.yaml` (with variable placeholders) to version control,
    not the rendered file.

**Key explanations:**

| Key | Value | Reason |
|---|---|---|
| `ingressClassName: alb` | `alb` | Targets the AWS Load Balancer Controller IngressClass |
| `target-type: ip` | `ip` | Routes traffic directly to pod IPs — avoids NodePort hops, required for EKS |
| `backend-protocol: HTTP` | `HTTP` | TLS terminates at the ALB; internal pod traffic stays HTTP |
| `listen-ports` | 80 + 443 | ALB listens on both so the redirect rule can fire |
| `ssl-redirect: '443'` | `443` | ALB redirects all HTTP:80 requests to HTTPS:443 (301) |
| `certificate-arn` | ACM ARN | Associates the ACM certificate — enables TLS at the ALB listener |
| `group.name` | shared group | Multiple Ingress objects share one ALB; one listener rule is added per host |

---

### `prometheus-values.yaml`

This file overrides Prometheus-specific settings: ingress, hostname, data
retention, and storage.

```bash
cat <<'EOF' > helm-values/monitoring/prometheus-values.yaml
prometheus:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/certificate-arn: "${CERT_ARN}"
      alb.ingress.kubernetes.io/group.name: "${ALB_GROUP_NAME}"
      alb.ingress.kubernetes.io/healthcheck-path: /-/healthy
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - "${PROMETHEUS_HOST}"
    paths:
      - /
    pathType: Prefix
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
EOF
```

Substitute the variables before applying:

```bash
envsubst < helm-values/monitoring/prometheus-values.yaml \
  > helm-values/monitoring/prometheus-values-rendered.yaml
```

**Key explanations:**

| Key | Value | Reason |
|---|---|---|
| `paths: [/]` | `/` | Prometheus serves all endpoints under `/` — a single root path rule covers everything |
| `pathType: Prefix` | `Prefix` | Matches `/`, `/graph`, `/api/v1/query`, and any other Prometheus path |
| `retention: 15d` | 15 days | Keeps 15 days of metrics before they are deleted; tune based on available storage |
| `storageClassName: gp3` | `gp3` | Uses the CSI-backed gp3 StorageClass for persistent TSDB storage across pod restarts |
| `accessModes: ReadWriteOnce` | `RWO` | Prometheus TSDB is a single-writer database; only one pod mounts the volume at a time |
| `storage: 20Gi` | 20 GiB | Initial PVC size; increase when `kubectl top pvc` shows the volume filling up |

!!! note
    Without `storageSpec`, Prometheus uses `emptyDir` by default — all scraped
    metrics are lost when the pod restarts. Always set `storageSpec` in
    production clusters.

---

## Step 4 — Install the stack

Install the chart, passing both rendered override files:

```bash
helm upgrade --install prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 86.2.0 \
  --namespace monitoring \
  --create-namespace \
  -f helm-values/monitoring/grafana-values-rendered.yaml \
  -f helm-values/monitoring/prometheus-values-rendered.yaml
```

Helm deep-merges the two override files with the chart defaults. Keys absent
from both override files keep their chart defaults — nothing else is affected.

---

## Step 5 — Verify the deployment

Check all pods are running in the `monitoring` namespace:

```bash
kubectl get pods -n monitoring
```

Expected pods:

```text
NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-prometheus-stack-kube-prom-alertmanager-0   2/2     Running   0          60s
prometheus-prometheus-stack-kube-prom-prometheus-0       2/2     Running   0          58s
prometheus-stack-grafana-57b9f6c5d4-v9pf4                3/3     Running   0          62s
prometheus-stack-kube-prom-operator-5c57fb45c7-q7qm4     1/1     Running   0          62s
prometheus-stack-kube-state-metrics-59d55c4c-k4xxg       1/1     Running   0          62s
prometheus-stack-prometheus-node-exporter-8z26f          1/1     Running   0          62s
prometheus-stack-prometheus-node-exporter-bv87t          1/1     Running   0          62s
```

!!! note
    The Grafana pod briefly shows `2/3` while the `grafana-sc-dashboard`
    sidecar loads ConfigMaps from the cluster. Wait ~30 seconds for it to
    reach `3/3`.

Check the Ingress objects received ALB addresses:

```bash
kubectl get ingress -n monitoring
```

Check the Prometheus PVC is bound:

```bash
kubectl get pvc -n monitoring
```

Expected:

```text
NAME                                     STATUS   VOLUME   CAPACITY   STORAGECLASS
prometheus-prometheus-stack-db-0         Bound    pvc-...  20Gi       gp3
```

---

## Step 6 — Add DNS records

Retrieve the ALB hostname assigned to the Ingress:

```bash
kubectl get ingress -n monitoring -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

Add two CNAME records in Route 53 or Cloudflare pointing to the same ALB
hostname:

| Name | Type | Target |
|---|---|---|
| `grafana.<domain>` | CNAME | ALB hostname from above |
| `prometheus.<domain>` | CNAME | ALB hostname from above |

!!! note
    Both Grafana and Prometheus Ingress objects share the same ALB (via
    `group.name`). Both CNAMEs point to the same ALB hostname. The ALB
    routes traffic to the correct backend based on the `Host` header.

---

## Step 7 — Retrieve the Grafana admin password

The chart generates a random admin password and stores it in a Kubernetes
Secret:

```bash
kubectl get secret \
  --namespace monitoring \
  -l app.kubernetes.io/component=admin-secret \
  -o jsonpath="{.items[0].data.admin-password}" | base64 --decode; echo
```

Log in at `https://${GRAFANA_HOST}` with username `admin` and the password
printed above.

!!! tip
    To set a known admin password at install time, add the following to
    `grafana-values.yaml`:

    ```yaml
    grafana:
      adminPassword: "<password>"
    ```

    This replaces the auto-generated Secret. Do not commit plaintext passwords
    to version control — use a Kubernetes Secret reference or a secrets manager.

---

## How the shared ALB accumulates rules

The `alb.ingress.kubernetes.io/group.name` annotation causes the AWS Load
Balancer Controller to add one HTTPS listener rule per Ingress object to a
single shared ALB, rather than provisioning a separate ALB for each service.
After applying this runbook, two new rules are added:

```
ALB: ${ALB_GROUP_NAME} (single shared ALB)
  HTTPS :443 listener rules:
    ...                              ← any rules already present from previously
    ...                                deployed Ingress objects in this group
    Rule N   → Host: ${GRAFANA_HOST}    → Grafana pods (monitoring namespace)
    Rule N+1 → Host: ${PROMETHEUS_HOST} → Prometheus pods (monitoring namespace)
    Default  → fixed 404 response

  HTTP :80 listener:
    → Redirect ALL to HTTPS :443 (301)
```

!!! note
    The exact rule numbers depend on how many Ingress objects were already
    sharing this ALB group before this runbook was applied. Each previously
    deployed Ingress using the same `group.name` occupies earlier rule slots.
    The ALB console shows the complete ordered rule list.

---

## Upgrade

To upgrade to a newer chart version, re-run the install command with the new
version number. Helm upgrades in place:

```bash
helm upgrade --install prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version <new-version> \
  --namespace monitoring \
  -f helm-values/monitoring/grafana-values-rendered.yaml \
  -f helm-values/monitoring/prometheus-values-rendered.yaml
```

To see what would change before upgrading, use `helm diff` (requires the
`helm-diff` plugin):

```bash
helm diff upgrade prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version <new-version> \
  --namespace monitoring \
  -f helm-values/monitoring/grafana-values-rendered.yaml \
  -f helm-values/monitoring/prometheus-values-rendered.yaml
```

---

## Troubleshooting

### Grafana pod stuck at `2/3`

**Cause:** The `grafana-sc-dashboard` sidecar is waiting to list ConfigMaps
across all namespaces. This is normal on first install.

**Fix:** Wait 60 seconds. If it remains `2/3` after 2 minutes, check the
sidecar logs:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
```

### Prometheus PVC stays in `Pending`

**Cause:** No `gp3` StorageClass exists, or the EBS CSI driver is not
installed.

**Fix:** Confirm the StorageClass and the CSI driver are present:

```bash
kubectl get storageclass
kubectl get deploy -n kube-system | grep ebs-csi
```

If `gp3` is missing, install the EBS CSI driver and create the `gp3`
StorageClass following the steps in `install-ebs-csi-driver.md` in this
directory.

### Ingress shows no address

**Cause:** The AWS Load Balancer Controller is not installed or the
`ingressClassName: alb` does not match its IngressClass name.

**Fix:** Check the controller deployment and its managed IngressClass:

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
kubectl get ingressclass
```

---

## Quick sequence

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CERT_ARN=<acm-certificate-arn>
export ALB_GROUP_NAME=<alb-ingress-group-name>
export GRAFANA_HOST=grafana.<your-domain>
export PROMETHEUS_HOST=prometheus.<your-domain>
```

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

mkdir -p helm-values/monitoring

cat <<'EOF' > helm-values/monitoring/grafana-values.yaml
grafana:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/certificate-arn: "${CERT_ARN}"
      alb.ingress.kubernetes.io/group.name: "${ALB_GROUP_NAME}"
      alb.ingress.kubernetes.io/healthcheck-path: /api/health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - "${GRAFANA_HOST}"
EOF

cat <<'EOF' > helm-values/monitoring/prometheus-values.yaml
prometheus:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/certificate-arn: "${CERT_ARN}"
      alb.ingress.kubernetes.io/group.name: "${ALB_GROUP_NAME}"
      alb.ingress.kubernetes.io/healthcheck-path: /-/healthy
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - "${PROMETHEUS_HOST}"
    paths:
      - /
    pathType: Prefix
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 20Gi
EOF

envsubst < helm-values/monitoring/grafana-values.yaml \
  > helm-values/monitoring/grafana-values-rendered.yaml

envsubst < helm-values/monitoring/prometheus-values.yaml \
  > helm-values/monitoring/prometheus-values-rendered.yaml

helm upgrade --install prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 86.2.0 \
  --namespace monitoring \
  --create-namespace \
  -f helm-values/monitoring/grafana-values-rendered.yaml \
  -f helm-values/monitoring/prometheus-values-rendered.yaml

kubectl get pods -n monitoring
kubectl get ingress -n monitoring
kubectl get pvc -n monitoring

# Grafana admin password
kubectl get secret \
  --namespace monitoring \
  -l app.kubernetes.io/component=admin-secret \
  -o jsonpath="{.items[0].data.admin-password}" | base64 --decode; echo
```
