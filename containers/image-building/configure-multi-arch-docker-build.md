# Docker Multi-Architecture Image: Single-Arch to Multi-Arch Migration

## Context

A Docker image built with `docker build` produces a single-platform image tied to the architecture of the host running the build. When the same image needs to run on both `linux/amd64` and
`linux/arm64` hosts - such as when deploying to heterogeneous infrastructure or publishing a
public image - the single-platform image must be replaced with a multi-architecture manifest list.

This entry documents the complete process of converting an existing single-platform Docker image
into a multi-architecture image using `docker buildx`, covering the conceptual model, builder
setup, platform-aware build execution, and registry push.

---

## What Was Done

| Task | Outcome |
|---|---|
| Multi-platform builder created using `docker-container` driver | Builder ready to target `linux/amd64` and `linux/arm64` simultaneously |
| QEMU binary format handlers registered | Foreign-architecture emulation enabled for cross-platform builds |
| Multi-arch image built and pushed to registry | Manifest list stored in registry pointing to both platform variants |
| Manifest list verified | Both `linux/amd64` and `linux/arm64` entries confirmed present |

---

## Conceptual Overview

### What a Single-Architecture Image Is

A Docker image is a stack of read-only filesystem layers bundled with metadata. When built on an
`amd64` host with `docker build`, every binary inside the image - the base OS packages, installed
tools, and application binaries - is compiled for the `x86_64` instruction set. The image carries
platform metadata (`linux/amd64`) that tells the Docker daemon which CPU it requires. Running this
image on an `arm64` host either fails outright or requires software emulation.

### What a Multi-Architecture Image Is

