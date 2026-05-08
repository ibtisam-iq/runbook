# Bootstrap Folder Structure Plan

> **Purpose of this file:** This document is the master plan for the `bootstrap/` section of this runbook.
> It defines every subfolder, every file, and maps every tool from the `install-tools-all.sh` script
> (31 phases, 350+ tools) to its exact location inside `bootstrap/`.
>
> **Golden Rule:** `bootstrap/` contains **installation runbooks only**.
> How to use a tool after it is installed belongs in its respective operational section
> (`kubernetes/`, `delivery/`, `security/`, `observability/`, etc.).

---

## What is `bootstrap/`?

`bootstrap/` answers one and only one question:

> *"I have a fresh Ubuntu 24.04 machine. How do I install `<tool>` on it?"*

Every file inside `bootstrap/` is an installation runbook — the commands, the method (apt, pip, cargo, binary, script), the version pinning, and the PATH/environment setup required to make the tool available system-wide.

This section is derived from the master script:
`iximiuz/rootfs/dev/machine/scripts/install-tools-all.sh`

---

## Root-Level Folder Structure

```
bootstrap/
├── index.md                        ← Overview + navigation map
├── bootstrap-folder-structure-plan.md  ← This file
│
├── kubernetes/                     ← Kubernetes cluster + ecosystem tool installs
├── container-runtime/              ← Docker, Podman, Buildah, image tools
├── language-runtimes/              ← Python, Node.js, Go, Rust, Java, Ruby
├── system-foundation/              ← APT base, shells, editors, build tools, compression
├── networking-tools/               ← Network diagnostics, VPN, DNS, firewall, HTTP
├── storage-tools/                  ← Disk, filesystem, NFS, FUSE
├── debugging-profiling/            ← strace, gdb, bpftrace, sysstat
├── iac/                            ← Terraform, Ansible, Packer, Vault, Helm ecosystem
├── security-tools/                 ← Scanning, SAST, policy engines, secret scanning, OS hardening
├── observability-tools/            ← Prometheus, Loki, Grafana, Jaeger, OTel, Vector
├── cloud-clis/                     ← AWS, GCP, Azure, DigitalOcean, Hetzner, Cloudflare, etc.
├── database-clis/                  ← psql, mysql, mongosh, redis-cli, etcdctl, nats
├── devops-clis/                    ← jq, yq, gh, lazygit, fzf, task, pre-commit, etc.
├── shell-environment/              ← starship, zoxide, chezmoi, nushell, tldr, modern CLI replacements
├── ai-ml-clis/                     ← LLM CLIs, AI SDKs, MLOps tools
├── documentation-tools/            ← MkDocs, mdBook, Pandoc, Mermaid, D2, PlantUML
├── arkade/                         ← arkade itself (the tool installer)
└── components/                     ← Index/overview page linking all above folders
```

**Total folders:** 18
**Total files (planned):** ~128

---

## Detailed Structure Per Folder

---

### `bootstrap/kubernetes/`

> Kubernetes cluster bootstrap + all Kubernetes ecosystem tool installs.
> The `install-kubernetes-cluster/` subfolder already exists and is complete.
> The additional files below cover the wider Kubernetes toolchain.

**Script phases covered:** Phase 19 (partial), Phase 20, Phase 23 (partial)

```
kubernetes/
├── install-kubernetes-cluster/     ← ALREADY DONE ✅
│   ├── index.md
│   ├── kubernetes-overview.md
│   ├── kubernetes-packages.md
│   ├── node-preparation.md
│   ├── container-runtime.md
│   ├── cluster-bootstrap.md
│   ├── kubeconfig-and-cni.md
│   ├── kind-local-cluster.md
│   └── maintenance-and-reset.md
│
├── helm.md                         ← helm binary install via arkade
├── kustomize.md                    ← kustomize via arkade
├── cluster-management.md           ← kubectx, kubens install
├── workload-tools.md               ← stern, k9s, kubeseal install
├── gitops.md                       ← flux, argocd, tilt install
├── rollouts.md                     ← kubectl-argo-rollouts binary install
├── krew-plugins.md                 ← krew install + all plugins:
│                                      ctx, ns, neat, images, resource-capacity,
│                                      node-shell, whoami, view-secret,
│                                      df-pv, get-all, sniff, trace
├── service-mesh.md                 ← cilium CLI, istioctl, linkerd2 install
├── vcluster.md                     ← vcluster install
├── local-clusters.md               ← kind, k3d, minikube install
└── validation-tools.md             ← kubeconform, kube-score, popeye,
                                       polaris, pluto, nova install
```

