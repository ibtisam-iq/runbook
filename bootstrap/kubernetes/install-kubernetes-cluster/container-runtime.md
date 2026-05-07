# Container Runtime

!!! abstract "Part of: [Install a Kubernetes Cluster with kubeadm](index.md)"
    **Phases 3 & 4 of 9** — Installs and configures the complete container runtime stack on every node: CNI binaries, crictl, containerd, and runc.

    **Prerequisite:** [Node Preparation](node-preparation.md) — swap disabled, kernel modules loaded, sysctl applied.  
    **Next step:** [Kubernetes Packages](kubernetes-packages.md) — install kubelet, kubeadm, kubectl, helm, and k9s.

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

### CNI Plugin Binaries

**What they are:** Low-level networking executables (`bridge`, `host-local`,
`loopback`, etc.) that CNI plugins like Calico and Flannel call into.
Without them, CNI plugins fail to configure pod network interfaces.

**What the script does:**

1. Detects architecture (`amd64` or `arm64`)
2. Downloads the CNI plugins archive (`v1.9.0`) from GitHub releases
3. Extracts to `/opt/cni/bin/`

```bash
ls /opt/cni/bin/   # Should show: bridge, host-local, loopback, portmap, etc.
```

### crictl

**What it is:** The CRI (Container Runtime Interface) CLI — a low-level
debugging tool that talks directly to containerd's CRI socket, bypassing
Kubernetes entirely. Useful for inspecting containers, pods, and images when
`kubectl` is unavailable or when debugging container startup failures.

**What the script does:**

1. Downloads the `crictl` binary (`v1.30.0`) for the detected architecture
2. Extracts to `/usr/local/bin/crictl`
3. Makes it executable

```bash
crictl version   # Verify install
```

After Phase 4, `crictl` is configured with the correct socket path by
`config-crictl.sh`.

---

## Phase 4 — containerd Install and Configuration

Phase 4 installs the container runtime itself. Two install methods are
supported. You choose during Phase 1 (the cluster parameters wizard).

### Method Selection

| Method | How it installs | Best for |
|---|---|---|
| **Package** (default) | `apt install containerd.io` from Docker's APT repo | All standard deployments |
| **Binary** | Downloads and extracts official containerd binary releases | Air-gapped or locked-down environments |

The dispatcher script `install-containerd.sh` reads `CONTAINERD_METHOD` (set
during Phase 1) and calls the correct install + config script pair.

### Package Method

**`install-containerd-package.sh`**

1. Installs Docker's APT repo GPG key
2. Adds `https://download.docker.com/linux/ubuntu` to APT sources
3. Runs `apt install -y containerd.io`
4. Enables and starts the `containerd` systemd service

**`config-containerd-package.sh`**

1. Generates the default containerd config: `containerd config default > /etc/containerd/config.toml`
2. Patches `SystemdCgroup = false` → `SystemdCgroup = true` — **critical:**
   without this, kubelet and containerd use different cgroup drivers and the
   cluster fails to start
3. Restarts containerd

### Binary Method

**`install-runc.sh`** — downloads the `runc` binary from GitHub releases and
installs to `/usr/local/sbin/runc`. (The package method gets runc bundled with
`containerd.io`.)

**`install-containerd-binary.sh`** — downloads the containerd tarball from
GitHub releases, extracts binaries to `/usr/local/bin/`, writes and enables a
systemd service unit.

**`config-containerd-binary.sh`** — identical to the package config: generates
`config.toml` and patches `SystemdCgroup = true`.

---

## Phase 4 (post) — Configure crictl

**`config-crictl.sh`** writes `/etc/crictl.yaml`:

```yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
```

This tells `crictl` which socket to use. Without this, every `crictl` invocation
requires a `--runtime-endpoint` flag.

**Verify full Phase 3+4 result:**

```bash
systemctl is-active containerd          # Should: active
crictl info                             # Should: print containerd info
ls /opt/cni/bin/                        # Should: list CNI binaries
ls /usr/local/bin/crictl                # Should: exist
```
