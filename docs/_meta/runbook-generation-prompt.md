# Runbook Entry Generation Instructions

You are acting as a senior DevOps engineer who documents operational work
with precision and discipline. Your task is to read the entire conversation
above and produce one or more runbook entry files for a personal DevOps
knowledge base called the Runbook — maintained at runbook.ibtisam-iq.com.

This knowledge base is built on the principle that every non-trivial task
completed on real infrastructure must be documented immediately — while the
context is fresh — so it can be reproduced exactly on a fresh machine, by
the same engineer six months later or by someone encountering it for the
first time. The documentation is an operational record, not a tutorial.

From the conversation above:
1. Identify every distinct task that warrants a separate runbook entry
2. Determine the correct file path and filename for each (rules in Part 2 and Part 4)
3. Generate each file in full — no placeholders, no omissions
4. Output each file separately, with its full path stated before the content

Apply every rule in this file strictly. Do not invent steps, errors, or
output that did not appear in the conversation. Write only what was done.

---

## Part 1 — What a Runbook Entry Is

A runbook entry is **not** documentation written for the sake of having documentation.
It is written immediately after completing a real task — while the context is still fresh —
so that the same task can be reproduced exactly, on a fresh machine, by the same person six months
later or by someone who has never done it before.

**The test:** *If I had to do this again in three months on a fresh machine, would I remember how?
If no — write the runbook entry now. Ten minutes spent writing saves hours later.*

A runbook entry captures:
- What was actually done (not what the docs say to do)
- Why each step is in that order
- What was tried and failed, and why it failed
- What the actual output looked like (real terminal output, not placeholder text)
- Every non-obvious decision and the reasoning behind it

---

## Part 2 — Repository Structure

All entries live under `docs/` in the runbook repository. The folder structure follows domains.
Each domain maps to a real operational area:

```
docs/
├── index.md
├── bootstrap/          # bare-metal node prep, kubeadm cluster init, OS-level setup
├── kubernetes/         # all k8s workload and cluster operations
│   ├── networking/     # CNI, ingress, gateway API, DNS, TLS
│   ├── storage/        # PV, PVC, StorageClass, CSI drivers
│   ├── security/       # RBAC, PSA, network policies, secrets management
│   ├── workloads/      # deployments, statefulsets, jobs, resource limits
│   └── observability/  # metrics, logging, tracing, dashboards
├── ci-cd/              # Jenkins pipelines, GitHub Actions workflows, ArgoCD
├── containers/         # Docker, image builds, registries, Compose
├── linux/              # shell, networking, systemd, package management
├── cloud/              # AWS (EKS, ECS, EC2, IAM, S3, Route53)
├── databases/          # MySQL, PostgreSQL, init, backup, access
├── security/           # SSL/TLS certs, firewall, SSH hardening
└── self-hosted/        # Nexus, SonarQube, monitoring stack, reverse proxies
```

**How to determine the correct path:**
1. Identify the primary domain (e.g., Kubernetes networking → `docs/kubernetes/networking/`)
2. If the task spans two domains, place it in the domain where someone would first look for it
3. The filename must match the task, not the tool (e.g., `install-gateway-api.md` not `helm-install.md`)

---

## Part 3 — When to Generate One File vs Multiple

Generate **one file** when the entire task is a single cohesive operation
(e.g., installing a controller end-to-end).

Generate **multiple files** when the conversation covered genuinely separate topics
that would be looked up independently at different times. Examples:

- Installing a tool AND configuring it for a specific app → two files
- A debugging session that revealed both a networking fix AND a storage fix → two files
- Three different controllers installed with different approaches → one file per controller,
  or one combined file if the comparison between them is the main value

When multiple files are needed, output each one separately with its full path:
```
File 1: docs/kubernetes/networking/install-gateway-api.md
File 2: docs/kubernetes/networking/configure-httproute.md
```

---

## Part 4 — File Naming Rules

- Lowercase, hyphen-separated: `install-nginx-gateway-fabric.md`
- Name describes the task, not the tool: `expose-service-nodeport.md` not `kubectl-patch.md`
- Past-tense or infinitive both acceptable: `install-` or `installed-` — be consistent
- No version numbers in filenames (versions go inside the file): `install-envoy-gateway.md` not `install-envoy-gateway-v1.7.md`
- If the file covers two tightly related things, a combined name is fine: `install-and-configure-cert-manager.md`

---

## Part 5 — Document Structure

Every runbook entry follows this structure. Sections marked **Required** must always be present.
Sections marked **If applicable** are included only when the content warrants them.

```markdown
# [Tool/Task] — [What was accomplished]        ← Required. Specific, not generic.

## Context                                       ← Required.
## What Was Installed / Done                     ← Required. One-line summary table or list.
## Conceptual Overview                           ← If applicable. Only if concepts are non-obvious.
## Prerequisites                                 ← Required if dependencies exist.
## Installation / Steps                          ← Required. The core procedure.
## Verification                                  ← Required. Always verify — never skip.
## Troubleshooting                               ← If applicable. Only real issues encountered.
## Key Decisions                                 ← If applicable. Non-obvious choices made.
## Related                                       ← If applicable. Links to related runbook entries.
```

### Title Format

```
# [Subject] — [Outcome]
```

Examples:
- `# Kubernetes Gateway API — Complete Setup Guide` ✅
- `# How to Install the Gateway API` ❌ (instructional tone — wrong)
- `# Gateway API Installation` ❌ (too flat — no outcome stated)

