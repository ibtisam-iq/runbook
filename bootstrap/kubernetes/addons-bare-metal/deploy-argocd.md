# Deploy ArgoCD on Bare-Metal and Access via Custom Domain

ArgoCD is a declarative, GitOps-based continuous delivery tool for Kubernetes. It watches a Git repository and automatically reconciles the live cluster state with the desired state defined in Git — no manual `kubectl apply` needed after the initial setup.

This runbook covers:

1. Installing ArgoCD on a bare-metal Kubernetes cluster via Helm
2. Exposing the ArgoCD UI (two methods: iximiuz lab port expose and Cloudflare Tunnel)
3. Deploying a full microservices application using an ArgoCD `Application` manifest, with all key decisions explained
4. Exposing the deployed app to the internet
5. Verifying the deployment via the ArgoCD UI

---

## Prerequisites

- A running Kubernetes cluster with `kubectl` configured. For k3s setup, see: [Bootstrap k3s Cluster](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-k3s/)
- `helm` installed and available in `PATH`
- A Cloudflare tunnel token provisioned (only for Option B — custom domain access)

### Dev Machine

[SilverStack Dev Machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) is used throughout this runbook — a custom root filesystem on iximiuz Labs with all DevOps tools pre-installed (`kubectl`, `helm`, `cloudflared`, `terraform`, `aws cli`, etc.). No local machine setup is required.

---

## Step 1 — Install ArgoCD

```bash
kubectl create namespace argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm install argocd argo/argo-cd \
  --namespace argocd
```

Verify all components are running:

```bash
kubectl get po,deploy,sts,svc -n argocd
```

| Component | Kind | Purpose |
|---|---|---|
| `argocd-server` | Deployment | API server + Web UI |
| `argocd-repo-server` | Deployment | Clones Git repos, renders manifests (Helm/Kustomize/raw YAML) |
| `argocd-application-controller` | StatefulSet | Reconciles desired (Git) vs live (cluster) state |
| `argocd-applicationset-controller` | Deployment | Generates `Application` objects from templates |
| `argocd-dex-server` | Deployment | OIDC SSO provider |
| `argocd-redis` | Deployment | Caching layer for repo server and app controller |
| `argocd-notifications-controller` | Deployment | Sends sync/health event notifications |

Retrieve the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

> **Note:** Delete this secret after the first login and password change.
> ```bash
> kubectl delete secret argocd-initial-admin-secret -n argocd
> ```

---

## Step 2 — Expose the ArgoCD UI

By default, `argocd-server` is a `ClusterIP` service. On bare-metal there is no cloud load balancer, so patch it to `NodePort` first:

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort"}}'

kubectl get svc argocd-server -n argocd
```

```
NAME            TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE
argocd-server   NodePort   10.43.86.5   <none>        80:30340/TCP,443:30440/TCP   4m37s
```

ArgoCD now listens on NodePort `30340` (HTTP) and `30440` (HTTPS). Choose one of the two access methods below.

### Option A — iximiuz Lab Port Expose

In the iximiuz lab UI, click **Expose HTTP(S) Ports**:

- Port: `30440`
- HTTPS: **ON**
- Click **EXPOSE**

A public URL like `https://6a...ae0c2.node-ap-b1d4.iximiuz.com` is generated.

> **Why port 30440 and not 30340?** ArgoCD enforces HTTPS redirects — connecting over plain HTTP on 30340 immediately redirects to HTTPS. Use the HTTPS NodePort directly.

### Option B — Cloudflare Tunnel (Custom Domain)

