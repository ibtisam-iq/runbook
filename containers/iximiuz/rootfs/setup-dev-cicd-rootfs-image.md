# Dev CI/CD Rootfs: Minimal Jump Host Image Build and Integration for the Iximiuz Labs

## Context

Dev CI/CD Rootfs (`dev-cicd-rootfs`) is the jump-host image for the SilverStack CI/CD Stack playground, built on top of `ubuntu-24-04-rootfs`.

It is easy to confuse with [Dev Machine Rootfs](./setup-dev-machine-rootfs-image.md), which shares the word "dev-machine" as a *node name* inside the CI/CD Stack manifest. They are not the same image. Dev Machine Rootfs is the full ~40-tool DevOps workstation, its own standalone playground. Dev CI/CD Rootfs is deliberately minimal: no toolchain install, no systemd services of its own, nothing beyond the base image plus a welcome banner and SSH aliases to the other three stack nodes. Its only job is to provide an operational environment to drive Jenkins, SonarQube, and Nexus.

!!! warning "MicroVM Rootfs"
    **This image is a microVM rootfs for the [iximiuz Labs](https://labs.iximiuz.com) platform.** The platform mounts it as a block device and boots it with its own kernel. systemd becomes PID 1 through the platform boot process, not through Docker. Running the image with `docker run` will not produce a working systemd or network services: see [Verification](#verification) for the correct approach.

All source artifacts live under:

| Artifact | Path |
|---|---|
| Dockerfile | [`iximiuz/rootfs/dev/ci-cd/Dockerfile`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/ci-cd/Dockerfile) |
| Scripts | [`iximiuz/rootfs/dev/ci-cd/scripts/`](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/dev/ci-cd/scripts/) |
| Welcome banner | [`iximiuz/rootfs/dev/ci-cd/welcome`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/ci-cd/welcome) |
| Playground content | [`iximiuz/rootfs/dev/ci-cd/CONTENT.md`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/ci-cd/CONTENT.md) |
| CI Workflow | [`.github/workflows/build-dev-cicd-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-dev-cicd-rootfs.yml) |
| Stack Manifest | [`iximiuz/manifests/cicd-stack.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/cicd-stack.yml) |

---

## Objectives

Dev CI/CD Rootfs must:

- Provide the **entry-point node** for the four-machine SilverStack CI/CD Stack playground, nothing more.
- Inherit a stable, systemd-enabled Ubuntu 24.04 environment from `ubuntu-24-04-rootfs`, unmodified beyond user-level customization.
- Ship SSH shortcut aliases (`stack-jenkins`, `stack-sonarqube`, `stack-nexus`) so the other three nodes are one command away.
- Display a stack-specific **welcome banner** pointing at the orchestration and operations runbooks.
- Consume as little of the stack's fixed 10 vCPU / 16 GiB / 150 GiB Flexbox budget as possible, so the bulk of it goes to the three service nodes.
- Be built reproducibly via **GitHub Actions**, tagged and pushed to GHCR as `ghcr.io/ibtisam-iq/dev-cicd-rootfs`.

---

## Architecture / Conceptual Overview

Dev CI/CD Rootfs is intentionally **the smallest image in the SilverStack rootfs family**. Where Dev Machine Rootfs layers a 35-phase toolchain install on top of the base, this image layers almost nothing:

```dockerfile
FROM ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest

USER $USER
ENV HOME=/home/$USER

COPY welcome $HOME/.welcome
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    bash /tmp/scripts/customize-bashrc.sh

EXPOSE 22
```

That is the entire Dockerfile. It inherits the base toolset (`jq`, `yq`, `fx`, `fzf`, `btop`, `code-server`, and the rest documented in [the base rootfs runbook](./setup-ubuntu-24-04-rootfs-base-image.md)) without installing a single additional package. The only image-specific work is one script:

| Script | Purpose |
|---|---|
| `customize-bashrc.sh` | Appends three `stack-*` SSH aliases and a handful of `ls` shortcuts to `~/.bashrc` |

Within the CI/CD Stack manifest, this image runs on the node named `dev-machine` (a naming collision with the standalone Dev Machine Rootfs playground) that is worth stating plainly so it does not cause confusion when reading the manifest or the welcome banner.

---

## Key Decisions

- **No toolchain install, on purpose.** Adding Docker, kubectl, Terraform, and the rest of the Dev Machine toolset here would spend vCPU and disk on a node whose only job is to run `ssh`. The full workstation is a separate image and a separate playground; putting it here would double-book resources that the three service nodes need more.

- **Sized as the smallest node in the stack.** The manifest allocates this node 1 vCPU and 1 GiB RAM against the stack's fixed 10 vCPU / 16 GiB budget, the minimum that comfortably runs SSH and an IDE tab. Every GiB not spent here is a GiB available to SonarQube, which needs the most.

- **`StrictHostKeyChecking=no` in the stack aliases is intentional.** Host keys on the target nodes are regenerated fresh at every playground boot, so strict checking would prompt on every new session. This is the one context in this project where disabling strict host key checking is the correct call rather than a shortcut.

- **`USER $USER` at the end is intentional: do not change it to `USER root`.** Same reasoning as [Dev Machine Rootfs](./setup-dev-machine-rootfs-image.md#key-decisions): the `USER` directive only controls what user `docker run` starts the container process as, for the binary-presence check. It has no effect on the iximiuz microVM boot, where the platform's kernel and systemd take over as PID 1 regardless of this directive.

---

## Source Layout

```text
dev/ci-cd/
├── Dockerfile
├── CONTENT.md                          # Playground description shown in the iximiuz dashboard
├── welcome
└── scripts/
    └── customize-bashrc.sh             # stack-jenkins / stack-sonarqube / stack-nexus aliases
```

---

## Build Arguments

| ARG | CI Default | Description |
|---|---|---|
| `USER` | `ibtisam` | Non-root interactive user (inherited from base) |
| `BUILD_DATE` | Set by `docker/metadata-action` | OCI label: image creation timestamp |
| `VCS_REF` | `github.sha` | OCI label: git commit SHA |

---

## Prerequisites

- `ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest` is built and published (the `FROM` reference).
- Local checkout of [`github.com/ibtisam-iq/silver-stack`](https://github.com/ibtisam-iq/silver-stack) with `iximiuz/rootfs/dev/ci-cd` available.
- Docker Buildx available locally, or a GitHub Actions runner with `docker/setup-buildx-action`.
- For CI: `packages: write` permission to push to GHCR via `secrets.GITHUB_TOKEN`.

---

## Build Steps

### 1. Local Build

From the `iximiuz/rootfs/dev/ci-cd/` directory:

```bash
IMAGE_NAME="ghcr.io/ibtisam-iq/dev-cicd-rootfs:latest"

docker build \
  --build-arg USER="ibtisam" \
  -t "${IMAGE_NAME}" \
  .
```

!!! note
    `BUILD_DATE` and `VCS_REF` are injected by CI. Local builds do not require them.

The Dockerfile performs the following sequence:

**Step 1: Inherit the base**

- `FROM ghcr.io/ibtisam-iq/ubuntu-24-04-rootfs:latest`: inherits systemd, SSH, `$USER` account, shell config, and base toolset. No `USER root` install phase, because nothing needs to be installed as root.

**Step 2: User customizations**

- `USER $USER` and `ENV HOME=/home/$USER`
- `COPY welcome $HOME/.welcome`: the stack-specific welcome banner, describing all four nodes and linking to the orchestration and operations runbooks.
- `customize-bashrc.sh` (bind mount): appends the `stack-jenkins`, `stack-sonarqube`, `stack-nexus` SSH aliases plus `ll`/`la`/`l` shortcuts to `~/.bashrc`.
- **`EXPOSE 22`**: documents the SSH port for iximiuz port-forwarding. SSH itself is managed by systemd inherited from the base image.

---

### 2. Build and Push via GitHub Actions

The canonical build runs via [`.github/workflows/build-dev-cicd-rootfs.yml`](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-dev-cicd-rootfs.yml).

**Triggers:**

- `push` to `main` when files under `iximiuz/rootfs/dev/ci-cd/**` (excluding `README.md` and `CONTENT.md`) or the workflow file change.
- Pull requests touching the same paths.
- Manual `workflow_dispatch`.

**Key steps:**

1. Checkout repository.
2. Set up Docker Buildx (no QEMU: amd64 only, intentional, matching every other child image in this family).
3. Log in to GHCR via `secrets.GITHUB_TOKEN`.
4. Extract metadata via `docker/metadata-action`: generates tags (`latest`, `sha-*`, `YYYY-MM-DD`) and OCI labels, including a `documentation` label pointing at this runbook's `#dev-cicd-machine-rootfs` anchor.
5. `docker/build-push-action` with:
    - `context: ./iximiuz/rootfs/dev/ci-cd`
    - `platforms: linux/amd64`
    - `push: true` (non-PR only)
    - `build-args: USER=ibtisam`
    - GHA layer cache enabled.
6. Print final image digest.

---

## Verification

### ✅ Correct: Inspect the Registry Image

After a CI push or manual `docker push`:

```bash
skopeo inspect docker://ghcr.io/ibtisam-iq/dev-cicd-rootfs:latest \
  | jq '{
      name:          .Name,
      base:          .Labels["org.opencontainers.image.base.name"],
      created:       .Labels["org.opencontainers.image.created"],
      documentation: .Labels["org.opencontainers.image.documentation"]
    }'
```

---

### ✅ Correct: Binary Presence Check (`docker run`: limited scope)

There is no toolchain to verify here beyond what the base image already provides. The only thing specific to this image is the welcome banner and the aliases:

```bash
docker run --rm \
  ghcr.io/ibtisam-iq/dev-cicd-rootfs:latest \
  bash -c "cat \$HOME/.welcome && grep 'stack-jenkins' \$HOME/.bashrc"
```

!!! note
    This confirms the banner and aliases were written correctly. It does **not** confirm SSH, systemd, or network reachability to the other three nodes: none of that exists inside a standalone `docker run`, only inside the composed playground.

---

### ✅ Correct: Full Runtime Verification (iximiuz microVM, composed stack)

This image only makes sense running as one node inside the four-machine stack, not in isolation:

```bash
labctl playground create --base flexbox cicd-stack -f cicd-stack.yml
```

Once connected to the `dev-machine` node:

```bash
# System health
systemctl is-system-running          # Expected: running

# Aliases present
alias | grep "^alias stack-jenkins="

# Reachability to the other three nodes
stack-jenkins      # should SSH straight into jenkins-server
```

Full multi-node verification (Nginx health checks on all three service nodes, intra-stack DNS) is covered in [Self-Hosted CI/CD Stack: Infrastructure & Orchestration](../../../self-hosted/ci-cd/iximiuz/setup-cicd-stack-orchestration.md).

---

### ❌ Not Valid: `docker run` for SSH or reachability checks

Running with `docker run` will not produce a working SSH daemon, and there are no sibling nodes to reach, because the private `172.16.0.0/24` network only exists once the manifest is booted as a Flexbox playground. Expected error:

```
System has not been booted with systemd as init system (PID 1). Can't operate.
```

This is **not a bug**; it is the same expected behavior documented across every rootfs image in this family.

---

## Integration with iximiuz Labs

This image is not launched on its own. It is one of four nodes defined in the CI/CD Stack manifest, and boots automatically as part of that playground:

```bash
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/iximiuz/manifests/cicd-stack.yml \
  -o cicd-stack.yml

labctl playground create --base flexbox cicd-stack -f cicd-stack.yml
```

The manifest's `dev-machine` node drive must reference this image:

```yaml
drives:
  - source: oci://ghcr.io/ibtisam-iq/dev-cicd-rootfs:latest
    mount: /
    size: 30GiB
```

Full manifest walkthrough, node topology, and tab layout: [Self-Hosted CI/CD Stack: Infrastructure & Orchestration](../../../self-hosted/ci-cd/iximiuz/setup-cicd-stack-orchestration.md).

---

## Related

- [Dev Machine Rootfs runbook](./setup-dev-machine-rootfs-image.md): the full workstation image, not this one
- [Ubuntu 24.04 base rootfs runbook](./setup-ubuntu-24-04-rootfs-base-image.md)
- [Self-Hosted CI/CD Stack: Infrastructure & Orchestration](../../../self-hosted/ci-cd/iximiuz/setup-cicd-stack-orchestration.md)
- [Dev CI/CD scripts](https://github.com/ibtisam-iq/silver-stack/tree/main/iximiuz/rootfs/dev/ci-cd/scripts)
- [Dev CI/CD welcome banner](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/rootfs/dev/ci-cd/welcome)
- [Dev CI/CD workflow](https://github.com/ibtisam-iq/silver-stack/blob/main/.github/workflows/build-dev-cicd-rootfs.yml)
- [Stack manifest](https://github.com/ibtisam-iq/silver-stack/blob/main/iximiuz/manifests/cicd-stack.yml)
- [Jenkins Rootfs runbook](./setup-jenkins-rootfs-image.md)
- [SonarQube Rootfs runbook](./setup-sonarqube-rootfs-image.md)
- [Nexus Rootfs runbook](./setup-nexus-rootfs-image.md)