**Tools covered in this folder:**

| Tool | Install Method | File |
|------|---------------|------|
| kubectl | kubeadm / arkade | `install-kubernetes-cluster/` |
| helm | arkade | `helm.md` |
| kustomize | arkade | `kustomize.md` |
| kubectx | arkade | `cluster-management.md` |
| kubens | arkade | `cluster-management.md` |
| k9s | arkade | `workload-tools.md` |
| stern | arkade | `workload-tools.md` |
| kubeseal | arkade | `workload-tools.md` |
| flux | arkade | `gitops.md` |
| argocd | arkade | `gitops.md` |
| tilt | arkade | `gitops.md` |
| kubectl-argo-rollouts | GitHub binary | `rollouts.md` |
| krew | GitHub tarball | `krew-plugins.md` |
| cilium | arkade | `service-mesh.md` |
| istioctl | arkade | `service-mesh.md` |
| linkerd2 | arkade | `service-mesh.md` |
| vcluster | arkade | `vcluster.md` |
| kind | arkade | `local-clusters.md` |
| k3d | arkade | `local-clusters.md` |
| minikube | arkade | `local-clusters.md` |
| kubeconform | GitHub tarball | `validation-tools.md` |
| kube-score | GitHub binary | `validation-tools.md` |
| popeye | GitHub tarball | `validation-tools.md` |
| polaris | GitHub tarball | `validation-tools.md` |
| pluto | GitHub tarball | `validation-tools.md` |
| nova | GitHub tarball | `validation-tools.md` |

---

### `bootstrap/container-runtime/`

> All container runtimes, image build tools, and image inspection tools.

**Script phases covered:** Phase 14, Phase 19 (partial), Phase 23 (partial)

```
container-runtime/
├── docker.md             ← docker-ce, docker-ce-cli, containerd.io,
│                            docker-buildx-plugin, docker-compose-plugin
│                            (Docker CE official apt repo method)
├── podman.md             ← podman, buildah, skopeo (apt install)
├── nerdctl.md            ← nerdctl binary from GitHub releases
├── image-tools.md        ← dive, crane, regctl install
└── hadolint.md           ← hadolint binary (Dockerfile linter)
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| docker-ce | apt (Docker CE repo) | `docker.md` |
| docker-ce-cli | apt | `docker.md` |
| containerd.io | apt | `docker.md` |
| docker-buildx-plugin | apt | `docker.md` |
| docker-compose-plugin | apt | `docker.md` |
| podman | apt | `podman.md` |
| buildah | apt | `podman.md` |
| skopeo | apt | `podman.md` |
| nerdctl | GitHub binary | `nerdctl.md` |
| dive | arkade | `image-tools.md` |
| crane | arkade | `image-tools.md` |
| regctl | arkade + GitHub binary | `image-tools.md` |
| hadolint | GitHub binary | `hadolint.md` |

---

### `bootstrap/language-runtimes/`

> Every programming language runtime and its package manager.
> **Install only** — how to run projects in these languages belongs in `delivery/project-runtimes/`.

**Script phases covered:** Phase 4, Phase 15, Phase 16, Phase 17

```
language-runtimes/
├── python.md        ← python3, pip, venv, python3-dev, setuptools
│                       + dev libs: libpq-dev, libffi-dev, libssl-dev, libmysqlclient-dev
├── nodejs.md        ← Node.js v20.x LTS via NodeSource setup_20.x script + npm
├── java.md          ← openjdk-21-jdk via apt
├── go.md            ← Go 1.22 tarball from go.dev/dl, extraction to /usr/local/,
│                       /etc/profile.d/go.sh for PATH + GOPATH
├── rust.md          ← rustup via sh.rustup.rs, rustc + cargo,
│                       ~/.cargo/bin PATH export
├── ruby.md          ← ruby, ruby-dev, rubygems via apt
└── other.md         ← perl, lua5.4 via apt
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| python3 | apt | `python.md` |
| pip | apt (python3-pip) | `python.md` |
| python3-venv | apt | `python.md` |
| python3-dev | apt | `python.md` |
| libpq-dev | apt | `python.md` |
| libffi-dev | apt | `python.md` |
| libssl-dev | apt | `python.md` |
| libmysqlclient-dev | apt | `python.md` |
| Node.js v20.x | NodeSource script | `nodejs.md` |
| npm | included with Node | `nodejs.md` |
| openjdk-21-jdk | apt | `java.md` |
| Go 1.22 | tarball (go.dev) | `go.md` |
| rustc | rustup | `rust.md` |
| cargo | rustup | `rust.md` |
| ruby | apt | `ruby.md` |
| ruby-dev | apt | `ruby.md` |
| rubygems | apt | `ruby.md` |
| perl | apt | `other.md` |
| lua5.4 | apt | `other.md` |

