# Deploy ArgoCD on Bare-Metal (k3s) and Deploy an App

This runbook walks through every step performed to install ArgoCD on a single-node k3s cluster running on an iximiuz SilverStack lab machine, deploy the **Online Boutique** microservices demo via an ArgoCD `Application` manifest, and expose the app and the ArgoCD UI to the internet using two methods: a **Cloudflare Tunnel** (custom domain) and the **iximiuz lab HTTPS port-forwarding** feature.

> **Pre-requisites**
> - iximiuz SilverStack Dev Machine (all tools pre-installed: `kubectl`, `helm`, `cloudflared`, etc.)
> - A Cloudflare account with a tunnel token already provisioned at `dash.cloudflare.com → Zero Trust → Networks → Tunnels`
> - The microservices-demo repo forked/cloned from `https://github.com/ibtisam-iq/microservices-demo`

---

## Phase 1 — Bootstrap k3s Cluster

See the full cluster bootstrap guide at: https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-k3s/

```bash
# Install k3s single-node cluster
curl -sfL https://get.k3s.io | sh -

# Set up kubeconfig for the current user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

# Verify
kubectl get nodes
```

**Expected output:**
```
NAME         STATUS   ROLES                  AGE   VERSION
dev-machine  Ready    control-plane,master   30s   v1.35.5+k3s1
```

---

## Phase 2 — Clone the Application Repo

```bash
git clone https://github.com/ibtisam-iq/microservices-demo.git
cd microservices-demo
```

This repo contains the Helm chart at `helm-chart/` which ArgoCD will use as its source.

---

## Phase 3 — Install ArgoCD via Helm

```bash
# Create the ArgoCD namespace
kubectl create namespace argocd

# Add the official Argo Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

# Install ArgoCD (default values — all components)
helm install argocd argo/argo-cd \
  --namespace argocd
```

**Verify all pods are Running:**
```bash
kubectl get po,deploy,sts,svc -n argocd
```

You should see these workloads all `Running`:

| Component | Kind | Purpose |
|---|---|---|
| `argocd-server` | Deployment | API server + Web UI |
| `argocd-repo-server` | Deployment | Clones Git repos, renders manifests |
| `argocd-application-controller` | StatefulSet | Reconciles desired vs live state |
| `argocd-applicationset-controller` | Deployment | Generates Applications from templates |
| `argocd-dex-server` | Deployment | OIDC SSO provider |
| `argocd-redis` | Deployment | Caching layer |
| `argocd-notifications-controller` | Deployment | Sends sync/health event notifications |

**Retrieve the initial admin password:**
```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

> **Important:** Delete this secret after logging in and changing the password.
> ```bash
> kubectl delete secret argocd-initial-admin-secret -n argocd
> ```

---

## Phase 4 — Expose the ArgoCD UI

By default `argocd-server` is a `ClusterIP` service. On bare-metal there is no cloud load balancer, so we use NodePort.

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort"}}'

kubectl get svc argocd-server -n argocd
```

**Expected:**
```
NAME            TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE
argocd-server   NodePort   10.43.86.5   <none>        80:30340/TCP,443:30440/TCP   4m37s
```

ArgoCD server now listens on `NodePort 30340` (HTTP) and `30440` (HTTPS).

### Option A — Cloudflare Tunnel (Custom Domain)

See full Cloudflare Tunnel setup: https://runbook.ibtisam-iq.com/self-hosted/ci-cd/iximiuz/self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs/#phase-4-implementation---creating-cloudflare-tunnels

```bash
# Install the cloudflared tunnel daemon (token from Cloudflare dashboard)
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
```

In the Cloudflare dashboard (`Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames`):

| Field | Value |
|---|---|
| Subdomain | `argocd` |
| Domain | `ibtisam-iq.com` |
| Full hostname | `argocd.ibtisam-iq.com` |
| Service Type | `HTTPS` |
| Service URL | `localhost:30440` |
| No TLS Verify | `ON` (because ArgoCD uses a self-signed cert) |

> **Why HTTPS + No TLS Verify?** ArgoCD server serves HTTPS on port 443 (NodePort 30440). Cloudflare must connect to it over HTTPS, but the certificate is self-signed, so TLS verification must be disabled on the tunnel route.

The app is then reachable at `https://argocd.ibtisam-iq.com`.

### Option B — iximiuz Lab Port Expose

In the iximiuz lab UI, click **Expose HTTP(S) Ports**:

- Port: `30440`
- HTTPS: `ON`
- Click **EXPOSE**

This gives a public URL like `https://6a...ae0c2.node-ap-b1d4.iximiuz.com`.

