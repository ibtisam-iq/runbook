# Kubernetes Packages

Phase 5 and Phase 6 install the Kubernetes binaries. Worker nodes receive
`kubelet` and `kubeadm` only. Control plane nodes additionally receive
`kubectl`, `helm`, and `k9s`.

---

## Scripts

| Script | Phase | Installed on |
|---|---|---|
| `packages/install-kubeadm-kubelet.sh` | 5 | All nodes |
| `packages/install-controlplane-cli.sh` | 6 | Control plane only |
| `lib/k8s-version-resolver.sh` | Pre-5 | Sourced by both |

---

## Version Resolution

Before any package is installed, the version resolver is sourced into the
running shell. It accepts a `MAJOR.MINOR` string and resolves the exact
patch release via the official Kubernetes release API.

**Input:**

```bash
export K8S_VERSION="1.36"   # Set during cluster-params wizard (Phase 1)
```

**Resolution logic:**

```bash
curl -fsSL https://dl.k8s.io/release/stable-1.36.txt
# Returns: v1.36.0
```

**Exported variables:**

| Variable | Example value | Used by |
|---|---|---|
| `K8S_MAJOR_MINOR` | `1.36` | APT repo URL |
| `K8S_PATCH_VERSION` | `1.36.0` | Validation output |
| `K8S_IMAGE_TAG` | `v1.36.0` | `kubeadm config images pull`, `kubeadm init` |
| `KUBE_PKG_VERSION` | `1.36.0-1.1` | `apt-get install kubelet=...` |

The `-1.1` suffix is the Debian package revision appended by the Kubernetes
packaging team. Without it, `apt-get` cannot find the exact package version.

The resolver performs no installation and makes no system changes. It is safe
to source multiple times.

---

## Phase 5 — kubelet + kubeadm (`install-kubeadm-kubelet.sh`)

**What the script does:**

1. Logs the resolved version context (`K8S_MAJOR_MINOR`, `K8S_PATCH_VERSION`,
   `KUBE_PKG_VERSION`)
2. Installs `ca-certificates`, `curl`, `gpg`
3. Removes any legacy `kubernetes.list` source file
4. Downloads the Kubernetes signing key from `pkgs.k8s.io` and stores it at
   `/etc/apt/keyrings/kubernetes-apt-keyring.gpg` (skips if already present)
5. Writes a Deb822-format APT source pointing to
   `https://pkgs.k8s.io/core:/stable:/v<MAJOR.MINOR>/deb/`
6. Installs exact versions:

    ```bash
    apt-get install kubelet=1.36.0-1.1 kubeadm=1.36.0-1.1
    ```

7. Pins both packages with `apt-mark hold` to prevent accidental upgrade
8. Enables `kubelet` via systemd (it will crashloop until `kubeadm init`
   or `kubeadm join` completes — this is expected and handled by
   `ensure-k8s-services.sh`)

**Verify:**

```bash
kubelet --version
kubeadm version
apt-mark showhold   # Should list kubelet and kubeadm
```

!!! note "Worker nodes stop here"
    `init-worker-node.sh` ends after Phase 5. `kubectl` and the remaining
    CLI tools are not installed on workers. The `kubeadm join` command
    (printed by `init-controlplane.sh`) is run manually after the control
    plane is ready.

---

## Phase 6 — Control Plane CLI Tools (`install-controlplane-cli.sh`)

Installs three tools that are only useful from the control plane:

### kubectl

Installed from the same `pkgs.k8s.io` APT repository using the same
`KUBE_PKG_VERSION`. The script checks if `kubectl` is already present and
skips if so.

```bash
kubectl version --client
```

### Helm 4

Downloaded via the official Helm install script:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
```

Skipped if `helm` is already installed.

```bash
helm version --short
```

### k9s

Downloaded as a tarball from `derailed/k9s` GitHub releases (pinned to
`v0.50.16`). Architecture is auto-detected (`amd64` / `arm64`).

1. Downloads `k9s_Linux_<arch>.tar.gz`
2. Extracts the `k9s` binary
3. Installs to `/usr/local/bin/k9s` with `install -m 0755`

Skipped if `k9s` is already installed.

```bash
k9s version --short
```

---

## APT Repository Structure

The Kubernetes APT repository at `pkgs.k8s.io` uses a **per-minor-version**
repo structure. Installing `v1.36.x` requires pointing the source at
`/core:/stable:/v1.36/deb/`. Switching versions means updating the source
file and re-running `apt-get update`.

The source is written in **Deb822 format** (`.sources` extension), which is
the current standard that replaces the legacy single-line `.list` format.
Any existing `kubernetes.list` file is deleted before writing the new source
to prevent repository conflicts.

---

## Version Pinning Strategy

`apt-mark hold` is applied to `kubelet` and `kubeadm` immediately after
installation. This prevents `apt-get upgrade` from accidentally upgrading
Kubernetes components, which would create a version skew between the control
plane and worker nodes.

To upgrade intentionally:

```bash
apt-mark unhold kubelet kubeadm kubectl
apt-get install kubelet=<new-version> kubeadm=<new-version> kubectl=<new-version>
apt-mark hold kubelet kubeadm kubectl
```

`cluster-params-2.sh` (the advanced wizard variant) enforces an additional
safety rule: it detects the currently installed `kubelet` version and refuses
to install a version more than one minor version away, preventing unsupported
upgrade or downgrade jumps.