---

### `bootstrap/system-foundation/`

> The absolute base of any Ubuntu machine — system services, shells, editors, build tools, compression, file utilities, and version control.

**Script phases covered:** Phase 1, Phase 2, Phase 3, Phase 5, Phase 6, Phase 12

```
system-foundation/
├── apt-setup.md             ← apt-get update + upgrade + dist-upgrade
│                               + DEBIAN_FRONTEND=noninteractive setup
├── core-packages.md         ← systemd, dbus, udev, kmod, locales,
│                               ca-certificates, lsb-release, sudo
├── shells.md                ← bash, zsh, fish,
│                               bash-completion, zsh-autosuggestions,
│                               zsh-syntax-highlighting
├── terminal-multiplexers.md ← tmux, screen
├── build-tools.md           ← build-essential, gcc, g++, clang, llvm, cmake,
│                               pkg-config, autoconf, automake, libtool,
│                               make, ninja-build, meson
├── compression-tools.md     ← bzip2, xz-utils, zstd, unzip, zip,
│                               p7zip-full, tar, gzip
├── editors.md               ← vim, neovim, nano, emacs-nox
├── system-monitors.md       ← htop, iotop, atop, less, most, bat
├── file-tools.md            ← tree, ncdu, lsof, file, rsync, pv, progress,
│                               inotify-tools, direnv, entr, parallel, gettext-base
├── search-tools.md          ← ripgrep (rg), fd-find
└── version-control.md       ← git, git-lfs, tig
```

---

### `bootstrap/networking-tools/`

> All network diagnostic, scanning, packet analysis, DNS, firewall, VPN, HTTP, and tunnel tools.

**Script phases covered:** Phase 7

```
networking-tools/
├── diagnostic-tools.md  ← iproute2, net-tools, iputils-ping, iputils-tracepath,
│                            traceroute, mtr, tcptraceroute
├── scanning-tools.md    ← nmap, ncat, socat, netcat-openbsd
├── packet-analysis.md   ← tcpdump, tshark, wireshark-common
├── bandwidth-tools.md   ← iperf3, iftop, nethogs, vnstat, iptraf-ng
├── dns-tools.md         ← dnsutils, bind9-dnsutils, whois, host,
│                            dnsmasq, avahi-daemon
├── firewall-tools.md    ← iptables, nftables, ipset, conntrack,
│                            bridge-utils, vlan, ethtool
├── vpn-tools.md         ← wireguard-tools, openvpn, strongswan, stunnel4
├── http-tools.md        ← curl, wget, httpie
└── tunnel-proxy.md      ← ngrok, cloudflared, caddy
```

---

### `bootstrap/storage-tools/`

> Disk management, filesystem utilities, network storage, and FUSE tools.

**Script phases covered:** Phase 8

```
storage-tools/
├── disk-management.md   ← lvm2, mdadm, cryptsetup, parted, fdisk, gdisk
├── filesystems.md       ← e2fsprogs (ext4), xfsprogs (xfs), btrfs-progs
├── network-storage.md   ← nfs-common, nfs-kernel-server, cifs-utils, smbclient
├── fuse-tools.md        ← fuse3, sshfs, davfs2
└── disk-health.md       ← smartmontools, hdparm
```

