# Runbook Repository — Architecture & Design Decisions

## Overview

This repository is a personal, living knowledge base for DevOps and platform engineering. It is not a tutorial site, not a blog, and not a scratchpad. Every file in this repo was written after the knowledge was earned in production or hands-on practice. The structure is intentional — designed so that any folder name tells you exactly what domain it owns and exactly what kind of content lives inside it.

The goal is simple: when a task comes up — installing a tool, debugging a Kubernetes cluster, setting up a self-hosted service, understanding a new project before containerizing it — the answer should already be here, one folder deep.

---

## Repository Structure

```
runbook/
│
├── assets/
│   ├── diagrams/        ← architecture diagrams, flow charts, system designs
│   ├── screenshots/     ← UI screenshots, terminal output, config panels
│   └── icons/           ← tool logos, badges (optional)
├── bootstrap/
├── linux/
├── containers/
├── kubernetes/
├── networking/
├── storage/
├── delivery/
│   └── project-runtimes/
├── security/
├── observability/
├── cloud/
│   └── aws/
├── iac/
├── self-hosted/
└── incident-response/
```

---

## Domain Breakdown

### `bootstrap/`

**Purpose:** Installing tools and setting up machines from scratch — fast.

This is where every installation runbook lives. The design philosophy is: one file per tool, and each file has two sections. The first section walks through the official installation commands one by one, with brief context for each step. The second section contains a single-command reference that invokes the corresponding automation script from the `silver-stack` repository — so a fresh server can be fully provisioned by running one command, not thirty.

Tools covered include Docker, Kubernetes node dependencies (containerd, kubeadm, kubelet, kubectl), Helm, Terraform, Jenkins, SonarQube, Nexus, ArgoCD, and Prometheus/Grafana. New tools get added here every time they're installed for the first time.

**File structure per tool:**
```
bootstrap/
├── docker.md
├── kubernetes-node.md
├── helm.md
├── terraform.md
├── jenkins.md
├── sonarqube.md
├── nexus.md
├── argocd.md
├── prometheus-grafana.md
└── linux-server.md     ← fresh Ubuntu server baseline
```

**Relationship with `silver-stack`:**
The automation scripts live in a separate repository (`silver-stack`). This folder does not duplicate those scripts. Instead, each markdown file references the script by raw URL so a reader can either follow the manual steps or run the one-liner. Documentation and code stay in their correct homes.

---

### `linux/`

**Purpose:** Linux system administration — the foundation everything else runs on.

Covers OS-level work: setting up a fresh server, configuring users and permissions, managing storage at the block level, networking from the OS side (interfaces, routes, firewall rules), hardening, and diagnosing system-level failures.

```
linux/
├── system-setup/
├── networking/
├── storage/
├── security/
└── troubleshooting/
```

---

### `containers/`

**Purpose:** Everything below Kubernetes — images, registries, and the container runtime.

This domain focuses on the build side of containers: writing efficient Dockerfiles, understanding layer caching, multi-stage builds, and pushing images to registries. It is intentionally separated from Kubernetes because container knowledge is a prerequisite to Kubernetes knowledge, and the two are often confused.

```
containers/
├── image-building/
├── registries/
├── runtime-config/
└── troubleshooting/
```

---

### `kubernetes/`

**Purpose:** Cluster setup, workloads, networking, storage, security, autoscaling, GitOps, and debugging inside Kubernetes.

This is the largest and most actively developed domain. It covers everything from bootstrapping a cluster (kubeadm, kind, EKS, bare-metal) to production-grade concerns like network policies, RBAC, HPA/VPA, persistent volumes, and GitOps workflows with ArgoCD or Flux.

```
kubernetes/
├── cluster-setup/
├── networking/
├── storage/
├── security/
├── workloads/
├── autoscaling/
├── gitops/
└── troubleshooting/
```

---

### `networking/`

**Purpose:** Infrastructure-level networking — DNS, TLS, load balancers, ingress/gateway controllers, VPNs, and firewalls.

This domain is about the network layer that sits between the internet and the application. It does not duplicate Kubernetes networking (which lives in `kubernetes/networking/`) — it covers the host and infrastructure side: DNS records and resolvers, TLS certificate management, Nginx/HAProxy configuration, VPN tunnels between servers, and firewall rules at the OS or cloud level.

```
networking/
├── dns/
├── tls/
├── load-balancing/
├── ingress-gateway/
├── vpn-tunnels/
└── firewalls/
```

---

### `storage/`

**Purpose:** Persistent data — block storage, object storage, databases, and backup/restore procedures.

```
storage/
├── block/
├── object/
├── databases/
└── backup-restore/
```

---

### `delivery/`

