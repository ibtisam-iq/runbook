# Install Kubernetes Tools

Manual installation of the most commonly used Kubernetes CLI tools. Each section is a self-contained bash block — all commands with inline comments, ready to copy and run.

---

## 1. kubectl

The official Kubernetes command-line tool for interacting with clusters.

```bash
# Fetch the latest stable version string
KUBECTL_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)

# Detect architecture
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# Download the binary
curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

# Make it executable and move to PATH
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

!!! note "kustomize is bundled with kubectl"
    Installing `kubectl` also ships a bundled `kustomize` binary. Check before running the standalone kustomize install:
    ```bash
    kubectl version --client
    # Output includes: Kustomize Version: vX.Y.Z
    ```
    If kustomize is already present, skip [Section 4](#4-kustomize).

---

## 2. Helm

The Kubernetes package manager. Uses the official installer script which handles arch detection internally.

```bash
# Download and run the official Helm install script
curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version --short
```

---

## 3. K9s

A terminal-based UI for managing Kubernetes clusters in real time.

```bash
# Detect architecture
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# Fetch the latest release tag
K9S_VERSION=$(curl -sSL https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

# Download the correct tarball for the detected arch
curl -sSLO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz"

# Extract and install
tar -xzf "k9s_Linux_${ARCH}.tar.gz" k9s
sudo mv k9s /usr/local/bin/k9s
sudo chmod +x /usr/local/bin/k9s

# Clean up
rm -f "k9s_Linux_${ARCH}.tar.gz"

# Verify
k9s version --short
```

---

## 4. kustomize

A tool for customizing Kubernetes YAML manifests without templating.

```bash
# Detect architecture
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# Fetch the latest kustomize release tag (tags follow kustomize/vX.Y.Z format)
KUSTOMIZE_TAG=$(curl -sSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name"' | grep 'kustomize/' | cut -d'"' -f4)
KUSTOMIZE_VERSION=${KUSTOMIZE_TAG#kustomize/}

# Download the tarball
curl -sSLO "https://github.com/kubernetes-sigs/kustomize/releases/download/${KUSTOMIZE_TAG}/kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz"

# Extract and install
tar -xzf "kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz"
sudo mv kustomize /usr/local/bin/kustomize
sudo chmod +x /usr/local/bin/kustomize

# Clean up
rm -f "kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz"

# Verify
kustomize version
```

!!! note "Already installed via kubectl?"
    `kubectl` bundles kustomize internally. If `kubectl version --client` already shows a `Kustomize Version`, a standalone install is unnecessary unless a specific newer version is required.

---

## 5. Helmfile

A declarative spec for deploying Helm charts. Used to manage multiple releases in a single `helmfile.yaml`.

```bash
# Detect architecture
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# Fetch the latest release tag
HELMFILE_VERSION=$(curl -sSL https://api.github.com/repos/helmfile/helmfile/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

# Download the tarball
curl -sSLO "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_${ARCH}.tar.gz"

# Extract and install
tar -xzf "helmfile_${HELMFILE_VERSION#v}_linux_${ARCH}.tar.gz" helmfile
sudo mv helmfile /usr/local/bin/helmfile
sudo chmod +x /usr/local/bin/helmfile

# Clean up
rm -f "helmfile_${HELMFILE_VERSION#v}_linux_${ARCH}.tar.gz"

# Verify
helmfile --version
```

---

## 6. eksctl

The official CLI for creating and managing Amazon EKS clusters.

```bash
# Detect architecture
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# Fetch the latest release tag
EKSCTL_VERSION=$(curl -sSL https://api.github.com/repos/eksctl-io/eksctl/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

# Download the tarball
curl -sSLO "https://github.com/eksctl-io/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_Linux_${ARCH}.tar.gz"

# Extract and install
tar -xzf "eksctl_Linux_${ARCH}.tar.gz" eksctl
sudo mv eksctl /usr/local/bin/eksctl
sudo chmod +x /usr/local/bin/eksctl

# Clean up
rm -f "eksctl_Linux_${ARCH}.tar.gz"

# Verify
eksctl version
```

---

## Post-Install Verification

Run all version checks together to confirm the full toolchain is in place:

```bash
kubectl version --client
helm version --short
k9s version --short
kustomize version
helmfile --version
eksctl version
```