---

### `bootstrap/debugging-profiling/`

> System call tracing, performance profiling, process inspection, and eBPF tools.

**Script phases covered:** Phase 9

```
debugging-profiling/
├── system-tracing.md  ← strace, ltrace, fatrace, auditd, systemd-coredump
├── profiling.md       ← sysstat, gdb, valgrind
├── process-tools.md   ← procps, psmisc
└── ebpf-tools.md      ← linux-tools-generic, bpftrace, bpfcc-tools
```

---

### `bootstrap/iac/`

> Infrastructure as Code tools — provisioning, configuration management, secret encryption, and the Helm IaC ecosystem.

**Script phases covered:** Phase 13 (ansible, yamllint), Phase 19 (terraform, terragrunt, packer, vault, consul, sops, age)

```
iac/
├── terraform.md        ← terraform + terragrunt (both via arkade)
├── ansible.md          ← ansible + ansible-lint (via pip3)
├── packer.md           ← packer (via arkade)
├── vault-consul.md     ← vault + consul (both via arkade)
├── helm-ecosystem.md   ← helmfile (GitHub binary) +
│                          helm-diff, helm-secrets, helm-push (helm plugin install)
├── secrets-tools.md    ← sops + age (both via arkade)
└── templating.md       ← gomplate (GitHub binary)
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| terraform | arkade | `terraform.md` |
| terragrunt | arkade | `terraform.md` |
| ansible | pip3 | `ansible.md` |
| ansible-lint | pip3 | `ansible.md` |
| yamllint | pip3 | `ansible.md` |
| packer | arkade | `packer.md` |
| vault | arkade | `vault-consul.md` |
| consul | arkade | `vault-consul.md` |
| helmfile | GitHub binary | `helm-ecosystem.md` |
| helm-diff | helm plugin | `helm-ecosystem.md` |
| helm-secrets | helm plugin | `helm-ecosystem.md` |
| helm-push | helm plugin | `helm-ecosystem.md` |
| sops | arkade | `secrets-tools.md` |
| age | arkade | `secrets-tools.md` |
| gomplate | GitHub binary | `templating.md` |

---

### `bootstrap/security-tools/`

> Security scanning (image, code, secrets), policy enforcement, OS hardening, pentest CLIs, and TLS/certificate tools.

**Script phases covered:** Phase 10, Phase 13 (bandit, detect-secrets, semgrep), Phase 19 (trivy, cosign, syft, grype), Phase 21 (gosec, golangci-lint), Phase 23 (gitleaks, trufflehog, kube-bench, kubescape, kyverno, OPA, conftest, terrascan, polaris, snyk, nuclei, ffuf)

```
security-tools/
├── os-hardening.md      ← fail2ban, ufw, apparmor, apparmor-utils, acl, attr
├── audit-tools.md       ← chkrootkit, rkhunter, lynis
├── gpg-pass.md          ← gpg, gnupg2, pass
├── image-scanning.md    ← trivy, grype, syft, cosign
├── secret-scanning.md   ← gitleaks, trufflehog, detect-secrets
├── sast.md              ← semgrep, bandit (Python SAST),
│                            gosec (Go SAST), golangci-lint
├── policy-engines.md    ← OPA (opa binary), conftest, kyverno CLI,
│                            terrascan, polaris, snyk
├── pentest-tools.md     ← nuclei, ffuf, nikto, sqlmap
└── tls-certs.md         ← mkcert, cfssl (Go install), openssl (cert generation context)
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| fail2ban | apt | `os-hardening.md` |
| ufw | apt | `os-hardening.md` |
| apparmor | apt | `os-hardening.md` |
| apparmor-utils | apt | `os-hardening.md` |
| acl | apt | `os-hardening.md` |
| attr | apt | `os-hardening.md` |
| chkrootkit | apt | `audit-tools.md` |
| rkhunter | apt | `audit-tools.md` |
| lynis | apt | `audit-tools.md` |
| gpg | apt | `gpg-pass.md` |
| gnupg2 | apt | `gpg-pass.md` |
| pass | apt | `gpg-pass.md` |
| trivy | arkade | `image-scanning.md` |
| grype | arkade | `image-scanning.md` |
| syft | arkade | `image-scanning.md` |
| cosign | arkade | `image-scanning.md` |
| gitleaks | GitHub tarball | `secret-scanning.md` |
| trufflehog | GitHub tarball | `secret-scanning.md` |
| detect-secrets | pip3 | `secret-scanning.md` |
| semgrep | pip3 | `sast.md` |
| bandit | pip3 | `sast.md` |
| gosec | go install | `sast.md` |
| golangci-lint | go install | `sast.md` |
| opa | GitHub binary | `policy-engines.md` |
| conftest | GitHub tarball | `policy-engines.md` |
| kyverno | GitHub tarball | `policy-engines.md` |
| terrascan | GitHub tarball | `policy-engines.md` |
| polaris | GitHub tarball | `policy-engines.md` |
| snyk | curl binary | `policy-engines.md` |
| nuclei | GitHub zip | `pentest-tools.md` |
| ffuf | GitHub tarball | `pentest-tools.md` |
| nikto | apt | `pentest-tools.md` |
| sqlmap | apt | `pentest-tools.md` |
| mkcert | go install | `tls-certs.md` |
| cfssl | go install | `tls-certs.md` |
| openssl | apt | `tls-certs.md` |

