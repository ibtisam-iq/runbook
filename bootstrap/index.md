# Bootstrap

Runbooks for installing and bootstrapping DevOps platform tools and cluster
components on any Linux server — EC2, bare-metal, VPS, or microVM.

---

## What This Section Covers

I document here the installation and initial configuration of any tool I
use across real projects and lab environments. Each runbook captures
the exact commands — whether from official upstream documentation, a dedicated
installer script, or a combination of both.

For tools I install repeatedly across disposable environments, I have scripted
the process. Two of the most frequently used:

```bash
# Install a Kubernetes cluster
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/kubernetes/entrypoints/init-controlplane.sh | sudo bash
```

```bash
# Install Docker
curl -fsSL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/scripts/installers/install-docker.sh | sudo bash
```

!!! info "Ever-evolving"
    As I work on new projects and encounter new tools, their installation
    runbooks are added here.