A multi-architecture image is not a single image file. It is a **manifest list** (defined by the
[OCI Image Index Specification](https://github.com/opencontainers/image-spec/blob/main/image-index.md))
stored in a container registry. The manifest list is a JSON document that maps each platform
to a separate image digest.

```text
Manifest List (image index)
├── linux/amd64  --> sha256:aaa...  (separate image, amd64 binaries)
└── linux/arm64  --> sha256:bbb...  (separate image, arm64 binaries)
```

When `docker pull myimage:tag` runs, the Docker daemon reads the local host architecture,
queries the registry manifest list, and pulls only the correct platform variant. The user
specifies no platform flag. The selection is automatic and transparent.

### Why `docker build` Cannot Produce Multi-Arch Images

`docker build` builds for exactly one platform - the native platform of the Docker daemon.
It does not produce manifest lists and has no `--platform` flag that accepts multiple values.
Producing a manifest list requires:

1. Building each platform variant separately, and
2. Assembling those variants into a manifest list in the registry

`docker buildx` handles both steps in a single command.

### What `docker buildx` Is

`docker buildx` is Docker's extended build system built on
[BuildKit](https://github.com/moby/buildkit). It extends `docker build` with:

- Multi-platform builds targeting several architectures in one command
- Pluggable builder backends (local daemon, container, remote)
- Advanced caching and parallelism
- Direct push to a registry as the build output

`buildx` ships with Docker Desktop and has been included in Docker Engine since version 23.
No separate installation is required on standard Docker installations.

### What a Builder Instance Is

`buildx` uses the concept of a **builder** - a named BuildKit daemon with its own driver and
configuration. The default builder created by Docker Desktop uses the `docker` driver, which is
constrained to the host's native platform. Building for multiple platforms requires a builder
using the **`docker-container` driver**, which:

- Runs the BuildKit daemon inside a container
- Supports QEMU-based emulation for non-native architectures
- Accepts the `--platform` flag with multiple comma-separated targets

### What QEMU Does During a Cross-Platform Build

QEMU is an open-source machine emulator. In the context of Docker multi-arch builds, it provides
**user-space binary translation**: when a build step tries to execute a binary compiled for a
foreign architecture (e.g., running an `arm64` binary during a build on an `amd64` host), the
Linux kernel's `binfmt_misc` interface intercepts the execution, hands it to the registered QEMU
handler for that architecture, and QEMU translates the binary's system calls in real time.

This allows a single build host to produce images for architectures other than its own, at the
cost of slower build times compared to building natively on each target platform.

The `tonistiigi/binfmt` image registers QEMU handlers for all supported architectures. On
Docker Desktop (macOS and Windows), this registration is handled automatically at startup.
On a Linux Docker host, it must be run explicitly once.

### The `TARGETARCH` Build Argument

When `docker buildx build --platform linux/amd64,linux/arm64` runs, BuildKit injects several
automatic build arguments into the Dockerfile for each platform variant being built:

| Variable | Example value (amd64) | Example value (arm64) |
|---|---|---|
| `TARGETPLATFORM` | `linux/amd64` | `linux/arm64` |
| `TARGETARCH` | `amd64` | `arm64` |
| `TARGETOS` | `linux` | `linux` |
| `BUILDARCH` | architecture of the build host | architecture of the build host |

These are available inside the Dockerfile by declaring `ARG TARGETARCH` without a default value.
They allow `RUN` steps to branch on the target architecture when downloading binaries or
selecting platform-specific packages:

```dockerfile
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) BINARY_URL="https://example.com/tool-linux-amd64" ;; \
      arm64) BINARY_URL="https://example.com/tool-linux-arm64" ;; \
    esac && \
    curl -fsSL "${BINARY_URL}" -o /usr/local/bin/tool && \
    chmod +x /usr/local/bin/tool
```

> **Why `ARG TARGETARCH` with no value?**
> BuildKit injects these variables automatically only when they are declared as `ARG` without an
> assigned value. If a default value is set (e.g., `ARG TARGETARCH=amd64`), the injected value
> is overridden and the build always behaves as if it is targeting `amd64`.

### Why `--push` Is Required for Multi-Arch Output

`docker buildx build --load` stores the built image into the local Docker daemon's image store.
The local image store holds single-platform images only. It cannot store a manifest list. This
means `--load` only functions when `--platform` specifies exactly one target.

When building for two or more platforms simultaneously, the output must go directly to a registry
that supports OCI manifest lists. Docker Hub and GitHub Container Registry (`ghcr.io`) both
support this format. The `--push` flag replaces `--load` for multi-platform builds.

---

## Prerequisites

- Docker Engine version 23 or later, or Docker Desktop (any recent version)
- Docker daemon running
- A container registry account (Docker Hub, `ghcr.io`, or any OCI-compatible registry)
- The image tagged with a registry-qualified name: `<registry>/<namespace>/<image>:<tag>`
- On a **Linux host only**: root or `sudo` access to register QEMU handlers (one-time setup)

> **On Docker Desktop (macOS or Windows):** QEMU is pre-installed and registered automatically.
> Steps 1a and 1b below are not required and can be skipped.

---

## Steps

### Step 1 (Linux hosts only): Register QEMU Binary Format Handlers

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

> **Why `--privileged`?**
> Registering binary format handlers requires writing to `/proc/sys/fs/binfmt_misc`, which is a
> kernel interface. Container access to kernel interfaces requires the `--privileged` flag.
> The `--rm` flag removes the container immediately after the handlers are registered - it is
> a one-shot operation, not a long-running service.

Expected output:

```text
installing: arm64 OK
installing: amd64 OK
installing: riscv64 OK
...
```

This registration persists until the host reboots. On most systems it is run once during
initial setup. Some teams add it to a host bootstrap script or a `systemd` unit.

### Step 2: Verify `buildx` Is Available

```bash
docker buildx version
```

Expected output:

```text
github.com/docker/buildx v0.19.3 linux/amd64
```

If this command returns `docker: 'buildx' is not a docker command`, the Docker installation
predates the bundled `buildx` plugin. In that case, install it from the
[docker/buildx releases page](https://github.com/docker/buildx/releases).

### Step 3: Create a Multi-Platform Builder

```bash
docker buildx create \
  --name multi-builder \
  --driver docker-container \
  --use
```

> **Why `--driver docker-container` and not the default driver?**
> The default `docker` driver runs BuildKit inside the Docker daemon itself and is constrained
> to the host's native platform. The `docker-container` driver launches a dedicated BuildKit
> container that has QEMU handlers available and can cross-compile for foreign platforms.

> **Why `--use`?**
> `--use` sets this builder as the active builder for all subsequent `buildx` commands in the
> current shell session. Without it, the new builder is created but not activated.

Expected output:

```text
multi-builder
```

### Step 4: Bootstrap the Builder and Confirm Supported Platforms

```bash
docker buildx inspect --bootstrap
```

> **Why bootstrap before building?**
> `--bootstrap` starts the BuildKit daemon container and initialises it. Without this step, the
> first build command triggers the bootstrap implicitly, making the initial build appear to hang
> without feedback. Running bootstrap explicitly confirms the builder is healthy and shows the
> platform list before any build is attempted.

Expected output (relevant section):

```text
Name:   multi-builder
Driver: docker-container

Nodes:
Name:      multi-builder0
Status:    running
Platforms: linux/amd64, linux/amd64/v2, linux/arm64, linux/riscv64, linux/ppc64le, linux/s390x
```

Confirm that both `linux/amd64` and `linux/arm64` appear in the `Platforms` list before
proceeding. If either is absent, the QEMU registration in Step 1 did not complete successfully.

### Step 5: Build and Push the Multi-Architecture Image

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag <registry>/<namespace>/<image>:<tag> \
  --push \
  <path-to-build-context>
```

Replace `<registry>/<namespace>/<image>:<tag>` with the fully qualified image name, for example
`docker.io/myuser/myimage:latest` or `ghcr.io/myorg/myimage:v1.0`.

Replace `<path-to-build-context>` with the directory containing the `Dockerfile`, for example `.`
for the current directory.

> **What happens during this build?**
> BuildKit runs two parallel build pipelines - one targeting `linux/amd64` and one targeting
> `linux/arm64`. For the non-native target, QEMU provides instruction-set emulation for any
> `RUN` steps that execute binaries. Once both platform builds complete, BuildKit assembles a
> manifest list and pushes it to the registry in a single atomic operation. The local Docker
> daemon does not store either image variant locally.

Expected terminal output (structure):

```text
[+] Building 142.3s (24/24) FINISHED
 => [linux/amd64] FROM docker.io/library/ubuntu:22.04
 => [linux/arm64] FROM docker.io/library/ubuntu:22.04
 => [linux/amd64] RUN apt-get update ...
 => [linux/arm64] RUN apt-get update ...
 ...
 => pushing manifest for <registry>/<namespace>/<image>:<tag>
```

> **Note:** The `arm64` build steps run slower than the `amd64` steps when the build host is
> `amd64`, because those steps execute under QEMU emulation. This is expected. The performance
> difference is visible in the build log timing.

---

## Verification

### Verify the Manifest List in the Registry

```bash
docker buildx imagetools inspect <registry>/<namespace>/<image>:<tag>
```

Expected output:

```text
Name:      <registry>/<namespace>/<image>:<tag>
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:...

Manifests:
  Name:      <registry>/<namespace>/<image>:<tag>@sha256:aaa...
  MediaType: application/vnd.oci.image.manifest.v1+json
  Platform:  linux/amd64

  Name:      <registry>/<namespace>/<image>:<tag>@sha256:bbb...
  MediaType: application/vnd.oci.image.manifest.v1+json
  Platform:  linux/arm64
```

Both `linux/amd64` and `linux/arm64` entries in the `Manifests` section confirm the push
succeeded and the manifest list is correctly formed. A `docker pull` from any supported
platform will now resolve to the correct variant automatically.

If only one platform entry appears, the `--platform` flag was likely applied to a `--load`
build rather than a `--push` build, and the manifest list was never assembled.

### Pull and Test a Specific Platform Variant

To pull and test the `arm64` variant explicitly on an `amd64` host:

```bash
docker pull --platform linux/arm64 <registry>/<namespace>/<image>:<tag>
docker run --rm --platform linux/arm64 <registry>/<namespace>/<image>:<tag> uname -m
```

Expected output:

```text
aarch64
```

`aarch64` confirms the container is running the `arm64` image variant. On a native `arm64` host,
the same `docker run` command without the `--platform` flag produces the same output.

### List Active Builders

```bash
docker buildx ls
```

Expected output (relevant columns):

```text
NAME/NODE          DRIVER/ENDPOINT   STATUS    PLATFORMS
multi-builder *    docker-container
  multi-builder0   ...               running   linux/amd64, linux/arm64, ...
default            docker
  default          ...               running   linux/amd64
```

The `*` next to `multi-builder` confirms it is active. The absence of `linux/arm64` from the
`default` builder confirms why a new builder was required.

---

## Troubleshooting

### `exec format error` during build

**Cause:** QEMU handlers are not registered for the target architecture. This error appears in a
`RUN` step when the build tries to execute a binary compiled for the non-native architecture.

**Fix:** Run the QEMU registration step (Step 1) and retry. On a Linux host, confirm with:

```bash
ls /proc/sys/fs/binfmt_misc/ | grep qemu
```

Expected output includes `qemu-aarch64` and `qemu-x86_64`.

### `--load` fails when multiple platforms are specified

**Symptom:** `docker buildx build --platform linux/amd64,linux/arm64 --load` returns an error
such as:

```text
error: docker exporter does not currently support exporting manifest lists
```

**Cause:** The local Docker image store does not support manifest lists. `--load` only accepts
a single platform target.

**Fix:** Replace `--load` with `--push`. To test a single platform variant locally without
pushing, build with one platform:

```bash
docker buildx build --platform linux/arm64 --load --tag myimage:test .
```

### Builder shows `inactive` status

**Cause:** The BuildKit container for the builder exited or was removed.

**Fix:**

```bash
docker buildx rm multi-builder
docker buildx create --name multi-builder --driver docker-container --use
docker buildx inspect --bootstrap
```

---

## Key Decisions

### `docker-container` driver over `docker` driver

The default `docker` driver builds natively only. The `docker-container` driver was chosen
because it is the only local driver that supports multi-platform builds via QEMU. The tradeoff
is that the first build requires pulling the BuildKit image, but this is a one-time cost.

### `--push` over local export

Multi-platform output is a manifest list. The local Docker daemon cannot store manifest lists.
`--push` is not a workaround - it is the correct and only supported output method for builds
targeting multiple platforms simultaneously.