---

### `bootstrap/observability-tools/`

> Metrics, logging, tracing, and telemetry CLIs.

**Script phases covered:** Phase 19 (promtool), Phase 25

```
observability-tools/
├── prometheus.md        ← promtool (Prometheus rule checker + query tool)
│                           installed via arkade
├── loki.md              ← loki binary + logcli (both from Grafana GitHub releases)
├── grafana.md           ← grafana-cli extracted from grafana tarball
├── opentelemetry.md     ← otelcol-contrib tarball + otelcol symlink
├── vector.md            ← vector via sh.vector.dev install script
├── jaeger.md            ← jaeger binaries from jaegertracing GitHub release
├── tempo.md             ← tempo binary from grafana/tempo GitHub release
└── mimir.md             ← mimirtool binary from grafana/mimir GitHub release
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| promtool | arkade | `prometheus.md` |
| loki | GitHub release | `loki.md` |
| logcli | GitHub release | `loki.md` |
| grafana-cli | GitHub tarball | `grafana.md` |
| otelcol-contrib | GitHub tarball | `opentelemetry.md` |
| vector | install script | `vector.md` |
| jaeger | GitHub tarball | `jaeger.md` |
| tempo | GitHub tarball | `tempo.md` |
| mimirtool | GitHub binary | `mimir.md` |

---

### `bootstrap/cloud-clis/`

> Every cloud provider CLI tool.

**Script phases covered:** Phase 24

```
cloud-clis/
├── aws.md              ← AWS CLI v2 (curl zip + unzip + /tmp/aws/install)
├── gcp.md              ← Google Cloud SDK via apt repo
│                          (packages.cloud.google.com)
├── azure.md            ← Azure CLI via aka.ms/InstallAzureCLIDeb script
├── digitalocean.md     ← doctl via arkade
├── hetzner.md          ← hcloud binary from GitHub release
├── cloudflare.md       ← wrangler via npm install -g
│                          + cloudflared GitHub binary
└── other-providers.md  ← vultr-cli (GitHub tarball)
                           scw / Scaleway (GitHub binary)
                           linode-cli (pip3)
                           civo (arkade)
                           ibmcloud (curl script)
                           oci / Oracle Cloud (bash install script)
                           flyctl (curl script + copy to /usr/local/bin)
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| aws | curl + unzip | `aws.md` |
| gcloud | apt repo | `gcp.md` |
| az | Microsoft script | `azure.md` |
| doctl | arkade | `digitalocean.md` |
| hcloud | GitHub binary | `hetzner.md` |
| wrangler | npm | `cloudflare.md` |
| cloudflared | GitHub binary | `cloudflare.md` |
| vultr-cli | GitHub tarball | `other-providers.md` |
| scw | GitHub binary | `other-providers.md` |
| linode-cli | pip3 | `other-providers.md` |
| civo | arkade | `other-providers.md` |
| ibmcloud | curl script | `other-providers.md` |
| oci | bash install script | `other-providers.md` |
| flyctl | curl script | `other-providers.md` |

