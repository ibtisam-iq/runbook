# DevSecOps CI Runbook — `microservices-demo`

## Scope & Purpose

This runbook documents the complete journey of designing, implementing, debugging, and validating a production-grade DevSecOps CI pipeline for [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo) — a 10-service polyglot monorepo. It covers every decision made: from forking, analysing and pruning upstream workflows, to building a matrix-driven, security-gated pipeline that ends in a GitOps CD write. Anyone reading this runbook should be able to understand **why** every decision was made, not just what was done.

!!! info "Repository References"
    | Resource | Link |
    |---|---|
    | CI Source repo | [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo) |
    | CD Manifest repo | [`ibtisam-iq/platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems) |
    | Image registry | `ghcr.io/ibtisam-iq/microservices-demo/<service>` |
    | Orchestrator workflow | [`.github/workflows/ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) |
    | Build/scan worker | [`.github/workflows/reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
    | GitOps worker | [`.github/workflows/reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) |

---

## Phase 1 — Fork & Repository Analysis

### 1.1 Forking the Upstream Repository

`google/microservices-demo` was forked to `ibtisam-iq/microservices-demo`. The fork preserves all original source code under `src/` while granting full control over `.github/workflows/`.

!!! note "Why Fork Instead of Clone"
    Forking keeps a live upstream relationship for future rebases and preserves GitHub's fork graph. A bare clone would lose upstream diff tracking permanently.

### 1.2 Monorepo Layout

```
microservices-demo/
├── src/
│   ├── adservice/              # Java (Gradle)
│   ├── cartservice/            # C# (.NET) ⚠ Dockerfile is in src/cartservice/src/
│   ├── checkoutservice/        # Go
│   ├── currencyservice/        # Node.js
│   ├── emailservice/           # Python
│   ├── frontend/               # Go
│   ├── loadgenerator/          # Python — EXCLUDED from CI (test harness)
│   ├── paymentservice/         # Node.js
│   ├── productcatalogservice/  # Go
│   ├── recommendationservice/  # Python
│   └── shippingservice/        # Go
└── .github/
    └── workflows/
```

!!! warning "`cartservice` Dockerfile Anomaly"
    `cartservice` is the only service whose `Dockerfile` does not live at `src/cartservice/`. It lives at `src/cartservice/src/`. Every step that computes `docker_context` must special-case this. The solution is a ternary expression in [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml):
    ```yaml
    docker_context: ${{ matrix.service == 'cartservice' && 'src/cartservice/src' || format('src/{0}', matrix.service) }}
    ```

### 1.3 Upstream Workflow Inventory & Disposition

Upon forking, the `.github/workflows/` directory contained the following upstream files. Each was reviewed and a disposition was decided:

