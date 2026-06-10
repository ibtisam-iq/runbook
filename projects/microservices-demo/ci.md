# DevSecOps CI: `microservices-demo`

## Scope & Purpose

This document covers the complete journey of designing, implementing, debugging, and validating a production-grade DevSecOps CI pipeline for [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo), a 10-service polyglot monorepo. It covers every decision made: from forking, analysing and pruning upstream workflows, to building a matrix-driven, security-gated pipeline that ends in a GitOps CD write. Anyone reading this should be able to understand **why** every decision was made, not just what was done.

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

## Phase 1: Fork & Repository Analysis

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
| `ci-main.yaml` | Builds all services unconditionally, pushes to Google Container Registry | **Deleted** | Not monorepo-efficient; pushes to GCR (Google's own registry); no security scanning; replaced by matrix-driven pipeline |
| `ci-pr.yaml` | Triggered on every PR; ran a full rebuild of all services | **Deleted** | Superseded; PR validation is built into `ci-trigger.yaml` natively |
| [`cleanup.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/cleanup.yaml) | Deletes the PR-specific GKE namespace in the staging cluster when a PR closes | **Kept** | Still useful as a reference; not wired into the new pipeline |
| [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml) | Validates Helm chart syntax and rendering | **Kept** | Relevant for GitOps CD phase |
| [`kustomize-build-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kustomize-build-ci.yaml) | Validates Kustomize manifests | **Kept** | Relevant for GitOps CD phase |
| [`kubevious-manifests-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kubevious-manifests-ci.yaml) | Validates manifests with Kubevious | **Kept** | Advisory manifest validation |
| [`terraform-validate-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/terraform-validate-ci.yaml) | Validates Terraform configurations | **Kept** | Infrastructure validation |
| [`install-dependencies.sh`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/install-dependencies.sh) | Helper script for self-hosted runner toolchain setup | **Kept** | Utility script |

!!! note "Correction, `cleanup.yaml` Purpose"
    The upstream `cleanup.yaml` does **not** clean up GHCR packages. Reading the actual file: it triggers on `pull_request` `closed` and runs `kubectl delete namespace pr${PR_NUMBER}` against the upstream staging GKE cluster. It is retained as a reference artifact only, it targets infrastructure (`online-boutique-ci` GCP project, self-hosted runners) that does not exist in this fork, so it never runs successfully here.

!!! danger "Why `ci-main.yaml` and `ci-pr.yaml` Were Deleted"
    The upstream `ci-main.yaml` rebuilt **all** services on every push regardless of which service actually changed. In a 10-service monorepo, this means a typo fix in `frontend/` triggers a full JVM rebuild of `adservice`. That wastes 20–40 CI minutes per push. The replacement matrix-based pipeline builds only changed services.

    Additionally, the upstream files pushed images to Google's own registry (`gcr.io`). The implementation here pushes to **GitHub Container Registry (GHCR)**, the decision rationale is covered in Phase 2.

### 1.4 Net Workflow File State After Fork Cleanup

| File | Status | Role |
|---|---|---|
| [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | ✅ New, written from scratch | Orchestrator |
| [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | ✅ New, written from scratch | Build/scan/push worker |
| [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) | ✅ New, written from scratch | CD manifest update worker |
| [`cleanup.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/cleanup.yaml) | ♻️ Kept from upstream (inactive) | PR namespace cleanup, reference only |
| [`helm-chart-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/helm-chart-ci.yaml) | ♻️ Kept from upstream | Helm chart validation |
| [`kustomize-build-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kustomize-build-ci.yaml) | ♻️ Kept from upstream | Kustomize manifest validation |
| [`kubevious-manifests-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/kubevious-manifests-ci.yaml) | ♻️ Kept from upstream | Kubevious manifest validation |
| [`terraform-validate-ci.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/terraform-validate-ci.yaml) | ♻️ Kept from upstream | Terraform validation |
| [`install-dependencies.sh`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/install-dependencies.sh) | ♻️ Kept from upstream | Toolchain helper |
| `ci-main.yaml` | ❌ Deleted | Replaced |
| `ci-pr.yaml` | ❌ Deleted | Replaced |

---

## Phase 2: Architecture Decisions

### 2.1 Decision: GHCR over Docker Hub or GCR

| Registry | Reason for/against |
|---|---|
| **GHCR (chosen)** | Native GitHub integration; `GITHUB_TOKEN` authenticates both CI push and pull without external secrets; images co-located with source in the same platform; free for public repos |
| Docker Hub | Requires a separate account, a `DOCKERHUB_TOKEN` secret, rate-limiting on pulls; adds external dependency |
| Google Container Registry (GCR) | The upstream used this because it is a Google project; requires a GCP service account key as a secret; unnecessary external cloud dependency for a GitHub-hosted project |

!!! tip "GHCR Authentication in CI"
    `GITHUB_TOKEN` authenticates GHCR push within the build worker, provided the calling workflow grants `packages: write`. See Phase 7, Bug 3: this permission must be granted at the **caller** level, not only inside the reusable worker.

### 2.2 Decision: GitOps Delivery Architecture

Two deployment patterns were evaluated for how a new image tag reaches the running cluster:

#### Pattern 1: Git as Single Source of Truth (Implemented Now)

The CI pipeline writes the new image tag to a file (`image.env`) in the CD repository ([`ibtisam-iq/platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems)). ArgoCD polls the CD repo on a configurable interval (default: 3 minutes). When it detects a changed `image.env`, it reconciles the Deployment to pull the new image from GHCR.

```
CI push → reusable-gitops.yaml writes image.env → ArgoCD polls CD repo
→ detects change → reconciles Deployment → new image pulled from GHCR
```

- **Mechanism:** Git polling (ArgoCD's default sync mode)
- **Latency:** Up to the ArgoCD polling interval (configurable; default 3 minutes)
- **Simplicity:** High, no additional cluster components required
- **Current status:** ✅ Implemented and working

#### Pattern 2: ArgoCD Image Updater (Planned)

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

#### Pattern 3: ArgoCD Push-Model / Instance Sync (Reference)

ArgoCD supports a webhook-based push model where the Git host (GitHub) pushes a notification to ArgoCD the moment a commit lands, eliminating polling latency entirely. This is a refinement of Pattern 1 that removes the polling delay.

- **Mechanism:** GitHub webhook → ArgoCD API server → immediate sync
- **Current status:** 📋 Documented for future consideration

!!! info "Why Pattern 1 Now and Pattern 2 Later"
    Pattern 1 requires no additional cluster components and works correctly with the current ArgoCD installation. The goal at this stage is to validate the full CI-to-CD pipeline end-to-end. Once ArgoCD is deployed and stable, `argocd-image-updater` will be layered on top to make delivery event-driven rather than polling-based.

### 2.3 Decision: Reusable Workflow Architecture Over Monolithic Workflow

The build/scan/push logic could have been inlined inside [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) as a matrix of steps. Instead, it was extracted into [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) called via `workflow_call`. Reasons:

- The same build/scan/push logic can be called from other workflows without duplication.
- A reusable workflow declares its own job-level `permissions:`, keeping the worker's needs self-documented. **Note the constraint:** a reusable workflow can only request permissions **at or below** what the caller grants at its top level, it cannot escalate. See Phase 7, Bug 3.
- Failures in one service's reusable run are isolated and do not affect siblings.

---

## Phase 3: Pipeline Topology

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

!!! note "Path Filter Asymmetry, `push` vs `pull_request`"
    The `push` trigger filters on `src/**` only. The `pull_request` trigger filters on `src/**` **and** `.github/workflows/**`. This is intentional: a change to a workflow file must be validated on the PR that introduces it, but once merged it does not need to re-trigger a build on `main` (no service source changed). A reader auditing the trigger block will notice this asymmetry, it is by design, not an oversight.

!!! tip "PR Builds: Images Are Pushed But CD Is Not Updated"
    PRs trigger build and scan and even push the image (because `push_image` defaults to `true`). However, Job 3 is gated by event type and `github.ref`, so the CD repo is never mutated on unmerged code. This is a deliberate trade-off: having the built image in GHCR from a PR run is useful for manual testing.

---

## Phase 4: Workflow Implementations

### 4.1 [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml): Orchestrator

#### All Jobs Summary

| Job ID | Job Name | Runs On | Needs | Condition | Calls |
|---|---|---|---|---|---|
| `detect-changes` | Detect Changed Services | `ubuntu-24.04` | - | Always | - (inline steps) |
| `build-and-push` | Build · Scan · Push - `${{ matrix.service }}` | Delegated | `detect-changes` | `has_changes == 'true'` | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) |
| `gitops-update` | GitOps - Update CD Manifest Tags | Delegated | `detect-changes`, `build-and-push` | `has_changes == 'true'` AND push/dispatch AND `refs/heads/main` | [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) |

#### Permissions Block

```yaml
permissions:
  contents: read
  packages: write          # GHCR push (delegated to reusable-build.yaml)
  security-events: write   # Trivy SARIF upload (delegated to reusable-build.yaml)
```

!!! danger "Caller Must Grant What the Worker Requests"
    `reusable-build.yaml` declares `packages: write` and `security-events: write` at job level. A reusable workflow **cannot** request more than the calling workflow grants at its top level. The top-level block above is the permission ceiling for every reusable workflow this orchestrator calls. Granting only `contents: read` here, as the file originally did, causes a **Startup failure** before any job runs. Full detail in Phase 7, Bug 3.

#### Concurrency Control

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Cancel-in-progress is scoped to PRs only. On a `push` to `main`, cancelling mid-run could corrupt a partial GHCR push or leave the CD repo half-updated.

#### Job 1: `detect-changes` Step Table

| Step | Action / Command | Key Detail |
|---|---|---|
| Checkout - full history required for git diff range | [`actions/checkout@df4cb1c…`](https://github.com/actions/checkout/releases/tag/v6.0.3) `# v6.0.3` | `fetch-depth: 0` mandatory: shallow clones break `git diff` range |
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

!!! warning "Branch Creation / Empty-SHA Edge Case"
    On the first push to a new branch, `github.event.before` is `0000000000000000000000000000000000000000`. On `workflow_dispatch` it can be empty. A `git diff` against either fails. The guard handles **both**:
    ```bash
    if [[ -z "$BEFORE" || "$BEFORE" == "0000000000000000000000000000000000000000" ]]; then
      BEFORE="HEAD~1"
    fi
    ```
    The `-z "$BEFORE"` empty-string check was added during troubleshooting, the original guard only handled the all-zeros case and would break on dispatch.

#### Job 2: `build-and-push` Key Decisions

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

`fail-fast: false`, a broken `adservice` JVM build must not abort a passing `frontend` Go build. Each service owns its own blast radius.

!!! note "`push_image` Omitted From `with:` By Design"
    `push_image` is not passed by the caller. `reusable-build.yaml` defaults it to `true`. Job 3's `if:` condition is what actually prevents CD updates on PRs, not a per-build flag. Keeping the boolean out of the matrix `with:` block also avoids a class of expression-evaluation pitfalls in matrix + reusable-workflow calls.

#### Job 3: `gitops-update` Conditions

```yaml
if: |
  needs.detect-changes.outputs.has_changes == 'true' &&
  (github.event_name == 'push' || github.event_name == 'workflow_dispatch') &&
  github.ref == 'refs/heads/main'
```

All three conditions must be true simultaneously. The `github.ref` guard prevents accidental CD repo writes from branch pushes.

---

### 4.2 [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml): Build · Scan · Push Worker

#### Inputs

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `service` | string | ✅ | - | Service directory name under `src/` |
| `docker_context` | string | ✅ | - | Docker build context path relative to repo root |
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
| 1 | Checkout - source code | [`actions/checkout@df4cb1c…`](https://github.com/actions/checkout/releases/tag/v6.0.3) `# v6.0.3` | `fetch-depth: 1` (default): no history needed in worker |
| 2a | Trivy - filesystem scan CRITICAL (advisory) | `aquasecurity/trivy-action@v0.24.0` | `exit-code: 0`, advisory |
| 2b | Trivy - filesystem scan HIGH/MEDIUM (advisory, upload report) | `aquasecurity/trivy-action@v0.24.0` | `exit-code: 0`, uploads JSON artifact |
| 2c | Upload Trivy FS report | `actions/upload-artifact@v4.6.0` | `retention-days: 14` |
| 3 | Set up Docker Buildx | `docker/setup-buildx-action@v3.10.0` | Required for `type=gha` cache |
| 4 | Login to GHCR | `docker/login-action@v3.3.0` | Must precede build, cache restore needs auth |
| 5 | Docker Build - load into daemon (scan before push) | `docker/build-push-action@v6.15.0` | `load: true`, `push: false`, `cache-from/to: type=gha,mode=max` |
| 6a | Trivy - image scan OS packages (advisory) | `aquasecurity/trivy-action@v0.24.0` | `vuln-type: os`, `exit-code: 0`, advisory |
| 6b | Trivy - image scan library CRITICAL (gate, currently advisory) | `aquasecurity/trivy-action@v0.24.0` | `vuln-type: library`, `exit-code: 0`, **gate temporarily relaxed (see below)** |
| 6c | Trivy - image scan library HIGH/MEDIUM (advisory, upload report) | `aquasecurity/trivy-action@v0.24.0` | `if: always()`, `exit-code: 0`, uploads JSON artifact |
| 6d | Upload Trivy image report | `actions/upload-artifact@v4.6.0` | `retention-days: 14` |
| 7 | Push to GHCR - versioned + latest tags | `docker push` (shell) | Conditional on `inputs.push_image == true` |
| 8 | Cleanup - remove local Docker images | `docker rmi` (shell) | `if: always()`, prevents runner disk exhaustion |

#### Image Tag Strategy

```
ghcr.io/ibtisam-iq/microservices-demo/<service>:sha-<full-40-char-commit-sha>
ghcr.io/ibtisam-iq/microservices-demo/<service>:latest
```

The `sha-` prefix tag is immutable and traceable to a specific commit. `:latest` is for local development convenience. ArgoCD Image Updater (Pattern 2, when implemented) will track the `sha-` prefix pattern.

!!! danger "Trivy Library-CRITICAL Gate Is Intentionally Relaxed"
    The three image-scan passes (Stages 6a–6c) are split by severity precisely so the library-CRITICAL pass (6b) can act as the **hard gate** while OS-package findings stay advisory. In standard practice, Stage 6b uses `exit-code: 1` so any CRITICAL library CVE fails the build.

    **Current state:** Stage 6b is set to `exit-code: 0`. This is a deliberate, temporary relaxation. The upstream Online Boutique base images carry known CRITICAL CVEs that would block every build during the pipeline build-out phase. Setting `0` lets the pipeline complete end-to-end validation without being gated by vulnerabilities inherited from upstream base images.

    **Required follow-up:** Restore `exit-code: "1"` on Stage 6b once base images are patched/updated or a curated `.trivyignore` is in place. Until then, the "hard gate" is advisory in effect, and that gap is tracked as technical debt, not a claim that the gate is currently enforced.

!!! info "Why `load: true` and `push: false` at Build Time"
    The image must be in the local Docker daemon for Trivy to scan it as a container image (Stage 6). Pushing directly to GHCR first and then pulling back for scanning would require registry authentication and add latency. `load: true` keeps the image local. `push: false` ensures nothing reaches the registry until the scan stages have run.

!!! warning "`load: true` is Incompatible with Multi-Platform Builds"
    All services are `linux/amd64` only in this pipeline. If multi-arch (`linux/arm64`) is ever added, the flow must be split into three separate steps and `load: true` removed.

---

### 4.3 [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml): CD Manifest Update Worker

#### Inputs

| Input | Type | Required | Description |
|---|---|---|---|
| `services` | string | ✅ | JSON array of service names, e.g. `'["frontend","cartservice"]'` |
| `image_tag` | string | ✅ | Image tag to write, e.g. `sha-4ba1fdab…` |

#### All Steps Summary

| Stage | Step Name | Key Detail |
|---|---|---|
| 1 | Clone CD repo - public URL (token withheld from process argv) | `git clone https://github.com/${CD_REPO}.git cd-repo`, token **never** in process argv |
| 2 | Configure git identity and authenticated remote | `git remote set-url origin https://x-access-token:${GIT_TOKEN}@...` set **after** clone |
| 3 | Write updated image tags for all changed services | `jq -r '.[]'` iterates service JSON array; writes `image.env` per service; all writes precede commit |
| 4 | Commit and push - skip if no manifest changed | `git diff --cached --quiet` guard prevents empty commit; `[skip ci]` in message prevents CD repo feedback loop |
| 5 | Clear token from remote URL | `git remote set-url origin https://github.com/${CD_REPO}.git`, token not left in workspace |
| 6 | Cleanup - remove cloned CD repo | `rm -rf cd-repo` runs `if: always()` |

#### CD Manifest Contract

For each changed service, the following file is written to [`ibtisam-iq/platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems):

```
systems/microservices-demo/src/<service>/image.env
```

This path is derived from `CD_BASE_PATH: systems/microservices-demo/src` in the workflow. Full content written per service:

```
IMAGE_TAG=sha-<40-char-commit-sha>
UPDATED_AT=<UTC timestamp, ISO 8601>
UPDATED_BY=github-actions-run-<run_number>
GIT_COMMIT=<full commit sha>
GIT_REPO=ibtisam-iq/microservices-demo
SERVICE=<service>
```

ArgoCD watches `IMAGE_TAG`. When it changes, ArgoCD reconciles the relevant Deployment. The remaining fields are provenance metadata for audit and traceability.

!!! danger "Do NOT Use `GITHUB_TOKEN` for Cross-Repo Push"
    `GITHUB_TOKEN` is scoped to the current repository only. It cannot push commits to a foreign repository. A GitHub PAT with `Contents: Read and Write` on `platform-engineering-systems` is stored as a repository secret named `GIT_TOKEN`. See Phase 7, Bug 4 for the authentication failure encountered when this secret was misconfigured, and Phase 10 for the planned migration to a GitHub App.

!!! info "Why a Single Atomic Commit for All Services"
    If [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) detected three changed services and [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) made one commit per service, ArgoCD would receive three separate polling triggers and run three sequential reconcile cycles. A single commit containing all `image.env` updates results in one reconcile wave, one rollout event across the cluster.

---

## Phase 5: Action Pinning Strategy

Pinning third-party GitHub Actions to immutable commit SHAs is the target standard. Semver tags (e.g., `@v4`) are mutable, they can be silently force-pushed to point at a completely different commit, a known supply-chain attack vector.

!!! warning "Current State, Only `actions/checkout` Is SHA-Pinned"
    Reading the live workflow files, **only `actions/checkout` is pinned to a commit SHA.** Every other action is pinned to a semver tag, not a SHA:

    | Action | Pin in code | Pinned to SHA? |
    |---|---|---|
    | `actions/checkout` | `@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3` | ✅ Yes |
    | `actions/upload-artifact` | `@v4.6.0` | ❌ Tag only |
    | `aquasecurity/trivy-action` | `@v0.24.0` | ❌ Tag only |
    | `docker/setup-buildx-action` | `@v3.10.0` | ❌ Tag only |
    | `docker/login-action` | `@v3.3.0` | ❌ Tag only |
    | `docker/build-push-action` | `@v6.15.0` | ❌ Tag only |

    **Required follow-up:** Convert the five tag-pinned actions to SHA pins using the `uses: action@<sha> # vX.Y.Z` convention, verifying each SHA from the action's official release page. Until that is done, the supply-chain hardening described here is only partially applied. Stating otherwise would overclaim the current security posture.

!!! tip "Annotation Format"
    The convention `uses: action@<sha> # vX.Y.Z` makes the human-readable version visible in code review while enforcing immutability at runtime. To upgrade: find the new release SHA on the action's releases page, update both the SHA and the comment.

---

## Phase 6: Secrets & Permissions Configuration

### Required Secrets

Navigate to **Settings → Secrets and variables → Actions → New repository secret** in [`ibtisam-iq/microservices-demo`](https://github.com/ibtisam-iq/microservices-demo).

| Secret | Value | Required By | Scope |
|---|---|---|---|
| `GIT_TOKEN` | GitHub PAT | [`reusable-gitops.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-gitops.yaml) | `Contents: Read+Write` on `platform-engineering-systems` only |
| `GITHUB_TOKEN` | Auto-provided | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | Auto-scoped to this repo, no manual setup |

!!! tip "PAT Minimum Permissions for `GIT_TOKEN`"
    Use a **fine-grained** PAT. Grant `Contents: Read and Write` on `platform-engineering-systems` only. Do not grant organisation-wide permissions. Set an expiry and rotate on schedule. An empty, expired, or wrong-scoped token produces the exact failure documented in Phase 7, Bug 4.

---

## Phase 7: Bugs Encountered and Resolved

### Bug 1: YAML Parse Failure: Nested Quotes in `description` Fields

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

### Bug 2: Wrong SHA Pinned for `actions/checkout`

**Symptom:** [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) referenced `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2` when v6.0.3 was intended.

**Fix:** Updated both [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) and [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) to:

```yaml
uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
```

!!! danger "Always Verify SHAs from Official Release Pages"
    The correct SHA for `actions/checkout@v6.0.3` is `df4cb1c069e1874edd31b4311f1884172cec0e10`. Verify from the [official releases page](https://github.com/actions/checkout/releases/tag/v6.0.3). Never trust a SHA from memory or from an AI.

---

### Bug 3: Startup Failure: Reusable Worker Requested More Permissions Than the Caller Granted

**Symptom:**
```
Invalid workflow file: .github/workflows/ci-trigger.yaml (Line: 102, Col: 3):
Error calling workflow 'ibtisam-iq/microservices-demo/.github/workflows/reusable-build.yaml@<sha>'.
The nested job 'build-scan-push' is requesting 'packages: write, security-events: write',
but is only allowed 'packages: none, security-events: none'.
Status: Startup failure
```

This was a **static** failure: GitHub rejected the workflow during call-graph validation, before any job ran. The Actions UI showed every job as "Waiting for pending jobs" and zero duration.

**Root cause:** `ci-trigger.yaml` originally declared only:
```yaml
permissions:
  contents: read
```
A called reusable workflow can only request permissions **at or below** the caller's top-level grant, it can narrow, never escalate. `reusable-build.yaml` requests `packages: write` and `security-events: write` at job level, which exceeded the `contents: read`-only ceiling.

**Misdiagnosis along the way:** The first hypotheses were the empty `github.event.before` on dispatch (real, but unrelated to a *startup* failure since that code never runs before startup) and a matrix-plus-reusable-workflow boolean-input limitation. The truncated error message (`Error calling workflow 'ibtisam-iq/microservices-d…'`) hid the real cause until the annotation was expanded with **Show more**, which revealed the permissions line. Lesson: on a startup failure, always expand the full annotation before theorising; the untruncated text names the exact cause.

**Fix:** Raise the ceiling at the top level of `ci-trigger.yaml`:
```yaml
permissions:
  contents: read
  packages: write          # GHCR push (delegated to reusable-build.yaml)
  security-events: write   # Trivy SARIF upload (delegated to reusable-build.yaml)
```

---

### Bug 4: `git push` to CD Repo Fails: Authentication Failed (Exit 128)

**Symptom:** Job 3 (`gitops-update`) reached the commit-and-push step. The local commit was created successfully, then the push failed:
```
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/ibtisam-iq/platform-engineering-systems.git/'
Error: Process completed with exit code 128.
```
All preceding steps (clone, configure remote, write `image.env`, stage, commit) succeeded; only the network push was rejected.

**Root cause:** The `GIT_TOKEN` secret used in the authenticated remote URL was not valid for the push: an empty, expired, or insufficiently-scoped token. When the token resolves to empty, the remote URL becomes `https://x-access-token:@github.com/...`, which GitHub rejects as an invalid username/token. GitHub no longer supports password authentication for Git operations, so any non-token credential fails here.

**Fix (applied):** Created a **fine-grained PAT** with `Contents: Read and Write` scoped to `platform-engineering-systems` only, stored it as the `GIT_TOKEN` repository secret in `microservices-demo`, and re-ran. The push then succeeded and the CD repo received the `image.env` commit.

!!! tip "Diagnosing Exit 128 on Push"
    Exit code 128 from `git push` with the "Password authentication is not supported" message almost always means a missing/empty/expired/wrong-scope token, rather than a workflow logic error. Confirm: (1) the secret exists in the **correct** repo, (2) it is a token (PAT or App token), not a password, (3) it has `Contents: write` on the **target** repo, (4) it has not expired.

---

### Bug 5: `workflow_dispatch` Always Produces `has_changes=false`

**Symptom:** Manually dispatching the workflow via the Actions UI produced a green Job 1 but skipped Jobs 2 and 3 with `has_changes=false`.

**Root cause:** `workflow_dispatch` carries no commit diff. With the empty/zero `before` SHA falling back to `HEAD~1`, a manual dispatch on an unchanged tree produces no `src/**` diff, so the service array is empty.

**Resolution:** This is correct and expected behaviour. To trigger a full three-job run, push a real change inside `src/`. For pipeline validation, a no-op commit was pushed to [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) (commit [`4ba1fda`](https://github.com/ibtisam-iq/microservices-demo/commit/4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6)).

---

## Phase 8: End-to-End Validation

### Validation Commit

To exercise the complete three-job pipeline, a no-op commit touching [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) was pushed to `main`:

```
Commit: 4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6
Message: chore: trigger CI — touch frontend README to test full pipeline run
```

### Observed Results

| Job | Status | Output |
|---|---|---|
| Job 1: Detect Changed Services | ✅ Success | `services=["frontend"]`, `has_changes=true` |
| Job 2: Build · Scan · Push (frontend) | ✅ Success | Image pushed: `ghcr.io/ibtisam-iq/microservices-demo/frontend:sha-4ba1fda…` |
| Job 3: GitOps Update | ✅ Success (after Bug 4 fix) | `systems/microservices-demo/src/frontend/image.env` written in [`platform-engineering-systems`](https://github.com/ibtisam-iq/platform-engineering-systems) |

!!! note "Job 3 Succeeded Only After the PAT Fix"
    On the first validation run, Job 3 failed at the push step (Bug 4). Once the `GIT_TOKEN` PAT was corrected, the re-run completed all three jobs and the atomic `image.env` commit landed in the CD repo.

### Full-Fleet Push: All Service Images to GHCR

The single-service validation above proved the pipeline end to end, but only the `frontend` image existed in GHCR. All 10 shippable services needed their images pushed before the CD/ArgoCD phase could begin. The same technique was repeated: a minor touch to every service directory under `src/` so `detect-changes` emits all 10 names.

```
Commit: 4fc33943fff24fcee0fce0a97fb37ebde804985b
Message: chore: Updating src/ with a minor touch to trigger the ci-trigger.yaml pipeline
```

#### Observed Results

| Job | Status | Detail |
|---|---|---|
| Job 1: Detect Changed Services | ✅ Success (4s) | All 10 services detected |
| Job 2: Build · Scan · Push (x10 matrix) | ✅ Success (10 jobs, 3m 34s total) | All images pushed to GHCR |
| Job 3: GitOps - Update CD Manifests | ✅ Success (4s) | Single atomic commit writing 10 `image.env` files to the CD repo |

Run #7 produced 30 artifacts (three Trivy reports per service: filesystem scan, image scan, and the combined report). Every service image is now available in GHCR at `ghcr.io/ibtisam-iq/microservices-demo/<service>:sha-4fc3394…` and `:latest`.

!!! tip "Why Touch All Services at Once"
    Pushing one commit that changes all 10 service directories validates the matrix fan-out at full scale: parallel builds, independent `fail-fast: false` isolation, and the single atomic GitOps commit writing all 10 `image.env` files in one push. This is the exact production scenario the pipeline was designed for.

---

## Phase 9: Final Commit History

| Commit SHA | File Changed | Change |
|---|---|---|
| [`7dc333d`](https://github.com/ibtisam-iq/microservices-demo/commit/7dc333da1e31289f14d0c7511bc31190cb41c747) | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | Updated `actions/checkout` SHA to v6.0.3 |
| [`1e0b6d5`](https://github.com/ibtisam-iq/microservices-demo/commit/1e0b6d5965b76e7eb5c1eb8c52d3cae46adec7bb) | [`reusable-build.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/reusable-build.yaml) | Updated `actions/checkout` SHA to v6.0.3 |
| [`1acd336`](https://github.com/ibtisam-iq/microservices-demo/commit/1acd3363ab9855a204e333ce01a02c2d2a341e96) | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | Iteration during startup-failure troubleshooting |
| `3f414f6` | [`ci-trigger.yaml`](https://github.com/ibtisam-iq/microservices-demo/blob/main/.github/workflows/ci-trigger.yaml) | Added `packages: write` + `security-events: write` at top level, fixed Startup failure (Bug 3) |
| [`4ba1fda`](https://github.com/ibtisam-iq/microservices-demo/commit/4ba1fdabe34bd06d6b5ec6c62c87d3d06bfd5cd6) | [`src/frontend/README.md`](https://github.com/ibtisam-iq/microservices-demo/blob/main/src/frontend/README.md) | Validation commit, triggered full three-job pipeline run |
| [`4fc3394`](https://github.com/ibtisam-iq/microservices-demo/commit/4fc33943fff24fcee0fce0a97fb37ebde804985b) | All 10 service directories under `src/` | Full-fleet push, built and pushed all service images to GHCR |

---

## Phase 10: Planned Improvements

### 10.1 Migrate CD-Repo Authentication from PAT to a GitHub App (Planned)

The current cross-repo push uses a fine-grained PAT (`GIT_TOKEN`). This works, but a GitHub App is the stronger long-term pattern for production CD writes. Planned migration:

| Dimension | PAT (current) | GitHub App (planned) |
|---|---|---|
| Ownership | Tied to an individual account | Org/account-owned identity, no human dependency |
| Token lifetime | Long-lived until expiry | Short-lived installation token (~1 hour), minted per run |
| Scope | Repo-scoped fine-grained PAT | Installed only on `platform-engineering-systems`, `Contents: write` |
| Rotation | Manual rotation on schedule | Private key rotation only; tokens auto-expire |
| Commit identity | Acting user's identity | App/bot identity, clean audit trail |

**Planned implementation outline:**

1. Create a GitHub App with **Repository → Contents: Read and write**; no webhook required.
2. Generate and download a private key (`.pem`); install the App on `platform-engineering-systems` only.
3. Store `CD_APP_ID` and `CD_APP_PRIVATE_KEY` as secrets in `microservices-demo`.
4. In `reusable-gitops.yaml`, mint a short-lived token at runtime (e.g. `actions/create-github-app-token`), then check out / push to the CD repo with that token instead of the PAT.
5. Forward the App secrets explicitly from `ci-trigger.yaml` rather than relying on `secrets: inherit`, so the worker's secret dependencies are self-documented.

!!! info "Why PAT First, App Later"
    The PAT unblocked end-to-end validation immediately with minimal setup. The GitHub App migration is deferred to the hardening phase, alongside restoring the Trivy hard gate and completing SHA-pinning, all tracked as the production-readiness backlog below.

### 10.2 Restore the Trivy Library-CRITICAL Hard Gate

Set Stage 6b in `reusable-build.yaml` back to `exit-code: "1"` once upstream base images are patched or a curated `.trivyignore` is committed. Until then the CRITICAL gate is advisory in effect (see Phase 4.2).

### 10.3 Complete SHA-Pinning of All Actions

Convert the five tag-pinned actions (Phase 5) to commit-SHA pins to fully close the supply-chain mutability gap.

### 10.4 Layer in ArgoCD Image Updater (Pattern 2)

Once ArgoCD is deployed against `platform-engineering-systems`, add `argocd-image-updater` to move from polling-based to event-driven delivery (see Phase 2.2).

!!! success "Pipeline Status: Validated End-to-End; Hardening In Progress"
    The pipeline has been validated at both single-service and full-fleet scale. All 10 shippable service images were built, Trivy-scanned, and pushed to GHCR (Run #7, commit `4fc3394`). Job 3 wrote atomic `image.env` commits to the CD repo for all services. The core CI-to-CD path is proven. Remaining work before calling it production-hardened: restore the Trivy CRITICAL gate, complete SHA-pinning, and migrate CD-repo auth to a GitHub App. Next functional milestone: deploy ArgoCD, validate that an `image.env` change triggers a live cluster reconcile, then layer on `argocd-image-updater`.