---

### `bootstrap/database-clis/`

> All database and message broker CLI clients.

**Script phases covered:** Phase 11 (apt), Phase 13 (pgcli, mycli), Phase 29

```
database-clis/
├── postgresql.md   ← postgresql-client (apt) + pgcli (pip3)
├── mysql.md        ← mysql-client (apt) + mycli (pip3)
├── sqlite.md       ← sqlite3 (apt)
├── redis.md        ← redis-tools / redis-cli (apt)
├── mongodb.md      ← mongosh (MongoDB downloads tarball)
├── etcd.md         ← etcdctl from etcd-io GitHub release tarball
├── nats.md         ← nats CLI from nats-io GitHub release tarball
└── universal.md    ← usql (universal SQL CLI) from xo/usql GitHub release
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| psql / postgresql-client | apt | `postgresql.md` |
| pgcli | pip3 | `postgresql.md` |
| mysql-client | apt | `mysql.md` |
| mycli | pip3 | `mysql.md` |
| sqlite3 | apt | `sqlite.md` |
| redis-cli / redis-tools | apt | `redis.md` |
| mongosh | GitHub tarball | `mongodb.md` |
| etcdctl | GitHub tarball | `etcd.md` |
| nats | GitHub tarball | `nats.md` |
| usql | GitHub tarball | `universal.md` |

---

### `bootstrap/devops-clis/`

> Standalone DevOps CLI tools — git helpers, data processors, task runners, and benchmarking tools.

**Script phases covered:** Phase 19 (partial), Phase 21, Phase 22 (partial), Phase 26 (partial)

```
devops-clis/
├── git-tools.md         ← gh (GitHub CLI via arkade)
│                           glab (GitLab CLI via arkade)
│                           lazygit (arkade)
│                           gitui (cargo)
│                           gh-dash (GitHub binary)
├── container-helpers.md ← lazydocker (arkade)
├── task-runners.md      ← just (arkade + cargo)
│                           task (arkade)
├── data-processing.md   ← jq (arkade)
│                           yq (arkade)
│                           dasel (GitHub binary)
│                           jless (GitHub zip)
│                           gron (go install)
│                           miller / mlr (GitHub tarball)
│                           xsv (GitHub tarball)
│                           csvkit (pip3)
│                           htmlq (GitHub tarball)
├── fuzzy-tools.md       ← fzf (arkade)
├── tekton.md            ← tkn / Tekton CLI (arkade)
├── shell-linting.md     ← shfmt (go install)
│                           thefuck (pip3)
│                           yamllint (pip3)
├── benchmarking.md      ← hyperfine (cargo)
│                           tokei (cargo)
│                           hey (arkade)
├── code-tools.md        ← ko (go install — builds OCI images from Go source)
│                           gops (go install — Go process inspector)
│                           hugo (go install — static site generator)
│                           hakrawler (go install — web crawler)
└── pre-commit.md        ← pre-commit (pip3)
```

---

### `bootstrap/shell-environment/`

> Shell prompt, directory jumping, dotfiles management, modern CLI replacements, and help tools.

**Script phases covered:** Phase 22 (partial), Phase 26

```
shell-environment/
├── starship.md      ← starship prompt (cargo install)
├── zoxide.md        ← zoxide smart cd (cargo install)
├── chezmoi.md       ← chezmoi dotfiles manager (GitHub tarball)
├── nushell.md       ← nushell / nu (GitHub tarball, musl build)
├── help-tools.md    ← tldr (npm install -g)
│                       cheat (GitHub binary)
│                       navi (GitHub tarball)
│                       pet (GitHub tarball)
└── modern-cli.md    ← exa (cargo — ls replacement)
                        bat (cargo — cat replacement, also apt)
                        sd (cargo — sed replacement)
                        bottom / btm (cargo — htop replacement)
                        procs (cargo — ps replacement)
                        du-dust / dust (cargo — du replacement)
                        bandwhich (cargo — network usage)
                        glow (go install — markdown reader)
