# Install Kubernetes CLI Tools

Installs the four essential Kubernetes command-line tools on any Linux server
in a single script run: **kubectl**, **helm**, **kustomize**, and **k9s**.

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/installers/install-kubernetes-cli.sh | bash
```

No `sudo` required for the script itself. Individual install steps that write
to `/usr/local/bin` use `sudo mv` internally.

---

## Script

| Script | Path |
|---|---|
| `install-kubernetes-cli.sh` | `scripts/installers/install-kubernetes-cli.sh` |

This is a **standalone script** — it does not depend on a running Kubernetes
cluster and can be run on any fresh Linux server.

---

## Tools Installed

| Tool | Version strategy | Binary location |
|---|---|---|
| `kubectl` | Latest stable from `dl.k8s.io/release/stable.txt` | `/usr/local/bin/kubectl` |
| `helm` | Latest release from `helm/helm` GitHub API | `/usr/local/bin/helm` |
| `kustomize` | Latest release from `kubernetes-sigs/kustomize` GitHub API | `/usr/local/bin/kustomize` |
| `k9s` | Latest release from `derailed/k9s` GitHub API | `/usr/local/bin/k9s` |

All four tools are installed to `/usr/local/bin/` and made executable.
Architecture is auto-detected (`x86_64` → `amd64`).

---

## Idempotency

Each tool is checked with `command -v` before installation. If already present,
the install step is skipped and the existing version is logged:

```
[ OK ]    kubectl already installed
[ OK ]    helm already installed
```

Re-running the script on an already-configured machine is safe.

---

## Installation Steps

### Step 1 — Preflight

Runs the silver-stack preflight check (OS, architecture, connectivity) before
any installation begins:

```bash
bash <(curl -fsSL .../preflight.sh)
```

Exits immediately if preflight fails.

---

### Step 2 — kubectl

Fetches the latest stable version string from the official Kubernetes release
endpoint, then downloads the binary directly:

```bash
curl -sLO "https://dl.k8s.io/release/v${KUBECTL_V}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

---

### Step 3 — helm

Fetches the latest tag from `helm/helm` releases, then downloads the official
tarball from `get.helm.sh`:

```bash
curl -sLO "https://get.helm.sh/helm-v${HELM_TAG}-linux-amd64.tar.gz"
tar -xzf *.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
```

---

### Step 4 — kustomize

Fetches the latest release from `kubernetes-sigs/kustomize`, downloads the
`linux_amd64` tarball via the GitHub releases API, extracts it, and moves the
binary:

```bash
# asset URL resolved from GitHub API
download_and_install "$ASSET_URL" "/usr/local/bin/kustomize"
```

The internal `download_and_install` helper handles `.tar.gz`, `.tgz`, and
`.zip` archives — finds the first executable binary in the archive and moves
it to the target path.

---

### Step 5 — k9s

Detects whether an existing `k9s` binary matches the current architecture
(`file $(command -v k9s) | grep x86-64`). If missing or wrong architecture,
downloads the correct `k9s_Linux_amd64.tar.gz` asset from `derailed/k9s`
releases:

```bash
curl -sLO "$ASSET_URL"
tar -xzf k9s*Linux*
sudo mv k9s /usr/local/bin/k9s
sudo chmod +x /usr/local/bin/k9s
```

---

### Step 6 — Summary

Prints a version summary table on completion:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 • kubectl:          1.33.0
 • helm:             3.17.3
 • kustomize:        5.6.0
 • k9s:              0.32.7
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ OK ]    Kubernetes CLI toolchain ready
```

---

## Post-Install Verification

```bash
kubectl version --client
helm version --short
kustomize version
k9s version --short
```

---

## Notes

!!! note "No cluster required"
    This script does not need a running Kubernetes cluster. It installs
    client-side tools only. Use it on the laptop, a jump host, a CI runner,
    or any server that needs to talk to a remote cluster.

!!! note "kustomize release tag format"
    The `kubernetes-sigs/kustomize` repository tags releases as
    `kustomize/vX.Y.Z` rather than plain `vX.Y.Z`. The script strips the
    prefix automatically before using the version string.
