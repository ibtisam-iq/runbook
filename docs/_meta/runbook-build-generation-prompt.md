# Runbook Build Entry Generation Instructions

You are acting as a senior DevOps engineer who documents systems and stacks
built from scratch with precision and discipline. Your task is to read the
entire conversation above and produce one or more runbook entry files for a
personal DevOps knowledge base called the Runbook, maintained at
runbook.ibtisam-iq.com.

This knowledge base is built on the principle that every non-trivial system
built on real infrastructure must be documented immediately, while the context
is fresh, so it can be reproduced exactly on a fresh machine by the same
engineer six months later or by someone encountering it for the first time.

The documentation is a build record, not a tutorial. It answers:
*What was built, what decisions were made, and how is it reproduced?*

From the conversation above:
1. Identify every distinct build artifact or system that warrants a separate runbook entry
2. Determine the correct file path and filename for each (rules in Part 2 and Part 4)
3. Generate each file in full - no placeholders, no omissions
4. Output each file separately, with its full path stated before the content

Apply every rule in this file strictly. Do not invent steps, commands, or
output that did not appear in the conversation. Write only what was built.

---

## Part 1: What a Build Runbook Entry Is

A build runbook entry is **not** documentation written for the sake of having documentation.
It is written immediately after completing a real build, while the context is still fresh,
so that the same system can be reproduced exactly on a fresh machine by the same person six
months later or by someone who has never built it before.

**The test:** *If this system had to be rebuilt from scratch in three months, would every step,
every design decision, and every non-obvious configuration be remembered clearly?
If no, write the entry now. Ten minutes spent writing saves hours later.*

A build runbook entry captures:
- What was built, its purpose, and where it fits in the broader architecture
- The complete bill of materials: every script, file, image, and dependency
- Every configuration decision and the reasoning behind it
- The exact commands to reproduce the build locally and via CI
- How to verify the build succeeded and the system is working correctly
- Non-obvious design choices made during development

A build runbook entry does **not** capture:
- Troubleshooting sessions or debugging flows (those belong in `debug-` entries)
- Step-by-step fixes for things that went wrong during development
- Instructions directed at a reader ("you should", "make sure you")
- Marketing language about why the technology is great

---

## Part 2: Repository Structure

All runbook entries live at the **root level** of the repository, not inside `docs/`.
The `docs/` folder is reserved for MkDocs configuration files and internal meta documentation
that is not published to the website.

The actual content tree is:

```
/ (repository root)
├── index.md                    # site homepage
├── bootstrap/                  # bare-metal node prep, OS-level setup before k8s
├── cloud/                      # AWS (EKS, ECS, EC2, IAM, S3, Route53)
├── containers/                 # Docker, image builds, registries, Compose
├── delivery/                   # CI/CD - Jenkins, GitHub Actions, ArgoCD
├── iac/                        # Infrastructure as Code - Terraform, Ansible
├── incident-response/          # postmortems, outage analysis, recovery procedures
├── kubernetes/
│   ├── addons.md               # cluster add-ons (metrics-server, dashboard, etc.)
│   ├── cni-networking.md       # CNI plugin setup (Flannel, Calico, Cilium)
│   ├── local-lightweight.md    # local clusters (kind, k3s, minikube)
│   ├── self-managed-kubeadm.md # kubeadm cluster bootstrap on bare-metal/EC2
│   ├── autoscaling/            # HPA, VPA, KEDA, cluster autoscaler
│   ├── cluster-setup/          # kubeconfig, contexts, multi-cluster access
│   ├── gitops/                 # ArgoCD, Flux, GitOps patterns
│   ├── networking/             # Gateway API, Ingress, DNS, TLS, service mesh
│   ├── security/               # RBAC, PSA, network policies, secrets management
│   ├── storage/                # PV, PVC, StorageClass, CSI drivers
│   ├── troubleshooting/        # node/pod/network debugging procedures
│   └── workloads/              # deployments, statefulsets, jobs, resource limits
├── linux/                      # shell, networking, systemd, package management
├── networking/                 # host/OS-level networking (not Kubernetes)
├── observability/              # Prometheus, Grafana, Loki, alerting
├── security/                   # SSL/TLS certs, firewall, SSH hardening (host-level)
├── self-hosted/                # Nexus, SonarQube, monitoring stack, reverse proxies
├── storage/                    # host/OS-level storage (not Kubernetes)
├── workstation/                # personal workstation setup (client machines only)
│   ├── windows/                # Windows workstation tooling and configuration
│   └── macos/                  # macOS workstation tooling and configuration
└── docs/                       # MkDocs config + internal meta only (NOT content)
    └── _meta/                  # internal docs not published to the site
```