```

**Tools covered:**

| Tool | Install Method | File |
|------|---------------|------|
| starship | cargo | `starship.md` |
| zoxide | cargo | `zoxide.md` |
| chezmoi | GitHub tarball | `chezmoi.md` |
| nushell (nu) | GitHub tarball | `nushell.md` |
| tldr | npm | `help-tools.md` |
| cheat | GitHub binary | `help-tools.md` |
| navi | GitHub tarball | `help-tools.md` |
| pet | GitHub tarball | `help-tools.md` |
| exa | cargo | `modern-cli.md` |
| bat | cargo | `modern-cli.md` |
| sd | cargo | `modern-cli.md` |
| bottom (btm) | cargo | `modern-cli.md` |
| procs | cargo | `modern-cli.md` |
| du-dust | cargo | `modern-cli.md` |
| bandwhich | cargo | `modern-cli.md` |
| glow | go install | `modern-cli.md` |

---

### `bootstrap/ai-ml-clis/`

> AI/LLM terminal tools, AI SDK CLIs, and MLOps command-line utilities.

**Script phases covered:** Phase 27

```
ai-ml-clis/
├── llm-clis.md      ← llm (Simon Willison — pip3)
│                       aichat (GitHub tarball, musl build)
│                       mods (GitHub tarball, charmbracelet)
│                       sgpt / shell-gpt (pip3)
├── ai-sdks.md       ← openai (pip3)
│                       anthropic (pip3)
│                       litellm (pip3)
│                       huggingface-cli / huggingface_hub (pip3)
├── mlops-tools.md   ← mlflow (pip3)
│                       dvc (pip3)
│                       wandb (pip3)
│                       tensorboard (pip3)
├── aider.md         ← aider-chat (pip3 — AI pair programmer)
└── langchain.md     ← langchain-cli (pip3)
```

---

### `bootstrap/documentation-tools/`

> Tools for writing, rendering, and exporting documentation.

**Script phases covered:** Phase 13 (mkdocs, mkdocs-material), Phase 28

```
documentation-tools/
├── mkdocs.md        ← mkdocs + mkdocs-material (pip3)
├── mdbook.md        ← mdBook binary from rust-lang GitHub release
├── pandoc.md        ← pandoc tarball from jgm/pandoc GitHub release
├── asciidoc.md      ← asciidoctor (gem install)
└── diagram-tools.md ← mermaid-cli / mmdc (npm install -g @mermaid-js/mermaid-cli)
                        d2 (curl install script + copy to /usr/local/bin)
                        plantuml (download plantuml.jar + bash wrapper script)
```

---

### `bootstrap/arkade/`

> arkade is the tool installer used throughout Phases 18–19.
> It must be installed first before any `ark get` command works.

**Script phases covered:** Phase 18

```
arkade/
└── install-arkade.md   ← arkade v0.11.82 binary download from GitHub releases
                           ELF binary verification before installation
                           placement at /usr/local/bin/arkade
                           ark symlink creation
                           arkade version verification
                           how to use: ark get <tool>
```

---

### `bootstrap/components/`

> This is the **master index** of the entire `bootstrap/` section.
> It does not contain tool runbooks itself — it is the navigation page.

```
components/
└── index.md   ← High-level overview of all bootstrap sub-sections.
                  Explains the install-tools-all.sh script.
                  Links to all 18 folders above.
                  Explains the install order / dependency chain.
