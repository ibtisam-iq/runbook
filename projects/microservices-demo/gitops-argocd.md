# Phase 4: GitOps with ArgoCD

## What This Is

This runbook documents how I deployed ArgoCD, deployed the Online Boutique application via the CD repo, and configured ArgoCD Image Updater for continuous delivery. This was the most iterative phase of the project: the Image Updater went through three strategy changes and multiple debugging cycles before working correctly with BuildKit-produced images.

This is Phase 4 of a 6-phase project.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| 1 | [CI Pipeline and DevSecOps](ci.md) | GitHub Actions workflows, Trivy scanning, GHCR image and chart publish |
| 2 | [AWS Infrastructure](aws-infrastructure.md) | DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes |
| 3 | [Cluster Add-ons and Gateway API](cluster-addons.md) | ALB Controller, EBS CSI, Gateway API, ExternalDNS |
| **4** | **GitOps with ArgoCD (this runbook)** | **ArgoCD install, application deployment, Image Updater, CI-CD integration** |
| 5 | Observability Stack | kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes |
| 6 | Autoscaling and Load Testing | Metrics Server, HPA, load generation, scaling verification |

At the end of this phase, the full CI/CD loop is operational: a code push to `src/` in the source repo triggers CI, which builds and pushes images to GHCR. Image Updater detects the new digest within 2 minutes and rolls the pods. No manual intervention.

### What I Did

```
Step 1   Cloned the CD repo, navigated to systems/microservices-demo/
Step 2   Installed ArgoCD via Helm with patch-values.yaml (insecure mode, Kustomize Helm, HTTPRoute)
Step 3   Applied the TargetGroupConfiguration for ArgoCD, accessed ArgoCD UI at argocd.ibtisam.qzz.io
Step 4   Reviewed all deployment manifests (kustomization.yaml, values-eks.yaml, httproute, target-grp)
Step 5   Applied the ArgoCD Application manifest, watched it sync and go Healthy
Step 6   Accessed the live app at app.ibtisam.qzz.io, placed a test order
Step 7   Installed ArgoCD Image Updater controller
Step 8   Applied the ImageUpdater CR (went through 3 strategy iterations)
Step 9   Debugged: newest-build failed (BuildKit epoch timestamps)
Step 10  Debugged: allowTags regex syntax (missing regexp: prefix)
Step 11  Debugged: digest strategy requires :latest version constraint
Step 12  Final config: digest strategy with :latest on all 10 images
Step 13  Triggered CI by pushing a change to src/frontend/README.md
Step 14  Verified: Image Updater detected new digest, rolled pods (revision 3)
```

| Item | Value |
|------|-------|
| CD repo | [ibtisam-iq/platform-engineering-systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo) |
| Codebase | [`systems/microservices-demo/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo) |
| ArgoCD manifests | [`addons/argocd/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/argocd) |
| Image Updater manifests | [`addons/image-updater/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/image-updater) |
| ArgoCD URL | [argocd.ibtisam.qzz.io](https://argocd.ibtisam.qzz.io/) |
| App URL | [app.ibtisam.qzz.io](https://app.ibtisam.qzz.io/) |

---

## Cloning the CD Repo

All deployment manifests live in the CD repo, not the source repo. I intentionally followed this architecture: the CI repo (`microservices-demo`) owns code and CI pipelines, the CD repo (`platform-engineering-systems`) owns deployment intent. The CD repo is not specific to this project alone; it is a platform-wide repo that hosts multiple systems.

```bash
git clone https://github.com/ibtisam-iq/platform-engineering-systems.git
cd platform-engineering-systems/systems/microservices-demo/
```

!!! abstract "Decision: All Manifests in CD Repo, Nothing in CI Repo"

    I never added any deployment manifests, values files, or Kubernetes resources to the source repo. The source repo owns code and CI workflows only. This separation means the CI pipeline has zero knowledge of the cluster, and the CD repo is the single source of truth for what runs where.

---

## Installing ArgoCD

I installed ArgoCD via Helm with a [`patch-values.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/addons/argocd/patch-values.yaml) that configures three things:

**1. Insecure mode** (`server.insecure: true`): TLS terminates at the ALB via the ACM certificate from Phase 2. The ALB forwards plain HTTP to ArgoCD internally. Without this, ArgoCD's own TLS would conflict with the ALB's TLS termination.