> Use port **30440** (HTTPS NodePort), NOT 30340 (HTTP). ArgoCD enforces HTTPS redirects, so connecting over plain HTTP will redirect you immediately.

---

## Phase 5 — Create the ArgoCD Application

The `Application` is the core ArgoCD custom resource. It tells ArgoCD:
1. **Where** to pull manifests from (Git source)
2. **Where** to deploy them (Kubernetes destination)
3. **How** to keep them in sync (sync policy)

```bash
cat <<'EOF' > boutique-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boutique-app
  namespace: argocd          # Application resource always lives in argocd namespace
spec:
  project: default           # ArgoCD project — controls RBAC boundaries

  source:
    repoURL: https://github.com/ibtisam-iq/microservices-demo
    targetRevision: main     # branch, tag, or commit SHA
    path: helm-chart         # folder inside repo — ArgoCD auto-detects Chart.yaml here → uses Helm
    helm:
      parameters:
        - name: images.repository
          value: "ghcr.io/ibtisam-iq/microservices-demo"
        - name: images.tag
          value: "latest"
        - name: loadGenerator.create
          value: "false"     # skip load generator pod in this demo

  destination:
    server: https://kubernetes.default.svc   # in-cluster deployment
    namespace: boutique-app

  syncPolicy:
    automated:
      prune: true       # delete resources removed from Git
      selfHeal: true    # revert any manual kubectl changes
    syncOptions:
      - CreateNamespace=true   # create boutique-app namespace if it doesn't exist
EOF

kubectl apply -f boutique-app.yaml
```

### Application Manifest — Field-by-Field Reference

#### `metadata`

| Field | Value used | Meaning |
|---|---|---|
| `name` | `boutique-app` | Name of the ArgoCD Application object |
| `namespace` | `argocd` | **Always `argocd`** — Application CRs must live here |

#### `spec.project`

`default` is the built-in project that allows deploying to any namespace on any cluster. Custom projects can restrict which repos, clusters, and namespaces are allowed.

#### `spec.source` — mandatory fields

| Field | Description |
|---|---|
| `repoURL` | Git repository URL (HTTPS or SSH). For Helm chart repos, this would be the chart repo URL instead. |
| `targetRevision` | Branch name, tag, or full commit SHA to track. `HEAD` means the default branch tip. |
| `path` | Directory inside the repo. ArgoCD **auto-detects** the tool based on what files exist here (see table below). |

**Auto-detection logic — what ArgoCD looks for inside `path`:**

| Files found in `path` | Tool ArgoCD uses | How it deploys |
|---|---|---|
| `Chart.yaml` | **Helm** | `helm template` then `kubectl apply` |
| `kustomization.yaml` | **Kustomize** | `kustomize build` then `kubectl apply` |
| Plain `*.yaml` / `*.json` | **Raw manifests** | `kubectl apply` directly |
| `Chart.yaml` + `kustomization.yaml` | Helm takes priority | |

> In this runbook, `path: helm-chart` contains a `Chart.yaml`, so ArgoCD uses Helm automatically. No need to set `spec.source.helm` unless you want to override values — which we do below.

#### `spec.source.helm` — optional Helm overrides

```yaml
helm:
  parameters:            # equivalent to --set on the CLI
    - name: images.tag
      value: "latest"
  valueFiles:            # equivalent to -f values-prod.yaml
    - values-prod.yaml
  values: |              # inline values, equivalent to --values with a string
    replicaCount: 2
  releaseName: boutique  # override the Helm release name (default: Application name)
  version: v3            # force Helm v3 (default)
```

#### `spec.destination`

| Field | Description |
|---|---|
| `server` | Target cluster API endpoint. `https://kubernetes.default.svc` = the same cluster ArgoCD runs in. For external clusters, register them first with `argocd cluster add`. |
| `namespace` | Namespace to deploy resources into. Must match `CreateNamespace=true` in syncOptions if it doesn't exist yet. |

#### `spec.syncPolicy`

