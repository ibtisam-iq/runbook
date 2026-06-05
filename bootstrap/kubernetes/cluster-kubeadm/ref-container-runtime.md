# Container Runtime


!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Phases 3 & 4 of 9** — Installs containerd, runc, crictl, and CNI plugin binaries on every node.

    **Prerequisite:** [Node Preparation](ref-node-preparation.md) must be complete.
    **Next:** [Kubernetes Packages](ref-kubernetes-packages.md) — install kubelet, kubeadm, and kubectl.

---

The container runtime layer installs and configures everything Kubernetes needs
to run containers: **containerd**, **runc** (OCI runtime), **crictl** (CRI
debugger), and the **CNI plugin binaries** (the low-level networking primitives
that CNI plugins like Calico and Flannel depend on).

This layer runs in Phases 3 and 4 of both entrypoint scripts.

---

## Scripts

| Script | Phase | Path |
|---|---|---|
| Install CNI binaries | 3 | `runtime/install-cni-binaries.sh` |
| Install crictl | 3 | `runtime/install-crictl.sh` |
| Install containerd (dispatcher) | 4 | `runtime/install-containerd.sh` |
| Install containerd — package method | 4 | `runtime/install-containerd-package.sh` |
| Configure containerd — package method | 4 | `runtime/config-containerd-package.sh` |
| Install runc (binary method only) | 4 | `runtime/install-runc.sh` |
| Install containerd — binary method | 4 | `runtime/install-containerd-binary.sh` |
| Configure containerd — binary method | 4 | `runtime/config-containerd-binary.sh` |
| Configure crictl | 4 (post) | `runtime/config-crictl.sh` |

---

## Phase 3 — Runtime Prerequisites

Phase 3 installs two components that are needed *before* containerd itself:
CNI plugin binaries and crictl.

### CNI Plugin Binaries (`install-cni-binaries.sh`)

!!! note "CNI binaries ≠ CNI plugin"
    The binaries installed here (`/opt/cni/bin/bridge`, `host-local`, `loopback`,
    etc.) are the **low-level primitives** that CNI plugins like Calico and
    Flannel call internally. They are not the CNI plugin itself. The CNI plugin
    (Calico or Flannel) is installed separately after `kubeadm init` — see
    [`kubeconfig-and-cni.md`](ref-kubeconfig-and-cni.md).

**What the script does:**

1. Resolves architecture (`x86_64` → `amd64`, `aarch64` → `arm64`)
2. Downloads `cni-plugins-linux-<arch>-<version>.tgz` from
   `containernetworking/plugins` GitHub releases (default: `v1.9.0`)
3. Verifies SHA256 checksum
4. Extracts all binaries to `/opt/cni/bin/`
5. Skips if `/opt/cni/bin/bridge` already exists (idempotent)

**Verify:**

```bash
ls /opt/cni/bin/
# Should list: bridge, host-local, loopback, portmap, etc.
```

### crictl (`install-crictl.sh`)

crictl is the low-level CRI debugging tool (`kubectl` equivalent for the
container runtime layer). It is installed before containerd because Phase 4
uses it to validate containerd configuration.

**What the script does:**

1. Downloads `crictl-<version>-linux-<arch>.tar.gz` from
   `kubernetes-sigs/cri-tools` (default: `v1.30.0`)
2. Verifies SHA256 checksum
3. Extracts `crictl` binary to `/usr/local/bin/`
4. Skips if already installed (idempotent)

---

## Phase 4 — Containerd Installation

`install-containerd.sh` is a **dispatcher**: it reads the
`CONTAINERD_INSTALL_METHOD` environment variable (set during Phase 1 by the
cluster parameters wizard) and routes to one of two installation paths.

```
CONTAINERD_INSTALL_METHOD=package  →  install-containerd-package.sh
                                       config-containerd-package.sh

CONTAINERD_INSTALL_METHOD=binary   →  install-runc.sh
                                       install-containerd-binary.sh
                                       config-containerd-binary.sh
```

After either path completes, the dispatcher enables `containerd` via systemd
and validates that the service is active.

### Package Method (Recommended)

Uses the **Docker official APT repository** to install `containerd.io`. This
package bundles runc and is maintained by Docker, making it the
industry-standard approach for Ubuntu-based nodes.

**install-containerd-package.sh:**

1. Installs `ca-certificates`, `curl`, `gnupg`, `lsb-release`
2. Adds the Docker GPG key to `/etc/apt/keyrings/docker.asc`
3. Writes a Deb822-format source to `/etc/apt/sources.list.d/docker.sources`
4. Installs `containerd.io` via `apt-get`

**config-containerd-package.sh:**

1. Runs `containerd config default > /etc/containerd/config.toml` to
   generate a clean baseline
2. Sets `SystemdCgroup = true` — **this is the critical change**; without it,
   kubelet and containerd use different cgroup drivers and the node becomes
   unstable
3. Restarts containerd

### Binary Method (Advanced)

Downloads containerd directly from the upstream GitHub releases at
`containerd/containerd`. runc must be installed first because the binary
method does not bundle it.

**install-runc.sh:**

1. Downloads `runc.<arch>` from `opencontainers/runc` releases (default: `v1.4.0`)
2. Verifies SHA256 from the official checksum file (parses the correct line
   for the architecture)
3. Installs to `/usr/local/sbin/runc` with `install -m 0755`

**install-containerd-binary.sh:**

1. Requires `runc` to be present (exits if not found)
2. Downloads `containerd-<version>-linux-<arch>.tar.gz` (default: `v2.2.0`)
3. Verifies SHA256 checksum
4. Extracts to `/usr/local`
5. Creates a complete systemd unit at `/etc/systemd/system/containerd.service`
6. Enables and starts the service

**config-containerd-binary.sh (extended):**

Applies more configuration than the package variant:

1. Generates default config
2. Sets `SystemdCgroup = true`
3. Sets `sandbox_image` to `registry.k8s.io/pause:3.9`
4. Sets `bin_dir` to `/opt/cni/bin` and `conf_dir` to `/etc/cni/net.d`
5. Waits up to 10 seconds for the containerd socket
6. Runs `crictl info` to validate CRI plugin is functional

---

## Phase 4 (Post) — Configure crictl

After containerd is running, `config-crictl.sh` configures crictl to
communicate with it.

**What the script does:**

1. Confirms `crictl` is installed and the containerd socket exists at
   `/run/containerd/containerd.sock`
2. Writes `/etc/crictl.yaml`:

```yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint:   unix:///run/containerd/containerd.sock
timeout:          10
debug:            false
pull-image-on-create: false
```

3. Validates the configuration with `crictl info`

**Verify:**

```bash
crictl info
crictl ps       # List running containers
crictl images   # List pulled images
```

---

## Key Design Notes

| Topic | Detail |
|---|---|
| `SystemdCgroup = true` | Must be set in both package and binary config scripts. kubelet uses systemd cgroup driver by default since Kubernetes 1.22; containerd must match. |
| CNI binaries vs CNI plugin | Binaries in `/opt/cni/bin/` are always installed. The CNI plugin (Calico/Flannel) is not installed until after `kubeadm init`. |
| Package method preference | The package method is preferred because Docker maintains `containerd.io` with stable release cadence and bundled runc. The binary method gives explicit version control at the cost of manual runc management. |
| Idempotency | `install-runc.sh`, `install-containerd-binary.sh`, `install-crictl.sh`, and `install-cni-binaries.sh` all check if the binary already exists and skip if it does. |