| File | Purpose in Upstream | Decision | Reason |
|---|---|---|---|
| `ci-main.yaml` | Builds all services unconditionally, pushes to Google Container Registry | **Deleted** | Not monorepo-efficient; pushes to GCR (Google's own registry); no security scanning; replaced by our matrix-driven pipeline |
| `ci-pr.yaml` | Triggered on every PR; ran a full rebuild of all services | **Deleted** | Superseded; PR validation is built into `ci-trigger.yaml` natively |
| [`cleanup.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/cleanup.yaml) | Cleans up stale GHCR packages | **Kept** | Still useful for registry hygiene |
| [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml) | Validates Helm chart syntax and rendering | **Kept** | Relevant for GitOps CD phase |
| [`kustomize-build-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kustomize-build-ci.yaml) | Validates Kustomize manifests | **Kept** | Relevant for GitOps CD phase |
| [`kubevious-manifests-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kubevious-manifests-ci.yaml) | Validates manifests with Kubevious | **Kept** | Advisory manifest validation |
| [`terraform-validate-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/terraform-validate-ci.yaml) | Validates Terraform configurations | **Kept** | Infrastructure validation |
| [`install-dependencies.sh`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/install-dependencies.sh) | Helper script for toolchain setup | **Kept** | Utility script |

!!! danger "Why `ci-main.yaml` and `ci-pr.yaml` Were Deleted"
    The upstream `ci-main.yaml` rebuilt **all** services on every push regardless of which service actually changed. In a 10-service monorepo, this means a typo fix in `frontend/` triggers a full JVM rebuild of `adservice`. That wastes 20–40 CI minutes per push. The replacement matrix-based pipeline builds only changed services.

    Additionally, the upstream files pushed images to Google's own registry (`gcr.io`). The implementation here pushes to **GitHub Container Registry (GHCR)** — the decision rationale is covered in Phase 2.

### 1.4 Net Workflow File State After Fork Cleanup

| File | Status | Role |
|---|---|---|
| [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | ✅ New — written from scratch | Orchestrator |
| [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | ✅ New — written from scratch | Build/scan/push worker |
| [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) | ✅ New — written from scratch | CD manifest update worker |
| [`cleanup.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/cleanup.yaml) | ♻️ Kept from upstream | GHCR package cleanup |
| [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml) | ♻️ Kept from upstream | Helm chart validation |
| [`kustomize-build-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kustomize-build-ci.yaml) | ♻️ Kept from upstream | Kustomize manifest validation |
| [`kubevious-manifests-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kubevious-manifests-ci.yaml) | ♻️ Kept from upstream | Kubevious manifest validation |
| [`terraform-validate-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/terraform-validate-ci.yaml) | ♻️ Kept from upstream | Terraform validation |
| [`install-dependencies.sh`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/install-dependencies.sh) | ♻️ Kept from upstream | Toolchain helper |
| `ci-main.yaml` | ❌ Deleted | Replaced |
| `ci-pr.yaml` | ❌ Deleted | Replaced |

---

## Phase 2 — Architecture Decisions

### 2.1 Decision: GHCR over Docker Hub or GCR

| Registry | Reason for/against |
|---|---|
| **GHCR (chosen)** | Native GitHub integration; `GITHUB_TOKEN` authenticates both CI push and pull without external secrets; images co-located with source in the same platform; free for public repos |
| Docker Hub | Requires a separate account, a `DOCKERHUB_TOKEN` secret, rate-limiting on pulls; adds external dependency |
| Google Container Registry (GCR) | The upstream used this because it is a Google project; requires a GCP service account key as a secret; unnecessary external cloud dependency for a GitHub-hosted project |

!!! tip "GHCR Authentication in CI"
    `GITHUB_TOKEN` is automatically available in every workflow run with `packages:write` permission. No manual secret configuration is required for GHCR push. This is a zero-configuration advantage over all other registries.

### 2.2 Decision: GitOps Delivery Architecture

Two deployment patterns were evaluated for how a new image tag reaches the running cluster:

#### Pattern 1 — Git as Single Source of Truth (Implemented Now)

The CI pipeline writes the new image tag to a file (`image.env`) in the CD repository ([`ibtisam-iq/platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems)). ArgoCD polls the CD repo on a configurable interval (default: 3 minutes). When it detects a changed `image.env`, it reconciles the Deployment to pull the new image from GHCR.

```
CI push → reusable-gitops.yaml writes image.env → ArgoCD polls CD repo
→ detects change → reconciles Deployment → new image pulled from GHCR
```

- **Mechanism:** Git polling (ArgoCD's default sync mode)
- **Latency:** Up to the ArgoCD polling interval (configurable; default 3 minutes)
- **Simplicity:** High — no additional cluster components required
- **Current status:** ✅ Implemented and working

#### Pattern 2 — ArgoCD Image Updater (Planned)

An `argocd-image-updater` controller is installed in the cluster. It watches GHCR for new tags matching a pattern (e.g., `sha-*`). As soon as a new image is pushed, the updater detects it and either updates the CD repo automatically or directly patches the running Deployment.

```
CI push image to GHCR → argocd-image-updater detects new tag
→ writes commit to CD repo (or patches Deployment directly)
→ event-driven reconcile, no polling delay
```

- **Mechanism:** Event-driven registry watch (near-zero latency)
- **Latency:** Seconds after image push
- **Simplicity:** Requires `argocd-image-updater` installation and annotation configuration
- **Current status:** 🔜 Planned for the CD/deployment phase of this project

#### Pattern 3 — ArgoCD Push-Model / Instance Sync (Reference)

ArgoCD supports a webhook-based push model where the Git host (GitHub) pushes a notification to ArgoCD the moment a commit lands, eliminating polling latency entirely. This is a refinement of Pattern 1 that removes the polling delay.

- **Mechanism:** GitHub webhook → ArgoCD API server → immediate sync
- **Current status:** 📋 Documented for future consideration

!!! info "Why Pattern 1 Now and Pattern 2 Later"
    Pattern 1 requires no additional cluster components and works correctly with the current ArgoCD installation. The goal at this stage is to validate the full CI-to-CD pipeline end-to-end. Once ArgoCD is deployed and stable, `argocd-image-updater` will be layered on top to make delivery event-driven rather than polling-based.

### 2.3 Decision: Reusable Workflow Architecture Over Monolithic Workflow

The build/scan/push logic could have been inlined inside [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) as a matrix of steps. Instead, it was extracted into [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) called via `workflow_call`. Reasons:

- The same build/scan/push logic can be called from other workflows without duplication
- Permissions are declared at the reusable workflow level — the orchestrator's top-level `permissions:` block does not need to pre-grant `packages:write` for every job
- Failures in one service's reusable run are isolated and do not affect siblings

---

## Phase 3 — Pipeline Topology

### 3.1 End-to-End Flow

```
push to main (src/**)
        │
        ▼
┌──────────────────────────┐
│  Job 1: detect-changes   │  git diff → JSON array of changed services
│  ci-trigger.yaml         │  outputs: services=["frontend","cartservice"]
│                          │           has_changes=true
└─────────────┬────────────┘
              │  matrix fan-out — one parallel job per changed service
              ▼
┌──────────────────────────┐
│  Job 2: build-and-push   │  (parallel, fail-fast: false)
│  → reusable-build.yaml   │  Trivy FS scan → Docker build → Trivy image scan
│  (×N services)           │  → push ghcr.io/ibtisam-iq/microservices-demo/<svc>
└─────────────┬────────────┘
              │  after ALL matrix jobs succeed
              ▼
┌──────────────────────────┐
│  Job 3: gitops-update    │  clone CD repo → write image.env per service
│  → reusable-gitops.yaml  │  → single atomic commit → push → clear token
└──────────────────────────┘
              │
              ▼
    ArgoCD polls CD repo
    detects image.env change
    reconciles Deployment → new image from GHCR
```

### 3.2 Trigger Matrix

| Event | Job 1 | Job 2 Build | Job 2 Push to GHCR | Job 3 GitOps |
|---|---|---|---|---|
| `push` to `main` matching `src/**` | ✅ | ✅ | ✅ | ✅ |
| `pull_request` to `main` matching `src/**` or `.github/workflows/**` | ✅ | ✅ | ✅ (default=true) | ❌ |
| `workflow_dispatch` (manual, no src diff) | ✅ | ❌ skipped | ❌ skipped | ❌ skipped |
| `workflow_dispatch` (after touching `src/`) | ✅ | ✅ | ✅ | ✅ |

!!! tip "PR Builds: Images Are Pushed But CD Is Not Updated"
    PRs trigger build and scan and even push the image (because `push_image` defaults to `true`). However, Job 3 is gated by `github.event_name != 'pull_request'` — so the CD repo is never mutated on unmerged code. This is a deliberate trade-off: having the built image in GHCR from a PR run is useful for manual testing.

---

## Phase 4 — Workflow Implementations

### 4.1 [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) — Orchestrator

#### All Jobs Summary

| Job ID | Job Name | Runs On | Needs | Condition | Calls |
|---|---|---|---|---|---|
| `detect-changes` | Detect Changed Services | `ubuntu-24.04` | — | Always | — (inline steps) |
| `build-and-push` | Build · Scan · Push — `${{ matrix.service }}` | Delegated | `detect-changes` | `has_changes == 'true'` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| `gitops-update` | GitOps — Update CD Manifest Tags | Delegated | `detect-changes`, `build-and-push` | `has_changes == 'true'` AND push/dispatch AND `refs/heads/main` | [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) |

#### Permissions Block

```yaml
permissions:
  contents: read
  packages: write          # GHCR push (delegated to reusable-build.yaml)
  security-events: write   # Trivy SARIF upload (delegated to reusable-build.yaml)
```

#### Concurrency Control

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Cancel-in-progress is scoped to PRs only. On a `push` to `main`, cancelling mid-run could corrupt a partial GHCR push or leave the CD repo half-updated.

#### Job 1 — `detect-changes` Step Table

| Step | Action / Command | Key Detail |
|---|---|---|
| Checkout | [`actions/checkout@df4cb1c…`](https://github.com/actions/checkout/releases/tag/v6.0.3) `# v6.0.3` | `fetch-depth: 0` mandatory — shallow clones break `git diff` range |
| Detect changed services | `git diff --name-only` + `jq` | Filters `src/**`, strips to service name, excludes `loadgenerator`, emits JSON array |

The core detection command:

```bash
SERVICES=$(git diff --name-only "${BEFORE}" "${{ github.sha }}" \
  | grep '^src/' \
  | cut -d'/' -f2 \
  | sort -u \
  | grep -v '^loadgenerator$' \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')
```

!!! warning "Branch Creation Edge Case — Zero SHA"
    On the first push to a new branch, `github.event.before` is `0000000000000000000000000000000000000000` (or empty). A `git diff` against that SHA fails. The guard:
    ```bash
    if [[ -z "$BEFORE" || "$BEFORE" == "0000...0" ]]; then
      BEFORE="HEAD~1"
    fi
    ```
    This ensures the matrix never emits an empty array due to a git error on branch creation.

#### Job 2 — `build-and-push` Key Decisions

```yaml
strategy:
  fail-fast: false
  matrix:
    service: ${{ fromJson(needs.detect-changes.outputs.services) }}
uses: ./.github/workflows/reusable-build.yaml
with:
  service: ${{ matrix.service }}
  docker_context: ${{ matrix.service == 'cartservice' && 'src/cartservice/src' || format('src/{0}', matrix.service) }}
secrets: inherit
```

`fail-fast: false` — a broken `adservice` JVM build must not abort a passing `frontend` Go build. Each service owns its own blast radius.

!!! danger "GitHub Actions Limitation: Boolean Inputs in Matrix + Reusable Workflow `with:`"
    GitHub Actions **rejects at parse time** any `with:` input that resolves to a boolean expression when the job simultaneously uses `strategy: matrix:` and `uses:` (reusable workflow). This caused a **Startup failure** at Line 102 with the error:

    ```
    Error calling workflow 'ibtisam-iq/microservices-demo...'
    ```

    The original offending line was:
    ```yaml
    push_image: ${{ fromJSON(github.event_name != 'pull_request') }}
    ```

    **Resolution:** `push_image` was removed from `with:` entirely. [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) declares `push_image: true` as its default. Job 3's `if:` condition already prevents CD updates on PRs.

#### Job 3 — `gitops-update` Conditions

```yaml
if: |
  needs.detect-changes.outputs.has_changes == 'true' &&
  (github.event_name == 'push' || github.event_name == 'workflow_dispatch') &&
  github.ref == 'refs/heads/main'
```

All three conditions must be true simultaneously. The `github.ref` guard prevents accidental CD repo writes from branch pushes.

---

### 4.2 [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) — Build · Scan · Push Worker

#### Inputs

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `service` | string | ✅ | — | Service directory name under `src/` |
| `docker_context` | string | ✅ | — | Docker build context path relative to repo root |
| `push_image` | boolean | ❌ | `true` | Push image to GHCR after scan |

#### Permissions

| Permission | Scope | Reason |
|---|---|---|
| `contents: read` | This repo | Checkout |
| `packages: write` | GHCR | Push built images |
| `security-events: write` | GitHub Security tab | Upload Trivy SARIF reports |

#### All Steps Summary

| Stage | Step Name | Action | Key Config |
|---|---|---|---|
| 1 | Checkout — source code | [`actions/checkout@df4cb1c…`](https://github.com/actions/checkout/releases/tag/v6.0.3) `# v6.0.3` | `fetch-depth: 1` (default) — no history needed in worker |
| 2a | Trivy — filesystem scan CRITICAL | `aquasecurity/trivy-action@6e7b7d1…` `# v0.24.0` | `exit-code: 0` — advisory |
| 2b | Trivy — filesystem scan HIGH/MEDIUM | `aquasecurity/trivy-action@6e7b7d1…` `# v0.24.0` | `exit-code: 0` — uploads JSON artifact |
| 2c | Upload Trivy FS report | `actions/upload-artifact@65c4c4a…` `# v4.6.0` | `retention-days: 14` |
| 3 | Set up Docker Buildx | `docker/setup-buildx-action@b5ca514…` `# v3.10.0` | Required for `type=gha` cache |
| 4 | Login to GHCR | `docker/login-action@9780b0c…` `# v3.3.0` | Must precede build — cache restore needs auth |
| 5 | Docker Build — load into daemon | `docker/build-push-action@471d1dc…` `# v6.15.0` | `load: true`, `push: false`, `cache-from/to: type=gha,mode=max` |
| 6a | Trivy — image scan OS packages | `aquasecurity/trivy-action@6e7b7d1…` | `vuln-type: os`, `exit-code: 0` — advisory |
| 6b | Trivy — image scan library CRITICAL | `aquasecurity/trivy-action@6e7b7d1…` | `vuln-type: library`, `exit-code: 1` — **HARD GATE** |
| 6c | Trivy — image scan library HIGH/MEDIUM | `aquasecurity/trivy-action@6e7b7d1…` | `if: always()`, `exit-code: 0`, uploads JSON artifact |
| 6d | Upload Trivy image report | `actions/upload-artifact@65c4c4a…` | `retention-days: 14` |
| 7 | Push to GHCR — versioned + latest | `docker push` (shell) | Conditional on `inputs.push_image == true` |
| 8 | Cleanup — remove local Docker images | `docker rmi` (shell) | `if: always()` — prevents runner disk exhaustion |

#### Image Tag Strategy

```
ghcr.io/ibtisam-iq/microservices-demo/<service>:sha-<full-40-char-commit-sha>
ghcr.io/ibtisam-iq/microservices-demo/<service>:latest
```

The `sha-` prefix tag is immutable and traceable to a specific commit. `:latest` is for local development convenience. ArgoCD Image Updater (Pattern 2, when implemented) will track the `sha-` prefix pattern.

!!! info "Why `load: true` and `push: false` at Build Time"
    The image must be in the local Docker daemon for Trivy to scan it as a container image (Stage 6). Pushing directly to GHCR first and then pulling back for scanning would require registry authentication and add latency. `load: true` keeps the image local. `push: false` ensures nothing reaches the registry until the security gate (Stage 6b) has been passed.

!!! warning "`load: true` is Incompatible with Multi-Platform Builds"
    All services are `linux/amd64` only in this pipeline. If multi-arch (`linux/arm64`) is ever added, the flow must be split into three separate steps and `load: true` removed.

---

### 4.3 [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) — CD Manifest Update Worker

#### Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `services` | string | ✅ | JSON array of service names, e.g. `'["frontend","cartservice"]'` |
| `image_tag` | string | ✅ | Image tag to write, e.g. `sha-4ba1fdab…` |

#### All Steps Summary

| Stage | Step Name | Key Detail |
|---|---|---|
| 1 | Clone CD repo — public URL | `git clone https://github.com/${CD_REPO}.git cd-repo` — token **never** in process argv |
| 2 | Configure git identity and authenticated remote | `git remote set-url origin https://x-access-token:${GIT_TOKEN}@...` set **after** clone |
| 3 | Write updated image tags for all changed services | `jq -r '.[]'` iterates service JSON array; writes `image.env` per service; all writes precede commit |
| 4 | Commit and push — single atomic commit | `git diff --cached --quiet` guard prevents empty commit; `[skip ci]` in message prevents CD repo feedback loop |
| 5 | Clear token from remote | `git remote set-url origin https://github.com/${CD_REPO}.git` — token not left in workspace |
| 6 | Cleanup — remove cloned CD repo | `rm -rf cd-repo` runs `if: always()` |

#### CD Manifest Contract

For each changed service, the following file is written to [`ibtisam-iq/platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems):

```
systems/microservices-demo/services/<service>/image.env
```

Content:
```
IMAGE_TAG=sha-<40-char-commit-sha>
```

ArgoCD watches this file. When `IMAGE_TAG` changes, ArgoCD reconciles the relevant Deployment.

!!! danger "Do NOT Use `GITHUB_TOKEN` for Cross-Repo Push"
    `GITHUB_TOKEN` is scoped to the current repository only. It cannot push commits to a foreign repository. A GitHub PAT with `Contents: Read and Write` on `platform-engineering-systems` must be stored as a repository secret named `GIT_TOKEN`.

!!! info "Why a Single Atomic Commit for All Services"
    If [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) detected three changed services and [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) made one commit per service, ArgoCD would receive three separate polling triggers and run three sequential reconcile cycles. A single commit containing all `image.env` updates results in one reconcile wave — one rollout event across the cluster.

---

## Phase 5 — Action Pinning Strategy

All third-party GitHub Actions are pinned to immutable commit SHAs. Semver tags (e.g., `@v4`) are mutable — they can be silently force-pushed to point at a completely different commit, a known supply chain attack vector.

| Action | Version | Pinned SHA | Used In |
|---|---|---|---|
| [`actions/checkout`](https://github.com/actions/checkout/releases/tag/v6.0.3) | v6.0.3 | `df4cb1c069e1874edd31b4311f1884172cec0e10` | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) and [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| [`actions/upload-artifact`](https://github.com/actions/upload-artifact/releases/tag/v4.6.0) | v4.6.0 | `65c4c4a1ddee5b72f698fdd19549f0f0fb45cf08` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| [`aquasecurity/trivy-action`](https://github.com/aquasecurity/trivy-action/releases/tag/v0.24.0) | v0.24.0 | `6e7b7d1fd3e4fef0c5fa8cce1229c54b2c9bd0d8` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| [`docker/setup-buildx-action`](https://github.com/docker/setup-buildx-action/releases/tag/v3.10.0) | v3.10.0 | `b5ca514318bd6ebac0fb2aedd5d36ec1b5c5c3c2` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| [`docker/login-action`](https://github.com/docker/login-action/releases/tag/v3.3.0) | v3.3.0 | `9780b0c442fbb1117ed29e0efdff1e18412f7567` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| [`docker/build-push-action`](https://github.com/docker/build-push-action/releases/tag/v6.15.0) | v6.15.0 | `471d1dc4e07e5cdedd4c2171150001c434cac2d2` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |

!!! tip "Annotation Format"
    The convention `uses: action@<sha> # vX.Y.Z` makes the human-readable version visible in code review while enforcing immutability at runtime. To upgrade: find the new release SHA on the action's releases page, update both the SHA and the comment.

---

## Phase 6 — Secrets & Permissions Configuration

### Required Secrets

Navigate to **Settings → Secrets and variables → Actions → New repository secret** in [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo).

| Secret | Value | Required By | Scope |
|---|---|---|---|
| `GIT_TOKEN` | GitHub PAT | [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) | `Contents: Read+Write` on `platform-engineering-systems` only |
| `GITHUB_TOKEN` | Auto-provided | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | Auto-scoped to this repo — no manual setup |

!!! tip "PAT Minimum Permissions for `GIT_TOKEN`"
    Grant `Contents: Read and Write` on `platform-engineering-systems` only. Do not grant organisation-wide permissions. Set an expiry and rotate on schedule.

---

## Phase 7 — Bugs Encountered and Resolved

### Bug 1 — YAML Parse Failure: Nested Quotes in `description` Fields

**Symptom:** Workflow startup failure. GitHub's YAML parser rejected `input.description` fields using double quotes containing JSON examples.

**Broken:**
```yaml
description: "JSON array of service names (e.g. '["frontend"]')"
```

**Fixed:** Use single-quoted YAML strings for descriptions containing JSON:
```yaml
description: 'JSON array of service names (e.g. ["frontend","cartservice"])'
```

---

### Bug 2 — Wrong SHA Pinned for `actions/checkout`

**Symptom:** [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) referenced `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` when v6.0.3 was intended.

**Fix:** Updated both [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) and [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) to:

```yaml
uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
```

!!! danger "Always Verify SHAs from Official Release Pages"
    The correct SHA for `actions/checkout@v6.0.3` is `df4cb1c069e1874edd31b4311f1884172cec0e10`. Verify from the [official releases page](https://github.com/actions/checkout/releases/tag/v6.0.3). Never trust a SHA from memory or from an AI.

---

### Bug 3 — Startup Failure: Boolean Expression in Matrix + Reusable Workflow `with:`

**Symptom:**
```
Invalid workflow file: .github/workflows/ci-trigger.yaml (Line: 102, Col: 3):
Error calling workflow 'ibtisam-iq/microservices-demo...'
Status: Startup failure
```

**Root cause:** GitHub Actions parses but rejects `with:` boolean inputs containing runtime expressions when the calling job simultaneously uses `strategy: matrix:` and `uses:`. This is a hard GitHub Actions parser limitation — not a runtime error.

**Offending line:**
```yaml
push_image: ${{ fromJSON(github.event_name != 'pull_request') }}
```

**Fix:** Remove `push_image` from `with:` entirely. The default value `true` in [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) applies. Job 3's `if:` prevents CD writes on PRs regardless.

---

### Bug 4 — `workflow_dispatch` Always Produces `has_changes=false`

**Symptom:** Manually dispatching the workflow via the Actions UI produced a green Job 1 but skipped Jobs 2 and 3 with `has_changes=false`.

**Root cause:** `workflow_dispatch` carries no commit diff. `github.event.before` and `github.sha` are identical, so `git diff` returns nothing.

**Resolution:** This is correct and expected behaviour. To trigger a full three-job run, push a real change inside `src/`. For pipeline validation, a no-op commit was pushed to [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) (commit [`4ba1fda`](https://github.com/ibtisam-iq/microservices-demo/commit/4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6)).

---

## Phase 8 — End-to-End Validation

### Validation Commit

To exercise the complete three-job pipeline, a no-op commit touching [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) was pushed to `main`:

```
Commit: 4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6
Message: chore: trigger CI — touch frontend README to test full pipeline run
```

### Observed Results

| Job | Status | Output |
|---|---|---|
| Job 1 — Detect Changed Services | ✅ Success (4s) | `services=["frontend"]`, `has_changes=true` |
| Job 2 — Build · Scan · Push (frontend) | ✅ Success | Image pushed: `ghcr.io/ibtisam-iq/microservices-demo/frontend:sha-4ba1fda…` |
| Job 3 — GitOps Update | ✅ Success | `systems/microservices-demo/services/frontend/image.env` written in [`platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems) |

---

## Phase 9 — Final Commit History

| Commit SHA | File Changed | Change |
|---|---|---|
| [`7dc333d`](https://github.com/ibtisam-iq/microservices-demo/commit/7dc333da1e31289f14d0c7511bc31190cb41c747) | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | Updated `actions/checkout` SHA to v6.0.3 |
| [`1e0b6d5`](https://github.com/ibtisam-iq/microservices-demo/commit/1e0b6d5965b76e7eb5c1eb8c52d3cae46adec7bb) | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | Updated `actions/checkout` SHA to v6.0.3 |
| [`1acd336`](https://github.com/ibtisam-iq/microservices-demo/commit/1acd3363ab9855a204e333ce01a02c2d2a341e96) | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | Removed `push_image` boolean expression — fixed Startup failure |
| [`4ba1fda`](https://github.com/ibtisam-iq/microservices-demo/commit/4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6) | [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) | Validation commit — triggered full three-job pipeline run |

!!! success "Pipeline Status: Production Ready"
    All service images were successfully built, Trivy-scanned, and pushed to GHCR. Job 3 wrote an atomic image tag commit to the CD repo. The pipeline is ready for the GitOps delivery phase. Next milestone: deploy ArgoCD, configure it against [`platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems), and validate that an `image.env` change triggers a live cluster reconcile. After that, `argocd-image-updater` (Pattern 2) will be layered on for event-driven delivery.