```yaml
syncPolicy:
  automated:
    prune: true      # Remove resources from cluster when deleted from Git
    selfHeal: true   # Re-apply Git state if someone manually edits live resources
  syncOptions:
    - CreateNamespace=true     # Auto-create destination namespace
    - ServerSideApply=true     # Use server-side apply (better for CRDs)
    - ApplyOutOfSyncOnly=true  # Only apply resources that are actually out of sync
    - PruneLast=true           # Prune resources only after all others are synced
    - Replace=true             # Use kubectl replace instead of apply (for immutable fields)
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

| Option | What it does |
|---|---|
| `prune: true` | Dangerous without care — deletes live resources not in Git |
| `selfHeal: true` | Overrides any manual `kubectl` changes — disable when debugging |
| `CreateNamespace=true` | Needed when destination namespace doesn't pre-exist |
| `ServerSideApply=true` | Recommended for complex CRDs and Helm charts |
| `PruneLast=true` | Prevents race condition where prune happens before new resources are healthy |

#### Multiple Sources (`spec.sources`)

For referencing a Helm chart from one repo but values files from another:

```yaml
spec:
  sources:
    - repoURL: https://github.com/ibtisam-iq/microservices-demo
      targetRevision: main
      ref: appcode                   # give this source a reference name
    - repoURL: https://charts.example.com
      chart: my-chart
      targetRevision: 1.2.3
      helm:
        valueFiles:
          - $appcode/helm-chart/values-prod.yaml   # reference the other source by name
  destination:
    server: https://kubernetes.default.svc
    namespace: boutique-app
```

---

## Phase 6 — Expose the Frontend App

The Helm chart creates `frontend-external` as a `LoadBalancer` service. On bare-metal it stays `<pending>`. Patch it to `NodePort`:

```bash
# First disable selfHeal so ArgoCD doesn't revert our manual patch
kubectl patch application boutique-app -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'

# Patch frontend-external to NodePort on port 30080
kubectl patch svc frontend-external -n boutique-app \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080,"protocol":"TCP"}]}}'

# Verify
kubectl get svc frontend-external -n boutique-app
```

**Expected:**
```
NAME                TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
frontend-external   NodePort   10.43.28.247  <none>        80:30080/TCP   3m
```

> **Why disable selfHeal first?** When `selfHeal: true`, ArgoCD continuously reconciles. The moment you manually patch the service, ArgoCD sees drift from Git and reverts your patch within seconds. Disabling selfHeal prevents this revert.

### Expose Frontend — Two Methods

#### Method A — Cloudflare Tunnel

In the Cloudflare dashboard, add a second public hostname for the same tunnel:

| Field | Value |
|---|---|
| Subdomain | `boutique` (or any name) |
| Domain | `ibtisam-iq.com` |
| Service Type | `HTTP` |
| Service URL | `localhost:30080` |

Access at: `https://boutique.ibtisam-iq.com`

#### Method B — iximiuz Lab Port Expose

In the iximiuz lab UI → **Expose HTTP(S) Ports**:
- Port: `30080`
- HTTPS: `OFF` (the app is plain HTTP)
- Click **EXPOSE**

This gives a public URL like `https://6a...ae0c2.node-ap-b1d4.iximiuz.com`.

---

## Phase 7 — Verify Full Deployment

```bash
# All 11 microservice pods should be Running
kubectl get po -n boutique-app

# All services should be present
kubectl get svc -n boutique-app

# Check ArgoCD application health
kubectl get application boutique-app -n argocd
```

**Healthy application output:**
```
NAME          SYNC STATUS   HEALTH STATUS
boutique-app  Synced        Healthy
```

In the ArgoCD UI, the application card will show:
- **APP HEALTH**: `Healthy` (green heart)
- **SYNC STATUS**: `Synced` — or `OutOfSync` if Git has newer commits not yet deployed
- **LAST SYNC**: timestamp of the last successful sync

> `OutOfSync` after the service patch is expected if selfHeal was disabled. It means the live cluster differs from Git. This is acceptable for local development experiments.

---

## Understanding the OutOfSync State (Seen in Screenshot)

After patching `frontend-external` to NodePort, ArgoCD shows **OutOfSync** because:
1. Git still defines `frontend-external` as `LoadBalancer`
2. The live cluster has it as `NodePort` (our manual patch)
3. selfHeal is now disabled, so ArgoCD reports the drift but does not fix it

This is intentional. To restore full sync, either:
- Re-enable selfHeal (ArgoCD will revert the patch → service goes back to LoadBalancer)
- Update the Helm chart values in Git to set `frontend.externalService.type: NodePort` → triggers a new sync with the correct state

---

## Cleanup

```bash
# Delete the application (and all deployed resources if prune is enabled)
kubectl delete application boutique-app -n argocd

# Or via ArgoCD CLI
argocd app delete boutique-app

# Uninstall ArgoCD
helm uninstall argocd -n argocd
kubectl delete namespace argocd

# Tear down k3s
/usr/local/bin/k3s-uninstall.sh
```

---

## Quick Reference

```bash
# Get ArgoCD initial password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode; echo

# Manually trigger a sync
kubectl patch application boutique-app -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Force refresh (re-fetch from Git)
argocd app get boutique-app --refresh

# Watch application status live
watch kubectl get application boutique-app -n argocd

# Check what ArgoCD would change (dry-run diff)
argocd app diff boutique-app
```