**How to determine the correct path:**
1. Identify the primary domain from the list above
2. If the artifact is a Docker image or container build, place it under `containers/`
3. If the artifact is a CI/CD pipeline or workflow, place it under `delivery/`
4. If the artifact is a self-hosted tool (Jenkins, SonarQube, Nexus), place it under `self-hosted/`
5. Place entries here only when the subject is the client machine itself - installing or configuring software on a personal Windows or macOS laptop. This covers package managers (Homebrew, Winget), CLI tools, IDEs, dotfiles, and any software installed directly on the developer's machine.
- This folder is not for container builds, server setups, or dev environments that run inside Docker/VMs. A Docker image built for iximiuz Playground is a container artifact. It belongs in `containers/` (for the image build) and `delivery/` (for the CI pipeline). The fact that a tool is used only by the developer does not make it a workstation entry.
7. If the task spans two domains, place it where someone would first look for it
8. Never place new content entries inside `docs/` - that folder is not for runbook entries

---

## Part 3: When to Generate One File vs Multiple

Generate **one file** when the entire build is a single cohesive artifact
(e.g., a single Docker image built and pushed end-to-end, including its CI pipeline).

Generate **multiple files** when the conversation covered genuinely separate build artifacts
that would be looked up independently at different times. Examples:

- Building the Docker image AND configuring the iximiuz playground manifest -> two files
- Building the image AND setting up the GitHub Actions pipeline -> one combined file if
  the pipeline is the canonical build path; separate files if each is complex enough to
  stand alone as a reference
- Two different images built separately -> two files

When multiple files are needed, output each one with its full path:
```
File 1: containers/build-dev-machine-rootfs.md
File 2: delivery/setup-dev-machine-rootfs-ci.md
```

---

## Part 4: File Naming Rules

### The Core Principle

The filename must describe **what was built and what it produces**. The action verb determines
whether this was a build, a setup, a deployment, or a configuration.
Choose the verb that most accurately reflects the nature of the work.

### Verb Guide

| Verb | When to use | Examples |
|---|---|---|
| `build-` | A Docker image or binary artifact assembled from source | `build-ubuntu-rootfs.md`, `build-dev-machine-rootfs.md` |
| `setup-` | An end-to-end environment or system brought to a working state from scratch | `setup-jenkins-server.md`, `setup-nexus-registry.md` |
| `configure-` | A feature or integration added to an existing system | `configure-github-actions-oidc.md`, `configure-sonarqube-quality-gate.md` |
| `deploy-` | A workload or application placed onto a cluster or server | `deploy-bankapp.md`, `deploy-prometheus-stack.md` |
| `install-` | A single tool or binary installed via one or two commands | `install-kubectl.md`, `install-helm.md` |
| `migrate-` | Data or config moved from one system to another | `migrate-pvc-storageclass.md` |
| `harden-` | Security hardening applied to a system or workload | `harden-ssh-access.md` |
| `debug-` | A troubleshooting session that diagnosed and resolved an issue | `debug-cert-manager-http01-challenge.md` |
| `patch-` | A targeted fix applied to an existing running resource | `patch-deployment-hostnetwork.md` |

### Examples of Correct vs Wrong Names

| Wrong | Correct | Why |
|---|---|---|
| `dev-machine.md` | `build-dev-machine-rootfs.md` | Verb + subject + artifact type makes the file self-describing |
| `dockerfile-image.md` | `build-ubuntu-rootfs.md` | Name the artifact produced, not the tool used |
| `github-actions.md` | `setup-dev-machine-rootfs-ci.md` | Describe what the workflow builds, not what runs it |
| `iximiuz-playground.md` | `configure-dev-machine-playground.md` | Verb + what was configured |
| `jenkins.md` | `setup-jenkins-server.md` | Too vague - no verb, no outcome |

### Other Rules

- Lowercase, hyphen-separated only: `build-dev-machine-rootfs.md`
- No version numbers in filenames: versions belong inside the file, not the name
- No `how-to-` prefix: `build-dev-machine-rootfs.md` not `how-to-build-dev-machine-rootfs.md`
- Combined name is acceptable when two tightly coupled build steps are inseparable:
  `build-and-push-dev-machine-rootfs.md`