**Purpose:** Getting code from a developer's laptop to a running service — CI pipelines, CD deployments, artifact management, GitOps workflows, and project runtime identification.

The `project-runtimes/` subfolder deserves a specific explanation. When a new project arrives — a Java service, a Node.js API, a Python script — the first job of a DevOps engineer is to understand how that project runs before writing any pipeline or Dockerfile. This folder contains one file per language/runtime, answering the question: "I just cloned this repo. What do I look at first, and what commands do I run to build and test it?"

```
delivery/
├── ci-pipelines/
├── cd-deployments/
├── artifact-management/
├── gitops/
└── project-runtimes/
    ├── node.md          ← package.json, npm install, build command, dist output
    ├── python.md        ← requirements.txt vs pyproject.toml, venv, entry point
    ├── java-maven.md    ← pom.xml, mvn package, target/ output
    ├── java-gradle.md   ← build.gradle, ./gradlew build, libs/ output
    └── golang.md        ← go.mod, go build, binary output
```

---

### `security/`

**Purpose:** Secrets management, vulnerability scanning, RBAC, OS hardening, and certificate workflows.

```
security/
├── secrets-management/
├── scanning/
├── rbac/
├── os-hardening/
└── certificates/
```

---

### `observability/`

**Purpose:** Knowing what is happening inside running systems — metrics, logs, traces, and alerts.

```
observability/
├── metrics/
├── logging/
├── tracing/
└── alerting/
```

---

### `cloud/`

**Purpose:** Cloud provider-specific knowledge — IAM, VPCs, compute, and managed services.

Cloud content is organized by provider. AWS is the primary target and has its own subdirectories. GCP and Azure folders exist as placeholders that will be populated as experience grows.

```
cloud/
├── aws/
│   ├── iam/
│   ├── networking/
│   ├── compute/
│   └── managed-services/
├── gcp/
└── azure/
```

---

### `iac/`

**Purpose:** Infrastructure as Code — provisioning, state management, and reusable modules.

Covers Terraform workflows: writing resources, managing remote state, structuring modules, handling provider versions, and running plans safely in CI. Will expand to include Pulumi or OpenTofu as needed.

```
iac/
├── provisioning/
├── state-management/
└── modules/
```

---

### `self-hosted/`

**Purpose:** Software that is deployed and operated personally — not managed by a cloud provider, not SaaS.

This is one of the most distinctive parts of the repository. Every tool here was set up from scratch: configuring the service, writing the systemd unit or Docker Compose file, setting up reverse proxies, managing TLS, and handling upgrades. Services currently running or planned include:

| Service | Category | Status |
|---|---|---|
| Nexus | Artifact registry | Running |
| SonarQube | Code quality | Running |
| Jenkins | CI/CD | Running |
| Nextcloud | Collaboration/storage | Planned |
| Gitea | Git hosting | Planned |
| Ollama + OpenWebUI | AI stack | Planned |
| n8n | Automation/workflows | Planned |
| MLflow | MLOps | Planned |

```
self-hosted/
├── ci-cd/
├── artifact-registry/
├── code-quality/
├── ai-stack/
├── automation/
├── collaboration/
└── mlops/
```

---

### `incident-response/`

**Purpose:** Structured playbooks for when things go wrong — not debugging notes, but step-by-step response procedures for known failure scenarios.

---

## Design Principles

**One domain, one folder.** No content lives in two places. If something could belong to both `kubernetes/` and `security/`, it belongs in `kubernetes/security/` — the more specific location wins.

**Tone is first-person past tense.** Every file in this repo was written after the work was done. The writing reflects what was built, what commands were run, and what was learned — not instructions directed at a future reader.

**Scripts live in `silver-stack`, documentation lives here.** Automation scripts (`.sh`, YAML manifests, Terraform modules) are maintained in the `silver-stack` repository. This runbook links to them by URL. No duplication. If a script changes, the documentation points to the latest version automatically.

**Bootstrap is its own domain.** Installation runbooks are not scattered across domain folders. Everything about getting a tool onto a machine lives in `bootstrap/`, regardless of what the tool is used for. This makes it fast to find installation steps without knowing which domain the tool belongs to.

**`project-runtimes/` is detective work, not operations.** The files in `delivery/project-runtimes/` are not about deploying applications — they are about identifying how an application is structured and built before any DevOps work begins. This distinction is intentional and matters.

---

## How Content Is Added

When a new tool is installed for the first time, a file is created in `bootstrap/` before anything else. When a self-hosted service is set up, a folder is created inside `self-hosted/` for its documentation. When a Kubernetes issue is debugged and resolved, the resolution is captured in `kubernetes/troubleshooting/`. When a new project language or framework is encountered, the runtime identification steps go into `delivery/project-runtimes/`.

The repository grows by doing, not by planning.