**2. Kustomize Helm rendering** (`kustomize.buildOptions: "--enable-helm"`): The ArgoCD Application points to a `kustomization.yaml` that contains a `helmCharts:` block. ArgoCD needs `--enable-helm` to render Helm charts inside Kustomize.

**3. HTTPRoute for ArgoCD UI** (`server.httproute.enabled: true`): The ArgoCD Helm chart natively supports creating an HTTPRoute. This attaches to the shared Gateway from Phase 3 and routes `argocd.ibtisam.qzz.io` to the `argocd-server` Service.

```bash
cd addons/argocd/

kubectl create namespace argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm install argocd argo/argo-cd \
  --namespace argocd \
  -f patch-values.yaml \
  --version 9.5.21

# After the Service exists, apply the TargetGroupConfiguration
kubectl apply -f target-grp-config.yaml
```

The [`target-grp-config.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/addons/argocd/target-grp-config.yaml) configures the ALB to route directly to ArgoCD server pod IPs (`targetType: ip`), same pattern as the app's target group binding.

I retrieved the initial admin password and accessed the ArgoCD UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

The ArgoCD UI at `argocd.ibtisam.qzz.io` took approximately 3-4 minutes to become accessible (ALB provisioning + DNS propagation by ExternalDNS + health check passing).

```bash
kubectl get httproute -A
# NAMESPACE     NAME             HOSTNAMES                       AGE
# argocd        argocd-server    ["argocd.ibtisam.qzz.io"]       4m50s
```

---

## Deploying the Application

Back in the project root (`systems/microservices-demo/`), I reviewed all the deployment manifests before applying.

### kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - manifests/httproute-frontend.yaml
  - manifests/target-grp-frontend.yaml
helmCharts:
  - name: onlineboutique
    repo: oci://ghcr.io/ibtisam-iq
    version: 0.10.5
    releaseName: boutique-app
    namespace: boutique-app
    valuesFile: chart/values-eks.yaml
```

The Kustomization pulls the Helm chart from my own GHCR (packaged by `chart-release.yaml` in Phase 1), overlays the EKS-specific values, and includes the HTTPRoute and TargetGroupBinding as additional resources. ArgoCD renders this with `kustomize build --enable-helm` (enabled by the patch-values.yaml).

### chart/values-eks.yaml

```yaml
images:
  repository: ghcr.io/ibtisam-iq/microservices-demo
  tag: "latest"

frontend:
  externalService: false
  platform: aws

loadGenerator:
  create: false
```

!!! tip "Decision: Patch-Only Values"

    Only 5 fields. Three real deltas from upstream (`externalService`, `platform`, `loadGenerator.create`), one registry swap, one tag override. The upstream Helm chart's default `values.yaml` handles everything else correctly.

!!! warning "Decision: tag: 'latest'"

    `tag: ""` was the initial choice, falling back to `.Chart.AppVersion`. This does not work with Image Updater: CI does not push images tagged with the chart version (that would be a dead tag nothing consumes). `tag: "latest"` is correct because Image Updater tracks the `:latest` tag's digest.

!!! info "Decision: loadGenerator Disabled"

    `loadgenerator` is excluded from the CI matrix. No image exists in GHCR for it. If the chart deployed it, the pod would hit `ImagePullBackOff`.

### manifests/

Two Gateway API resources sit outside the Helm chart:

[`httproute-frontend.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/manifests/httproute-frontend.yaml) routes `app.ibtisam.qzz.io` to the `frontend` ClusterIP Service. I included `group: ""`, `kind: Service`, `weight: 1`, and `matches` with `PathPrefix /` explicitly because the ALB controller injects these defaults post-creation, and without them ArgoCD shows perpetual OutOfSync drift.

!!! failure "Bug: HTTPRoute OutOfSync Drift"

    After initial deploy, ArgoCD showed 1 OutOfSync resource. The diff showed the live HTTPRoute had extra fields (`group`, `kind`, `weight`, `matches`) that the Git manifest lacked. These are Gateway API defaults the ALB controller injects. Adding them explicitly to the manifest resolved the drift permanently.

[`target-grp-frontend.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/manifests/target-grp-frontend.yaml) configures the ALB to route directly to frontend pod IPs (`targetType: ip`).

### Applying the Application

```bash
cd ~/platform-engineering-systems/systems/microservices-demo/
kubectl apply -f application.yaml
```

ArgoCD picked up the Application, rendered the Kustomization, and synced all resources:

```bash
kubectl get applications.argoproj.io -A
# NAMESPACE   NAME                 SYNC STATUS   HEALTH STATUS
# argocd      microservices-demo   Synced        Healthy

kubectl get httproutes.gateway.networking.k8s.io -A
# NAMESPACE      NAME              HOSTNAMES                       AGE
# argocd         argocd-server     ["argocd.ibtisam.qzz.io"]       10m
# boutique-app   http-app-route    ["app.ibtisam.qzz.io"]          58s
```

The app was live at [app.ibtisam.qzz.io](https://app.ibtisam.qzz.io/). I placed a test order to verify the full checkout flow across all 10 services.

![Online Boutique live on EKS](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/03_online_boutique_web_view.png?raw=true)

---

## ArgoCD Image Updater

### Installation

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/config/install.yaml

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
# NAME                                                READY   STATUS    RESTARTS   AGE
# argocd-image-updater-controller-xxxxxxxxxx-xxxxx    1/1     Running   0          30s
```

No registry config needed because the GHCR packages are public.

### Strategy Iteration 1: newest-build (Failed)

I initially configured the ImageUpdater CR with `newest-build` strategy and `allowTags: "^sha-[a-f0-9]{7}$"` to track the 7-char SHA tags.

**Bug 1:** `Invalid match option syntax '^sha-[a-f0-9]{7}$', ignoring`. The `allowTags` field requires a `regexp:` prefix. Fix: `allowTags: "regexp:^sha-[a-f0-9]{7}$"`.

After fixing the syntax, Image Updater found the tags but `images_updated` stayed at 0. The logs showed no errors, just `images_skipped=0 images_updated=0`. I pushed a new frontend image via CI. Image Updater still did not pick it up.

**Root cause:** BuildKit sets the image config's `created` timestamp to `1970-01-01T00:00:00Z` (epoch) for reproducible builds. The `newest-build` strategy uses this timestamp to determine which tag is newest. Since all images had identical epoch timestamps, Image Updater could not differentiate them.

I verified by inspecting the image manifest:

```bash
docker manifest inspect ghcr.io/ibtisam-iq/microservices-demo/frontend:sha-3cde868
# No "created" field in the manifest; it is in the config blob at epoch
```

!!! danger "Bug: BuildKit Epoch Timestamps Break newest-build"

    BuildKit produces images with `created: 1970-01-01T00:00:00Z` for reproducibility. ArgoCD Image Updater's `newest-build` strategy relies on this timestamp to rank tags. All tags appear identical in age, so Image Updater keeps the first one and never updates. This is a fundamental incompatibility between BuildKit's reproducibility design and Image Updater's timestamp-based strategy.

### Strategy Iteration 2: digest without version constraint (Failed)

I switched to `digest` strategy without changing the `imageName` fields:

```yaml
commonUpdateSettings:
  updateStrategy: digest
```

**Bug 2:** `cannot use update strategy 'digest' without a version constraint`. The `digest` strategy needs to know which tag's digest to track. Without `:latest` in the `imageName`, it does not know what to watch.

!!! failure "Bug: Digest Strategy Requires :latest Suffix"

    Each `imageName` must include the tag to track. `ghcr.io/.../frontend` is not enough. It must be `ghcr.io/.../frontend:latest`. The `:latest` suffix is the version constraint that tells Image Updater which tag's digest to compare.

### Strategy Iteration 3: digest with :latest (Working)

I added `:latest` to every `imageName` and also cleared the stale kustomize overrides left behind by the `newest-build` run:

```bash
# Clear stale overrides from the previous strategy
kubectl patch application microservices-demo -n argocd --type json \
  -p '[{"op": "remove", "path": "/spec/source/kustomize/images"}]'

# Apply the corrected ImageUpdater CR
kubectl apply -f image-updater.yaml
```

!!! warning "Note: The kubectl patch is Cleanup Only"

    The `kubectl patch` command above was needed only because the previous `newest-build` iteration had written stale `sha-*` overrides into the Application spec. On a fresh install, this patch is never needed. The Application starts with `tag: "latest"` from `values-eks.yaml`, and Image Updater pins the digest from there.

The logs immediately showed success:

```
msg="Successfully updated image 'ghcr.io/.../frontend:latest' to 'ghcr.io/.../frontend:latest@sha256:...'"
msg="Committing 10 parameter update(s) for application microservices-demo"
msg="Successfully updated application spec for microservices-demo"
msg="Processing results: applications=1 images_considered=10 images_updated=10 errors=0"
```

### Verification Commands

```bash
# ImageUpdater CR status
kubectl get imageupdater -n argocd
# APPS=1, IMAGES=10, READY=True

# What Image Updater wrote to the Application
kubectl get application microservices-demo -n argocd \
  -o jsonpath='{.spec.source.kustomize}' | python3 -m json.tool

# What image the frontend pod is running
kubectl get pods -n boutique-app -l app=frontend \
  -o jsonpath='{.items[0].spec.containers[0].image}'
# ghcr.io/ibtisam-iq/microservices-demo/frontend:latest@sha256:<digest>
```

### Final ImageUpdater CR

The working configuration: [`addons/image-updater/image-updater.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/addons/image-updater/image-updater.yaml)

```yaml
commonUpdateSettings:
  updateStrategy: digest
images:
  - alias: frontend
    imageName: "ghcr.io/ibtisam-iq/microservices-demo/frontend:latest"
  # ... all 10 services with :latest suffix
```

---

## End-to-End CI Trigger Test

With Image Updater running, I tested the full CI-to-CD loop. I pushed a change to `src/frontend/README.md` in the source repo. This triggered `ci-trigger.yaml`, which built and pushed `frontend:latest` with a new digest to GHCR.

Within 2 minutes, Image Updater detected the new digest and patched the Application. ArgoCD synced and rolled the frontend pods. The ArgoCD dashboard showed revision 3 (revision 1 was the initial deploy, revision 2 was Image Updater's first pin, revision 3 was the CI-triggered update).

![ArgoCD app tree showing Image Updater revision](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/04_argo_app_tree_image_updater_frontend_revision.png?raw=true)

The full loop was confirmed operational: code push to source repo -> CI builds and pushes image -> Image Updater detects new digest -> ArgoCD syncs -> pods roll. Zero manual intervention.

---

## Final State

```
argocd namespace
  ├── ArgoCD server (Helm release: argocd, version 9.5.21)
  ├── ArgoCD Image Updater controller
  ├── HTTPRoute: argocd.ibtisam.qzz.io
  ├── TargetGroupConfiguration: argocd-tg-config
  └── ImageUpdater CR: microservices-demo-updater (10 images, digest strategy)

boutique-app namespace
  ├── 10 Deployments (one per service, loadgenerator excluded)
  ├── 10 Services (ClusterIP)
  ├── 1 Redis StatefulSet (in-cluster cart database)
  ├── HTTPRoute: app.ibtisam.qzz.io
  └── TargetGroupConfiguration: app-tg-config

ArgoCD Application: microservices-demo
  ├── Source: platform-engineering-systems/systems/microservices-demo
  ├── Sync: Synced, Healthy
  └── Image overrides: 10 images pinned to digest by Image Updater
```

---

## Terminal Sessions and Evidence

| # | Session | What It Covers | Link |
|---|---------|----------------|------|
| 1 | Application Deployment and CI Trigger | CD repo clone, ArgoCD Helm install, patch-values review, Application apply, Image Updater install, strategy debugging, CI trigger test | [`04_application_deployment_and_ci_trigger.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/04_application_deployment_and_ci_trigger.txt) |

| # | Screenshot | What It Shows | Link |
|---|------------|---------------|------|
| 1 | Online Boutique Web View | Live app at app.ibtisam.qzz.io with product catalog | [`03_online_boutique_web_view.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/03_online_boutique_web_view.png) |
| 2 | ArgoCD App Tree with Image Updater | Application tree showing frontend revision after Image Updater rollout | [`04_argo_app_tree_image_updater_frontend_revision.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/04_argo_app_tree_image_updater_frontend_revision.png) |

---

## Next Phase

[Phase 5: Observability Stack](../phase-5-observability/) covers deploying kube-prometheus-stack (Prometheus, Grafana, AlertManager with Slack), the ELK stack (Elasticsearch, Filebeat, Kibana), and exposing all dashboards via HTTPRoutes on custom subdomains.
