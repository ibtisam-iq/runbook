# Phase 1: CI Pipeline and DevSecOps

## What This Is

This runbook documents how I built the CI pipeline for the Online Boutique microservices project. It covers the 3 GitHub Actions workflow files that live in the source repo ([ibtisam-iq/microservices-demo](https://github.com/ibtisam-iq/microservices-demo)), the image tagging strategy and how it evolved, and the bugs I hit along the way.

This is Phase 1 of a 6-phase project. The full project deploys a 10-service polyglot application on Amazon EKS using a production-grade GitOps pipeline.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| **1** | **CI Pipeline and DevSecOps (this runbook)** | **GitHub Actions workflows, Trivy scanning, GHCR image and chart publish** |
| 2 | [AWS Infrastructure](aws-infrastructure.md) | VPC, EKS cluster, self-managed nodes, Bastion host, Route 53 hosted zone, ACM certificate (Terraform) |
| 3 | [Cluster Add-ons and Gateway API](cluster-addons.md) | ALB Controller, EBS CSI, Gateway API CRDs, GatewayClass, Gateway, ExternalDNS |
| 4 | GitOps with ArgoCD | ArgoCD, Application manifest, Image Updater, CD repo structure, deployment manifests |
| 5 | Observability Stack | kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes |
| 6 | Autoscaling and Load Testing | Metrics Server, HPA, load generation, scaling verification |

At the end of this phase, every code push to `src/` builds, scans, and pushes container images to GHCR automatically. Every change to `helm-chart/` packages and publishes the Helm chart to GHCR and updates the CD repo. CI does not touch the cluster. ArgoCD Image Updater (configured in Phase 4) watches GHCR and handles deployments.

| Item | Value |
|------|-------|
| Source repo | [ibtisam-iq/microservices-demo](https://github.com/ibtisam-iq/microservices-demo) |
| CD repo | [ibtisam-iq/platform-engineering-systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo) |
| Container images | `ghcr.io/ibtisam-iq/microservices-demo/<service>:<tag>` |
| Helm chart | `oci://ghcr.io/ibtisam-iq/onlineboutique` |

---

## Pipeline Flow

Two independent triggers, two independent flows. A code change and a chart change can fire in the same push without conflict.

### Flow A: Code Change (`src/**` modified)

```
push to main
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  ci-trigger.yaml                                                │
│                                                                 │
│  Job 1: detect-changes                                          │
│    ├── checkout (full history, fetch-depth: 0)                  │
│    ├── git diff: extract changed service directories            │
│    ├── exclude loadgenerator                                    │
│    └── emit JSON array, e.g. ["frontend","cartservice"]         │
│                                                                 │
│  Job 2: build-and-push (matrix, one per service)                │
│    └── calls reusable-build.yaml per service                    │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼ (× N services in parallel)
┌─────────────────────────────────────────────────────────────────┐
│  reusable-build.yaml                                            │
│                                                                 │
│  Stage 0  Compute short SHA (bash ${GITHUB_SHA:0:7})            │
│  Stage 1  Checkout source code                                  │
│  Stage 2  Trivy filesystem scan (CRITICAL + HIGH/MEDIUM)        │
│  Stage 3  Docker Buildx setup                                   │
│  Stage 4  GHCR login                                            │
│  Stage 5  Docker build (load: true, 3 tags, BuildKit GHA cache) │
│  Stage 6  Trivy image scan (OS + library CRITICAL + HIGH/MED)   │
│  Stage 7  Push to GHCR: :sha-<40> :sha-<7> :latest              │
│  Stage 8  Cleanup local images                                  │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
CI done. No CD repo touch.
  :
  : (Image Updater detects new :latest digest within ~2 min)
  : (see Phase 4)
```

### Flow B: Chart Change (`helm-chart/**` modified)

```
push to main
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  chart-release.yaml                                             │
│                                                                 │
│  Stage 1  Read Chart.yaml metadata (name, version, appVersion)  │
│  Stage 2  helm lint + helm package                              │
│  Stage 3  helm push to oci://ghcr.io/ibtisam-iq                 │
│  Stage 4  Verify push                                           │
│  Stage 5  Clone CD repo, sed version in kustomization.yaml      │
│  Stage 6  Commit + push to CD repo                              │
│  Stage 7  Clear token from remote URL                           │
└─────────────────────────────────────────────────────────────────┘
  │
  ▼
CD repo updated.
  :
  : (ArgoCD detects commit, pulls new chart, syncs)
  : (see Phase 4)
```

---

## Forking and Evaluating the Upstream

I forked [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo). The fork stays pristine: I never modify upstream files. All customization lives in files I add alongside upstream. The `src/` directory, `helm-chart/` directory, and all templates remain untouched. This keeps the fork syncable with upstream.

!!! abstract "Decision: Never Modify Upstream Files"

    Every custom file I created (workflow files, values overrides, manifests) is an addition, not a modification. If upstream releases a new chart version or patches a service, I can sync the fork without merge conflicts.

The upstream repo shipped with 5 CI workflows. I evaluated each:

| File | What It Did | My Decision | Why |
|------|-------------|-------------|-----|
| `ci-main.yaml` | Built all services unconditionally, pushed to Google Container Registry | **Deleted** | Not monorepo-efficient, pushed to GCR, no security scanning |
| `ci-pr.yaml` | Full rebuild on every PR | **Deleted** | Superseded by PR validation built into `ci-trigger.yaml` |
| [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml) | Linted and template-tested the Helm chart under 5 configurations | **Kept** | Catches template bugs before `chart-release.yaml` pushes to GHCR |
| `kubevious-manifests-ci.yaml` | Kubevious structural validation of upstream directories | **Kept** | Validates directories I do not deploy from, but harmless |
| `kustomize-build-ci.yaml` | `kustomize build` on upstream overlays | **Kept** | Same reasoning as above |

I deleted `ci-main.yaml` and `ci-pr.yaml` because both rebuilt all services unconditionally (no change detection), pushed to Google's own registry (GCR), and had zero security scanning. I replaced them with 3 custom workflows: a monorepo-aware trigger with matrix dispatch, a reusable build worker with Trivy scanning, and a Helm chart release pipeline pushing to my own GHCR.

---

## Workflow 1: ci-trigger.yaml

**File:** [`.github/workflows/ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml)
**Triggers on:** `src/**` changes to `main`, PRs against `main`, `workflow_dispatch`

This is the orchestrator. It detects which services changed and fans out one build job per service.

**Job 1: detect-changes** checks out the repo with full history (`fetch-depth: 0`), runs `git diff` between the previous commit and the current SHA, and extracts the unique service directory names under `src/`. The output is a JSON array like `["frontend","cartservice"]`.

```bash
SERVICES=$(git diff --name-only "${BEFORE}" "${{ github.sha }}" \
  | grep '^src/' \
  | cut -d'/' -f2 \
  | sort -u \
  | grep -v '^loadgenerator$' \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')
```

I excluded `loadgenerator` from the matrix. It is a test harness, not a production service. No image is pushed to GHCR for it. On the CD side, the Helm chart's `loadGenerator.create` is set to `false` to prevent `ImagePullBackOff`.

The `${{ github.event.before }}` is empty on `workflow_dispatch` and is the all-zeros SHA on the first push to a new branch. I added a fallback to `HEAD~1` for both cases so the `git diff` range is always valid.

**Job 2: build-and-push** consumes the JSON array as a matrix. Each matrix entry calls `reusable-build.yaml` for one service. `fail-fast: false` ensures a broken `adservice` does not abort a clean `frontend` build. Each service owns its own blast radius.

!!! tip "Design: cartservice Context Override"

    `cartservice`'s Dockerfile lives in `src/cartservice/src/`, not `src/cartservice/`. I handled this with a ternary in the `docker_context` input at the caller level, so `reusable-build.yaml` stays generic.

    ```yaml
    docker_context: ${{ matrix.service == 'cartservice' && 'src/cartservice/src' || format('src/{0}', matrix.service) }}
    ```

### Permissions

```yaml
permissions:
  contents: read           # checkout
  packages: write          # GHCR push (delegated to reusable-build.yaml)
  security-events: write   # Trivy SARIF upload (delegated to reusable-build.yaml)
```

A called reusable workflow can only request permissions at or below what the caller grants. It can narrow, never escalate. I had to grant `packages: write` and `security-events: write` at the caller level because `reusable-build.yaml` needs both.

!!! failure "Bug: Permission Escalation Failure"

    The first run failed at startup. `reusable-build.yaml` requested `packages: write` but `ci-trigger.yaml` only granted `contents: read`. The fix was adding `packages: write` and `security-events: write` at the caller level.

### Concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Safe on PRs (no registry side effects). I scoped `cancel-in-progress` to PRs only because cancelling a `main` push mid-push could leave GHCR in a partial state.

---

## Workflow 2: reusable-build.yaml

**File:** [`.github/workflows/reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml)
**Called by:** [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) (one invocation per changed service)

This is the worker. It owns the full build lifecycle for a single service.

### Stage 0: Compute Short SHA

GitHub Actions expressions do not support string slicing. I computed the 7-char short SHA in bash and exported it to `GITHUB_ENV`:

```bash
SHORT_SHA="${GITHUB_SHA:0:7}"
echo "IMAGE_SHORT=ghcr.io/${{ github.repository_owner }}/microservices-demo/${{ inputs.service }}:sha-${SHORT_SHA}" >> "$GITHUB_ENV"
```

### Stage 2: Trivy Filesystem Scan

I scan the source tree before building the image. Two passes:

- **CRITICAL**: advisory (`exit-code: 0`). Catches hardcoded secrets and IaC misconfigs early.
- **HIGH/MEDIUM**: advisory, uploads a JSON artifact for audit trail (14-day retention).

### Stage 5: Docker Build

```yaml
- name: Docker Build - load into daemon (scan before push)
  uses: docker/build-push-action@v6.15.0
  with:
    context: ${{ inputs.docker_context }}
    push: false
    load: true
    tags: |
      ${{ env.IMAGE_REF }}
      ${{ env.IMAGE_SHORT }}
      ${{ env.IMAGE_LATEST }}
    cache-from: type=gha,scope=${{ inputs.service }}
    cache-to: type=gha,mode=max,scope=${{ inputs.service }}
```

`load: true` puts the image in the local Docker daemon so Trivy can scan it before push. `push: false` because push is a separate stage after scans pass.

!!! info "Design: BuildKit Cache Strategy"

    `cache-to: type=gha,mode=max` writes ALL layers, not just the final stage. This is correct for multi-stage Dockerfiles (builder + runtime stages). `mode=max` saves runner time at the cost of cache storage.

!!! warning "Design: BuildKit Epoch Timestamps"

    BuildKit sets the image config's `created` field to `1970-01-01T00:00:00Z` for reproducible builds. I discovered this when ArgoCD Image Updater's `newest-build` strategy failed to differentiate tags. All images appeared identical in age. This constraint drove the `digest` strategy choice on the CD side (see [Phase 4](gitops-argocd.md)).

### Stage 6: Trivy Image Scan

Three passes on the built image:

- **OS packages CRITICAL/HIGH**: advisory. Vendor's responsibility.
- **Library CRITICAL**: designed as a hard gate (`exit-code: 1`), currently relaxed to `exit-code: 0`.
- **Library HIGH/MEDIUM**: advisory, uploads JSON artifact.

!!! danger "Decision: Trivy CRITICAL Gate Temporarily Relaxed"

    The upstream Online Boutique base images carry known CRITICAL CVEs that would block every build during the pipeline build-out phase. I set `exit-code: 0` as a deliberate, temporary relaxation. Restore `exit-code: "1"` once base images are patched or a curated `.trivyignore` is in place.

### Stage 7: Push to GHCR

Three tags per service per build:

| Tag | Purpose | Consumer |
|-----|---------|----------|
| `sha-<40char>` | Immutable, traceable to exact commit | Audit trail |
| `sha-<7char>` | Human-readable | ArgoCD UI, CD logs |
| `latest` | Mutable, digest changes on every push | ArgoCD Image Updater |

```bash
docker push ${{ env.IMAGE_REF }}
docker push ${{ env.IMAGE_SHORT }}
docker push ${{ env.IMAGE_LATEST }}
```

Skipped on PR builds (`if: inputs.push_image == true`). The caller does not pass `push_image` (defaults to `true`); the PR gating comes from the caller's `if:` condition on Job 3 in older iterations. In the current design, there is no Job 3, and `push_image` simply defaults to `true`.

### Stage 8: Cleanup

```bash
docker rmi ${{ env.IMAGE_REF }}   || true
docker rmi ${{ env.IMAGE_SHORT }}  || true
docker rmi ${{ env.IMAGE_LATEST }} || true
```

Runners are ephemeral but image layers consume disk. Large services (adservice JVM, frontend Node build) can hit the runner disk limit in matrix runs sharing the same runner pool.

---

## Workflow 3: chart-release.yaml

**File:** [`.github/workflows/chart-release.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/chart-release.yaml)
**Triggers on:** `helm-chart/**` changes to `main`, `workflow_dispatch`

This workflow packages the upstream Helm chart as-is and pushes it to `oci://ghcr.io/ibtisam-iq`. Then it updates the chart version in the CD repo's [`kustomization.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/kustomization.yaml).

### Stage 1: Read Chart Metadata

```bash
CHART_NAME=$(grep '^name:' helm-chart/Chart.yaml | awk '{print $2}')
CHART_VERSION=$(grep '^version:' helm-chart/Chart.yaml | sed "s/version: *//; s/\"//g" | tr -d '[:space:]')
```

I used `grep`/`awk`/`sed` instead of `yq` to avoid adding a tool dependency to the runner.

### Stage 2: Package and Push

```bash
helm lint helm-chart/
helm package helm-chart/
helm push onlineboutique-${CHART_VERSION}.tgz oci://ghcr.io/${{ github.repository_owner }}
```

!!! abstract "Decision: Chart Packaged from Upstream As-Is"

    No upstream files are modified. The chart on GHCR ships with Google's default `values.yaml` baked in. EKS-specific customizations live in [`values-eks.yaml`](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/microservices-demo/values-eks.yaml) in the CD repo, applied at render time by the Kustomization's `valuesFile` field.

### Stage 3: Update CD Repo

After pushing the chart, the workflow clones the CD repo and updates the `version:` field in `kustomization.yaml`:

```bash
git clone https://github.com/${CD_REPO}.git cd-repo
cd cd-repo
git remote set-url origin https://x-access-token:${GIT_TOKEN}@github.com/${CD_REPO}.git
sed -i "s/^    version: .*/    version: ${CHART_VERSION}/" "${KUSTOMIZATION}"
git add "${KUSTOMIZATION}"
git commit -m "ci: update microservices-demo chart to ${CHART_VERSION} [skip ci]"
git push origin HEAD
```

Token security: clone via public HTTPS URL (token never in process argv), set authenticated remote after clone via `git remote set-url`, clear the token from the remote URL after push.

!!! warning "GIT_TOKEN Security"

    `GITHUB_TOKEN` cannot push to a foreign repo. `GIT_TOKEN` is a fine-grained PAT scoped to `platform-engineering-systems` with Contents: Read+Write only. Planned migration: GitHub App installation token (org-owned identity, short-lived per-run token).

!!! info "GIT_TOKEN Not Needed for Code Pushes"

    With Image Updater handling image tag resolution, `ci-trigger.yaml` and `reusable-build.yaml` never touch the CD repo. `GIT_TOKEN` is only consumed by `chart-release.yaml` for chart version updates, which happen far less frequently than code pushes.

---

## How the Image Tagging Strategy Evolved

The tag strategy went through three iterations. Each solved one problem and exposed another.

### Iteration 1: Chart Version Tags

I initially added a 4th tag (`:chart_version`, e.g., `:0.10.5`) to every image push. The CD repo's `values-eks.yaml` set `tag: ""` so the Helm chart template fell back to `.Chart.AppVersion`. I also built `reusable-gitops.yaml` to write the chart version into the CD repo after every build, and added a full-fleet rebuild trigger: when `Chart.yaml` changed, all 10 services rebuilt with the new version tag.

The problem appeared on the first code-only push. I changed `src/frontend/`, CI built and pushed `frontend:0.10.5`, then `reusable-gitops.yaml` tried to write `chart_version: 0.10.5` to the CD repo. But `0.10.5` was already there. `git diff --cached --quiet` exited 0, no commit, no ArgoCD sync. The new image sat in GHCR and nothing deployed it.

This design only worked for release events (Chart.yaml version bump), not for continuous delivery.

### Iteration 2: Immutable SHA Tags

I reverted to the original design: every code push wrote a unique `sha-<commit>` tag to the CD repo via `reusable-gitops.yaml`. ArgoCD detected the diff and synced.

This worked but was noisy. Every commit to `src/` triggered a CD repo commit. The CD repo accumulated a commit per code push. And it would conflict with ArgoCD Image Updater if both tried to be the source of truth for which image should run.

### Iteration 3: ArgoCD Image Updater (Final Design)

I evaluated three approaches:

| | Approach A (SHA tags) | Approach B (Image Updater) | Approach C (Hybrid) |
|---|---|---|---|
| CI touches CD repo? | Yes, every push | No | Yes, every push |
| Deployment trigger | Git commit to CD repo | Registry poll | Git commit to CD repo |
| CD repo noise | High | Low | High |
| Conflicts with Image Updater | Yes | N/A | Yes, if not scoped |

I chose Approach B. CI pushes images with `sha-<40>`, `sha-<7>`, and `latest` tags, then stops. It has zero knowledge of the CD repo for code pushes. Image Updater watches GHCR for new digests behind `:latest` and handles deployments on the cluster side (configured in [Phase 4](gitops-argocd.md)).

This eliminated `reusable-gitops.yaml` entirely. Its two responsibilities were redistributed:

- **Image tag writes**: eliminated. Image Updater owns this.
- **Chart version writes**: absorbed into `chart-release.yaml` (Stage 3).

!!! info "Decision: CD Repo Update Does Not Contradict Image Updater"

    Image Updater manages what **code** runs inside pods (container image digests). `chart-release.yaml` manages what **resources** exist in the cluster (Deployments, Services, ConfigMaps defined by Helm templates). A chart version bump means "the Deployment now has a new env var." An image digest change means "the frontend container has new code." They never step on each other.

---

## End-to-End Verification

### Code change (CI only)

I pushed a change to `src/frontend/`. The pipeline ran:

```
ci-trigger.yaml -> detect-changes emitted ["frontend"]
  -> reusable-build.yaml built, scanned, pushed:
       frontend:sha-<40char>
       frontend:sha-<7char>
       frontend:latest
  -> CI done. No CD repo commit.
```

On the cluster side, Image Updater detected the new digest behind `frontend:latest` within 2 minutes and rolled the pods (documented in [Phase 4](gitops-argocd.md)).

### Chart change (CI + CD repo update)

I pushed a change to `helm-chart/`. The pipeline ran:

```
chart-release.yaml -> lint, package, push to oci://ghcr.io/ibtisam-iq
  -> cloned CD repo, updated kustomization.yaml version
  -> committed and pushed to CD repo
  -> ArgoCD detected the commit, pulled the new chart, synced
```

### Both change simultaneously

When both `src/` and `helm-chart/` change in the same push, `ci-trigger.yaml` and `chart-release.yaml` fire in parallel. They trigger on different paths (`src/**` vs `helm-chart/**`) and resolve independently. No conflict.

---

## Final State

The [`.github/workflows/`](https://github.com/ibtisam-iq/microservices-demo/tree/main/.github/workflows) directory has 3 custom files:

```
.github/workflows/
├── ci-trigger.yaml         # 141 lines - src/** -> detect, fan out
├── reusable-build.yaml     # 197 lines - build, scan, push per service
└── chart-release.yaml      # 164 lines - helm-chart/** -> package, push, update CD
```

Plus 3 upstream workflows kept as-is: [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml), [`kubevious-manifests-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kubevious-manifests-ci.yaml), [`kustomize-build-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kustomize-build-ci.yaml).

GHCR hosts 10 service images (one per service, excluding `loadgenerator`) and 1 Helm chart OCI artifact:

```
ghcr.io/ibtisam-iq/microservices-demo/frontend:latest
ghcr.io/ibtisam-iq/microservices-demo/cartservice:latest
ghcr.io/ibtisam-iq/microservices-demo/checkoutservice:latest
ghcr.io/ibtisam-iq/microservices-demo/currencyservice:latest
ghcr.io/ibtisam-iq/microservices-demo/emailservice:latest
ghcr.io/ibtisam-iq/microservices-demo/paymentservice:latest
ghcr.io/ibtisam-iq/microservices-demo/productcatalogservice:latest
ghcr.io/ibtisam-iq/microservices-demo/recommendationservice:latest
ghcr.io/ibtisam-iq/microservices-demo/shippingservice:latest
ghcr.io/ibtisam-iq/microservices-demo/adservice:latest

oci://ghcr.io/ibtisam-iq/onlineboutique:0.10.5
```

Secrets required:

| Secret | Scope | Used By |
|--------|-------|---------|
| `GITHUB_TOKEN` | Auto-provided | All 3 workflows (GHCR login, cache pulls) |
| `GIT_TOKEN` | Fine-grained PAT, `platform-engineering-systems` only | `chart-release.yaml` only |

---

## Next Phase

[Phase 2: AWS Infrastructure](aws-infrastructure.md) covers provisioning the EKS cluster, VPC, and self-managed node groups using Terraform.