- No `[cite:XX]` markers

---

## Part 5: Document Structure

Every build runbook entry follows this structure. Sections marked **Required** must always
be present. Sections marked **If applicable** are included only when the content warrants them.

```markdown
# [Subject]: [What Was Built]                     <- Required. Specific, not generic.

## Context                                         <- Required.
## Architecture Overview                           <- Required for non-trivial builds.
## Bill of Materials                               <- Required. Every file, script, image.
## Prerequisites                                   <- Required if dependencies exist.
## Build Procedure                                 <- Required. The core steps.
## Verification                                    <- Required. Always verify.
## Key Design Decisions                            <- Required for non-trivial builds.
## Troubleshooting                                 <- If applicable. Real issues only.
## Related                                         <- If applicable.
```

### Title Format

```
# [Subject]: [What Was Built]
```

Examples:
- `# Dev Machine Rootfs: Interactive DevOps Workstation Image` (correct)
- `# How to Build the Dev Machine Image` (wrong - instructional tone)
- `# Dev Machine Image Build` (acceptable but weaker - no specificity about what it is)

### Section Details

**Context** - Why this artifact was built and where it fits in the broader system.
State the purpose in one or two sentences. Never start with "This guide..." or "In this tutorial...".

**Architecture Overview** - The component map: what files exist, what each does, how they
connect to produce the final artifact. Include the directory tree if relevant. A Mermaid
diagram is appropriate for complex multi-component builds.

**Bill of Materials** - A complete list of every file, script, dependency, and external
resource the build depends on. Use a table if there are more than four items. This section
ensures someone reproducing the build knows exactly what must exist before a single command is run.

**Prerequisites** - What must already exist and be accessible before starting:
upstream images, secrets, tool versions, network access, registry permissions.

**Build Procedure** - The exact commands to reproduce the build, in order. Split into
named sub-steps if the procedure has distinct phases (local build, local validation, CI push).
Each non-obvious command must be followed immediately by a `>` blockquote explaining why.

**Verification** - How to confirm the build succeeded. Always include:
1. The exact command used to verify
2. The exact expected output
3. What a failing output looks like and what it means

**Key Design Decisions** - Non-obvious architectural or configuration choices made during
the build. Explain what was considered, what was chosen, and why. This section is what
separates a build record from a mere procedure list.

**Troubleshooting** - Only real issues encountered during the build. Not fabricated
"common errors". Each entry needs: the exact symptom, the cause, the exact fix applied.

---

## Part 6: Writing Rules

### Tone

This is a build record. It is not a tutorial. It is not directed at a reader.
Write in third-person present tense (stating facts about the system) or past tense
(what happened during the build). Never second-person.

**DO write like this:**
> The Dev Machine Dockerfile inherits from `ubuntu-24-04-rootfs` and layers toolchain
> installation, shell customization, and a welcome banner on top of the base image.

> The `USER` build argument is set to `ibtisam` in both local builds and CI to ensure the
> interactive user inside the container matches the documented default.

**DO NOT write like this:**
> You need to set the USER build arg before running docker build.
> Make sure you have Docker installed before proceeding.
> This guide will walk you through building the image step by step.

### Explaining the "Why"

Every non-obvious step, configuration value, or design choice must include a reason.
The reason goes inline as a `>` blockquote immediately after the command or decision it explains.

````markdown
```bash
docker build \
  --build-arg USER="ibtisam" \
  -t "${IMAGE_NAME}" \
  .
```

> **Why only USER here:** The Dockerfile exposes `USER`, `BUILD_DATE`, and `VCS_REF`.
> CI injects `BUILD_DATE` and `VCS_REF` via the metadata action. Local builds only
> need `USER` because build metadata is not relevant for local testing.
````

### Architecture Overview Format

For image builds, the Architecture Overview should include:
1. The source tree (directory listing) showing all files involved
2. A brief role description for each file
3. The build chain: what depends on what, in what order

```markdown
## Architecture Overview

The image is assembled from a Dockerfile and a set of provisioning scripts:

```
iximiuz/rootfs/dev/machine/
├── Dockerfile                  # Multi-stage image definition
├── README.md                   # Tool reference and alias map
├── welcome                     # Login banner copied to $HOME/.welcome
└── scripts/
    ├── install-docker.sh       # Docker CE install and user group setup
    ├── install-tools.sh        # Full DevOps toolchain installation
    ├── install-cloudflared.sh  # Cloudflare Tunnel CLI
    ├── setup-completions.sh    # Bash completions for major CLIs
    └── customize-bashrc.sh     # Aliases and helper functions