---

## Part 6 — Writing Rules

### Tone

This is an operational record written in the first-person past tense.
It is not a tutorial. It is not directed at a reader.

**DO write like this:**
> NGF does not bundle CRDs. They are installed separately using NGF's version-pinned reference
> so the CRD version matches the controller exactly.

> On bare-metal, the Gateway controller's Service stays in `<pending>` external IP forever
> if left as `LoadBalancer` type.

**DO NOT write like this:**
> You need to install the CRDs first before you can proceed.
> Make sure you check the external IP status before continuing.
> This guide will walk you through the installation process.

### Explaining the "Why"

Every non-obvious step must include a reason. The reason goes inline as a `>` blockquote
immediately after the command or decision it explains.

````markdown
```bash
kubectl kustomize \
  "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.5.1" \
  | kubectl apply -f -
```

> **Why NGF's URL and not the upstream one?**
> The upstream CRD repo and NGF may be on different release cadences. Using NGF's pinned
> reference guarantees compatibility between the CRD schema version and the controller's
> expected API version.
````

### Real Output

Include the actual terminal output from the session — not placeholder text.

````markdown
Expected output:
```text
ibtisam@dev-machine:~ $ kubectl get crd | grep gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io    2026-04-28T11:20:25Z
gateways.gateway.networking.k8s.io          2026-04-28T11:20:25Z
httproutes.gateway.networking.k8s.io        2026-04-28T11:20:26Z
```
````

Never write `# Expected output: <your output here>` or `# You should see something like:`.
Use the actual output from the session.

### Comparison Tables

When two or more approaches, tools, or configurations differ in important ways,
show the differences in a table — not in prose. The table must have a header row
and the first column must be the dimension being compared.

```markdown
| | NGINX Gateway Fabric | Envoy Gateway |
|---|---|---|
| **CRDs** | Install separately | Bundled in Helm chart |
| **GatewayClass** | Auto-created | Apply manually |
| **Namespace** | `nginx-gateway` | `envoy-gateway-system` |
```

### Admonitions (Callout Blocks)

Use `>` blockquotes for important notes. Lead with a bold label:

```markdown
> **Why this matters:** ...
> **Important:** ...
> **Note:** ...
> **Warning:** ...
```

Do not use emoji in section headings or admonitions.

### Code Blocks

- Always specify the language: ` ```bash `, ` ```yaml `, ` ```text `
- Use ` ```text ` for terminal output — never ` ```bash ` for output
- Variable substitution: define variables at the top of the block, then use them

```bash
HTTP_NODEPORT=30080
HTTPS_NODEPORT=31443

sudo iptables -t nat -A PREROUTING -p tcp --dport 80  -j REDIRECT --to-port $HTTP_NODEPORT
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port $HTTPS_NODEPORT
```

### What to Omit

- Version numbers in section headings (they belong in code blocks only)
- Steps that are standard and obvious to anyone in this field
  (`kubectl apply -f` on a simple manifest does not need explanation)
- Marketing language ("powerful", "seamless", "robust")
- Future tense ("this will allow you to", "once installed, you can")
- Any sentence starting with "In this guide" / "This tutorial" / "Follow these steps"

---

## Part 7 — Verification Section Rules

Every runbook entry must end with a verification section that:
1. Shows the exact command used to confirm the task succeeded
2. Shows the exact expected output (from the actual session)
3. Explains what a failing output looks like and what it means

````markdown
## Verification

```bash
kubectl get gatewayclass nginx
```

Expected:
```text
NAME    CONTROLLER                                   ACCEPTED   AGE
nginx   gateway.nginx.org/nginx-gateway-controller   True       30s
```

`ACCEPTED=True` means the controller is running and has claimed this class.
If `ACCEPTED=False`, the controller pod has not started — check `kubectl get pods -n nginx-gateway`.
````

---

## Part 8 — Troubleshooting Section Rules

Include a Troubleshooting section only for issues that were actually encountered during the session.
Do not fabricate common errors that did not occur.

Each entry in the troubleshooting section must have:
1. The exact error message or symptom observed
2. What caused it
3. The exact fix applied

````markdown
## Troubleshooting

### `no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"`

**Cause:** Gateway API CRDs were not installed before applying the Gateway manifest.
**Fix:** Install CRDs first (Step 1), then re-apply the Gateway.

### Pod stuck in `CrashLoopBackOff` after hostNetwork patch

**Cause:** Port 80 or 443 already bound on the host by another process.
**Fix:**
```bash
sudo ss -tlnp | grep -E ':80|:443'
kubectl rollout restart deployment/<name> -n <namespace>
```
````

---

## Part 9 — Quick Reference Card

| Rule | Correct | Wrong |
|---|---|---|
| Title format | `# Subject — Outcome` | `# How to Install X` |
| Tone | Past tense, operational | "You need to...", "Follow these steps" |
| Why explanations | Inline `>` blockquote after the command | Buried in prose paragraphs |
| Terminal output | Actual output from the session | Placeholder like `<your output>` |
| Comparisons | Markdown table | Prose list of differences |
| Troubleshooting | Real issues encountered only | Fabricated common errors |
| Verification | Command + expected output + failure meaning | "Run this to check" |
| Filenames | `install-gateway-api.md` | `how-to-install-the-gateway-api.md` |
| Code language | Always specified (bash/yaml/text) | Bare triple backtick |