```

**Recommended install order (dependency chain):**

```
1. system-foundation/     ← apt base, build tools, shells
2. language-runtimes/     ← Python, Node, Go, Rust, Java (needed by later tools)
3. arkade/                ← install arkade first (used in phases 18-19)
4. container-runtime/     ← Docker, Podman
5. kubernetes/            ← k8s tools (depend on container runtime)
6. iac/                   ← Terraform, Ansible, Vault (depend on Python/Go)
7. security-tools/        ← scanners, SAST (depend on Go, Python)
8. observability-tools/   ← Prometheus, Loki, Grafana (standalone binaries)
9. cloud-clis/            ← AWS, GCP, Azure (depend on Python for some)
10. database-clis/        ← psql, mongosh (standalone)
11. devops-clis/          ← jq, yq, gh, lazygit (standalone)
12. shell-environment/    ← starship, zoxide (depends on Rust/cargo)
13. ai-ml-clis/           ← LLM tools (depends on Python/pip)
14. documentation-tools/  ← mkdocs, pandoc (depends on Python/npm/Ruby)
15. networking-tools/     ← diagnostic tools (apt-based, can be early)
16. storage-tools/        ← disk tools (apt-based)
17. debugging-profiling/  ← strace, gdb (apt-based)
```

---

## Phase-to-Folder Cross Reference

| Script Phase | Content | Bootstrap Folder |
|-------------|---------|-----------------|
| Phase 1 | apt update, upgrade, dist-upgrade | `system-foundation/apt-setup.md` |
| Phase 2 | Core system packages, shells | `system-foundation/core-packages.md`, `shells.md` |
| Phase 3 | Build essentials, compression | `system-foundation/build-tools.md`, `compression-tools.md` |
| Phase 4 | Python, Java, Ruby, Perl, Lua | `language-runtimes/python.md`, `java.md`, `ruby.md`, `other.md` |
| Phase 5 | Editors, TUI monitors | `system-foundation/editors.md`, `system-monitors.md` |
| Phase 6 | File management, search | `system-foundation/file-tools.md`, `search-tools.md` |
| Phase 7 | Networking tools | `networking-tools/` (8 files) |
| Phase 8 | Storage, filesystem | `storage-tools/` (5 files) |
| Phase 9 | Debugging, profiling | `debugging-profiling/` (4 files) |
| Phase 10 | OS security | `security-tools/os-hardening.md`, `audit-tools.md`, `gpg-pass.md` |
| Phase 11 | DB clients (apt) | `database-clis/postgresql.md`, `mysql.md`, `sqlite.md`, `redis.md` |
| Phase 12 | Git, git-lfs, tig | `system-foundation/version-control.md` |
| Phase 13 | pip tools | split across `iac/`, `security-tools/`, `documentation-tools/`, `devops-clis/`, `ai-ml-clis/`, `database-clis/` |
| Phase 14 | Docker, Podman, Buildah | `container-runtime/docker.md`, `podman.md` |
| Phase 15 | Node.js v20.x | `language-runtimes/nodejs.md` |
| Phase 16 | Go 1.22 | `language-runtimes/go.md` |
| Phase 17 | Rust via rustup | `language-runtimes/rust.md` |
| Phase 18 | arkade install | `arkade/install-arkade.md` |
| Phase 19 | ark get (50+ tools) | split across `kubernetes/`, `iac/`, `security-tools/`, `devops-clis/`, `observability-tools/`, `cloud-clis/` |
| Phase 20 | krew + krew plugins | `kubernetes/krew-plugins.md` |
| Phase 21 | Go-based tools | `security-tools/sast.md`, `devops-clis/code-tools.md`, `security-tools/tls-certs.md` |
| Phase 22 | Rust/cargo tools | `shell-environment/modern-cli.md`, `shell-environment/starship.md`, `shell-environment/zoxide.md`, `devops-clis/benchmarking.md`, `devops-clis/git-tools.md` |
| Phase 23 | GitHub binary installs | split across `container-runtime/`, `kubernetes/`, `security-tools/`, `iac/`, `networking-tools/`, `devops-clis/`, `database-clis/`, `observability-tools/` |
| Phase 24 | Cloud CLIs | `cloud-clis/` (7 files) |
| Phase 25 | Observability stack | `observability-tools/` (8 files) |
| Phase 26 | Additional utilities | `shell-environment/`, `devops-clis/`, `networking-tools/tunnel-proxy.md` |
| Phase 27 | AI/ML CLIs | `ai-ml-clis/` (5 files) |
| Phase 28 | Documentation tools | `documentation-tools/` (5 files) |
| Phase 29 | Database CLIs (binary) | `database-clis/mongodb.md`, `etcd.md`, `nats.md`, `universal.md` |

---

## Stats

| Metric | Count |
|--------|-------|
| Total subfolders under `bootstrap/` | 18 |
| Total planned files | ~128 |
| Tools from script mapped | 350+ |
| Script phases covered | 31 |
| Already completed | `kubernetes/install-kubernetes-cluster/` (9 files) ✅ |

---

*This plan was generated by deep analysis of `install-tools-all.sh` (31 phases, Feb 2026) and the existing runbook tree structure.*
*Last updated: May 2026*