```

Build chain: `ubuntu-24-04-rootfs` (base) → scripts execute in `USER root` context →
ownership fixed → switched to `USER $USER` → welcome banner + bashrc customized →
image tagged and pushed to GHCR via GitHub Actions.
```

### Bill of Materials Format

```markdown
## Bill of Materials

| File | Role |
|---|---|
| `Dockerfile` | Defines the full image build: base, scripts, ownership fix, welcome, metadata labels |
| `scripts/install-docker.sh` | Installs Docker CE and adds `$USER` to the docker group |
| `scripts/install-tools.sh` | Installs runtimes, Kubernetes CLIs, IaC tools, security scanners |
| `scripts/install-cloudflared.sh` | Installs Cloudflare Tunnel CLI |
| `scripts/setup-completions.sh` | Registers bash completions for kubectl, docker, helm, etc. |
| `scripts/customize-bashrc.sh` | Appends aliases and helper functions to `~/.bashrc` |
| `welcome` | Login banner advertising tools and shortcuts |
| `.github/workflows/build-dev-machine-rootfs.yml` | GitHub Actions workflow for CI builds |
| `iximiuz/manifests/dev-machine.yml` | iximiuz Labs playground manifest |
```

### Real Output

Include the actual terminal output from the session, not placeholder text.

````markdown
Expected output:
```text
ibtisam@dev-machine:~ $ docker --version
Docker version 27.3.1, build ce12230
ibtisam@dev-machine:~ $ kubectl version --client
Client Version: v1.31.0
```
````

Never write `<your output here>` or `You should see something like:`.
Use only the actual output from the conversation.

### Comparison Tables

When two or more approaches differ in important ways, use a table, not prose.

```markdown
| | Local Build | CI Build (GitHub Actions) |
|---|---|---|
| **Trigger** | Manual `docker build` | Push to `main` or PR on path filter |
| **Platforms** | Host arch only | `linux/amd64,linux/arm64` |
| **Tags** | Manual `-t` flag | `latest`, `sha-*`, date tag via metadata-action |
| **BUILD_DATE / VCS_REF** | Not injected | Injected via `docker/metadata-action` |
```

### Admonitions

```markdown
> **Why this matters:** ...
> **Important:** ...
> **Note:** ...
> **Warning:** ...
```

No emoji in headings or admonitions.

### Code Blocks

- Always specify the language: ` ```bash `, ` ```yaml `, ` ```text `
- Use ` ```text ` for terminal output, never ` ```bash ` for output
- Define variables at the top of a block before using them

### What to Omit

- Version numbers in section headings
- Obvious steps that need no explanation (e.g., "clone the repository")
- Marketing language ("powerful", "seamless", "robust", "production-grade")
- Future tense ("this will allow", "once built, you can")
- Sentences starting with "In this guide" / "This tutorial" / "Follow these steps"
- The em dash character anywhere in the document - use a colon or plain hyphen instead
- Narrative of what went wrong during development (unless it produced a lasting design decision)

---

## Part 7: Verification Section Rules

Every entry must include a verification section with:
1. The exact command used to confirm success
2. The exact expected output from the session
3. What a failing output looks like and what it means

````markdown
## Verification

### Image present in GHCR

```bash
skopeo inspect docker://ghcr.io/ibtisam-iq/dev-machine-rootfs:latest \
  | jq '.Name,.Labels."org.opencontainers.image.title"'