For full Cloudflare Tunnel setup, see: [Creating Cloudflare Tunnels](https://runbook.ibtisam-iq.com/self-hosted/ci-cd/iximiuz/self-hosted-cicd-stack-journey-from-ec2-to-iximiuz-labs/#phase-4-implementation---creating-cloudflare-tunnels)

```bash
sudo cloudflared service install <YOUR_TUNNEL_TOKEN>
```

In the Cloudflare dashboard (`Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames`), add a route:

| Field | Value |
|---|---|
| Subdomain | `argocd` |
| Domain | `ibtisam-iq.com` |
| Full hostname | `argocd.ibtisam-iq.com` |
| Service Type | `HTTPS` |
| Service URL | `localhost:30440` |
| No TLS Verify | **ON** |

> **Why HTTPS + No TLS Verify?** ArgoCD's server certificate is self-signed. Cloudflare must reach it over HTTPS (because ArgoCD only speaks HTTPS), but cannot verify the certificate chain. `No TLS Verify` allows the tunnel to connect without a trusted CA.

Access the UI at `https://argocd.ibtisam-iq.com`.

---

## Step 3 — Clone the Application Repo

The application being deployed is **Online Boutique** — a microservices demo originally by Google. It has been forked to [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo) with the following additions:

- A CI pipeline (`.github/workflows/ci.trigger.yml` and `build.yml`) that builds all service images and pushes them to `ghcr.io/ibtisam-iq/microservices-demo` instead of Google's registry
- A Helm chart at `helm-chart/` that references these custom images via `images.repository` and `images.tag` values

```bash
git clone https://github.com/ibtisam-iq/microservices-demo.git
cd microservices-demo
```

The Helm chart at `helm-chart/` is what ArgoCD will use as its source in the next step.

---

## Step 4 — Deploy the Application via ArgoCD

Create the ArgoCD `Application` manifest:

```bash
cat <<'EOF' > boutique-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: boutique-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ibtisam-iq/microservices-demo
    targetRevision: main
    path: helm-chart
    helm:
      parameters:
        - name: images.repository
          value: "ghcr.io/ibtisam-iq/microservices-demo"
        - name: images.tag
          value: "latest"
        - name: loadGenerator.create
          value: "false"
  destination:
    server: https://kubernetes.default.svc
    namespace: boutique-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

kubectl apply -f boutique-app.yaml
```

### Decisions Explained

**`path: helm-chart`**
ArgoCD auto-detects the deployment tool from the contents of this directory. Since `helm-chart/` contains a `Chart.yaml`, ArgoCD treats it as a Helm chart and runs `helm template` internally before applying.

| Files found in `path` | Tool used | How deployed |
|---|---|---|
| `Chart.yaml` | Helm | `helm template` → `kubectl apply` |
| `kustomization.yaml` | Kustomize | `kustomize build` → `kubectl apply` |
| Plain `*.yaml` | Raw manifests | `kubectl apply` directly |

**`images.repository: ghcr.io/ibtisam-iq/microservices-demo`**
The upstream chart defaults to Google's own image registry. Since all images have been rebuilt and pushed to GitHub Container Registry under this account, the repository is overridden here.

**`images.tag: latest`**
The Helm chart defaults to using the chart's `appVersion` as the image tag. Overriding with `latest` ensures the most recently pushed image is always pulled, which is appropriate for this demo setup.

**`loadGenerator.create: false`**
The load generator service requires its own custom-built image, which was not pushed to GHCR as part of this setup. Disabling it avoids an `ImagePullBackOff` error on that pod.

> **Note:** `images.tag: latest` is fine for demos. In production, pin to an immutable tag (e.g., a Git commit SHA) so deployments are reproducible and rollbacks are reliable.

**`destination.server: https://kubernetes.default.svc`**
This is the in-cluster Kubernetes API server address. It means ArgoCD deploys to the same cluster it runs in. For deploying to an external cluster, register it first with `argocd cluster add`.

**`syncPolicy.automated.prune: true`**
Resources deleted from Git are also deleted from the cluster. Without this, removed manifests would stay running indefinitely.

**`syncPolicy.automated.selfHeal: true`**
Any manual `kubectl` changes to cluster resources are automatically reverted to match Git. This enforces strict GitOps — Git is the single source of truth.

**`syncOptions.CreateNamespace=true`**
The `boutique-app` namespace does not exist before this manifest is applied. This option tells ArgoCD to create it automatically.

---

## Step 5 — Expose the Frontend

The Helm chart creates `frontend-external` as a `LoadBalancer` service. On bare-metal without MetalLB, it stays `<pending>` indefinitely. Patch it to `NodePort`.

First, disable `selfHeal` — otherwise ArgoCD will revert the manual patch within seconds:

```bash
kubectl patch application boutique-app -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
```

Then patch the service:

```bash
kubectl patch svc frontend-external -n boutique-app \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080,"protocol":"TCP"}]}}'

kubectl get svc frontend-external -n boutique-app
```

```
NAME                TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
frontend-external   NodePort   10.43.28.247  <none>        80:30080/TCP   3m
```

### Expose the Frontend — Two Methods

#### Option A — iximiuz Lab Port Expose

In the iximiuz lab UI → **Expose HTTP(S) Ports**:

- Port: `30080`
- HTTPS: **OFF** (the app serves plain HTTP)
- Click **EXPOSE**

#### Option B — Cloudflare Tunnel

In the Cloudflare dashboard, add a second public hostname on the same tunnel:

| Field | Value |
|---|---|
| Subdomain | `boutique` |
| Domain | `ibtisam-iq.com` |
| Service Type | `HTTP` |
| Service URL | `localhost:30080` |

Access at `https://boutique.ibtisam-iq.com`.

---

## Step 6 — Verify

```bash
# All 11 microservice pods should be Running
kubectl get po -n boutique-app

# All services should be present
kubectl get svc -n boutique-app

# ArgoCD application status
kubectl get application boutique-app -n argocd
```

```
NAME          SYNC STATUS   HEALTH STATUS
boutique-app  Synced        Healthy
```

In the ArgoCD UI at `argocd.ibtisam-iq.com`, the application shows:

- **APP HEALTH**: `Healthy`
- **SYNC STATUS**: `Synced` (or `OutOfSync` after the manual service patch — expected, since selfHeal is now disabled and Git still has `LoadBalancer`)
- **LAST SYNC**: timestamp of the last successful reconciliation

---

## Cleanup

```bash
# Delete the ArgoCD Application (prune will remove all deployed resources)
kubectl delete application boutique-app -n argocd

# Uninstall ArgoCD
helm uninstall argocd -n argocd
kubectl delete namespace argocd

# Tear down k3s (if needed)
/usr/local/bin/k3s-uninstall.sh
```