```

Expected:
```text
"ghcr.io/ibtisam-iq/dev-machine-rootfs"
"Dev Machine Rootfs"
```

`org.opencontainers.image.title` present confirms OCI metadata was injected correctly.
If the label is missing, the `docker/metadata-action` step did not run or the `labels`
build-arg was not passed to `docker/build-push-action`.
````

---

## Part 8: Troubleshooting Section Rules

Include only issues that were actually encountered during the build. Do not fabricate errors.

Each entry needs:
1. The exact error or symptom observed
2. What caused it
3. The exact fix applied

````markdown
## Troubleshooting

### Tools missing despite successful build

**Symptom:** `trivy` or `gitleaks` not found inside the container after a successful build.
**Cause:** `install-tools.sh` did not run to completion, or the script was not copied
as executable before execution.
**Fix:**
```bash
docker build --no-cache -t "${IMAGE_NAME}" .
```
Check build logs around the `RUN /tmp/scripts/install-tools.sh` step for the failure.
````

---

## Part 9: Quick Reference Card

| Rule | Correct | Wrong |
|---|---|---|
| Title format | `# Subject: What Was Built` | `# How to Build X` |
| Tone | Operational, no second-person | "You need to...", "Follow these steps" |
| Why explanations | Inline `>` blockquote after the command | Buried in prose |
| Terminal output | Actual output from the session | `<your output here>` |
| Comparisons | Markdown table | Prose list of differences |
| Troubleshooting | Real issues encountered only | Fabricated common errors |
| Verification | Command + expected output + failure meaning | "Run this to check" |
| File location | Root-level domain folder (e.g., `containers/`, `self-hosted/`) | Inside `docs/` |
| Verb in filename | Matches the artifact type (`build-`, `setup-`, `configure-`) | Generic or tool-named |
| Code language | Always specified (`bash`/`yaml`/`text`) | Bare triple backtick |
| Root folder structure | Fixed - never add new root domains | `dev-machine/` at root |
| `docs/` folder usage | Internal meta only - no runbook entries | `docs/containers/build-image.md` |
| External links | Official project sources only, always hyperlinked | Blog posts, Medium articles |
| Design decisions | Explain what was chosen and why | Just stating what was done |

---

## Part 10: Placement, Boundary, and Link Rules

### Rule 1: Root Folder Structure is Immutable

The root-level domain folders are fixed. They will not change, and no new root-level folder
will ever be created. The complete set is defined in Part 2.

Sub-folders inside each domain are not fixed. They can be created, renamed, or nested deeper
as content demands.

**Decision flow when placing a new file:**
1. Identify the correct root domain folder from the list in Part 2
2. Determine the appropriate sub-folder inside that domain
3. If that sub-folder does not exist yet, create it - this is expected and correct
4. Place the file inside the sub-folder

**What is never allowed:**
- Creating a new root-level folder alongside the existing domains
- Placing a file directly at the repository root (except `index.md`)

```
CORRECT: containers/build-dev-machine-rootfs.md
CORRECT: delivery/setup-dev-machine-rootfs-ci.md
WRONG:   dev-machine/build-rootfs.md
WRONG:   iximiuz/build-dev-machine.md
```

---

### Rule 2: The `docs/` Folder Never Contains Runbook Content

The `docs/` folder exists solely for MkDocs configuration, navigation definitions, and internal
meta documentation. It is not served as content on the website.

```
CORRECT: containers/build-dev-machine-rootfs.md
CORRECT: self-hosted/setup-jenkins-server.md
WRONG:   docs/containers/build-dev-machine-rootfs.md
WRONG:   docs/self-hosted/setup-jenkins-server.md
```

---

### Rule 3: Official Links Only, All Hyperlinked

When writing a build runbook entry, every external resource referenced must be included
as a hyperlink.

**Only official sources are linked:**
- The official GitHub repository of the tool, image, or library
- The official documentation site published by the project itself

**Never link:**
- Stack Overflow answers
- Medium or blog posts
- Third-party tutorials or unofficial guides

Links go in the `## Related` section at the bottom of the entry, or inline as hypertext
on the first mention of the resource within the document body.

---

## Part 11: Build Entry vs Debug Entry - The Boundary

This prompt generates **build entries** only. The boundary is clear:

| Type | Use `runbook-build-generation-prompt.md` | Use `runbook-generation-prompt.md` |
|---|---|---|
| **Subject** | A system, image, pipeline, or stack that was designed and built | A problem that appeared on existing infrastructure |
| **Verb** | `build-`, `setup-`, `configure-`, `deploy-` | `debug-`, `patch-`, `migrate-` |
| **Narrative arc** | Design -> Build -> Verify | Symptom -> Diagnosis -> Fix |
| **Primary value** | Reproducibility of the artifact | Preventing recurrence of the incident |
| **Example** | `build-dev-machine-rootfs.md` | `debug-cert-manager-http01-challenge.md` |

When a conversation contains **both** a build and a debugging session that happened during
development, generate two files: one build entry (using this prompt) and one debug entry
(using `runbook-generation-prompt.md`). Do not merge them.
