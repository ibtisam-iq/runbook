# ⚠️ ARCHIVED REPOSITORY

> **This repository has been archived and is now read-only.**

---

## 📦 Migration Notice

All content from this repository has been **migrated to and integrated into**:

### 🥈 [SilverStack](https://github.com/ibtisam-iq/silver-stack)

**New location:** `silver-stack/infra-bootstrap/`

For the latest updates, improvements, and active development, please visit:
👉 **[github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack)**

---

## 🚀 What was infra-bootstrap?

**infra-bootstrap** was a Bash-driven infrastructure provisioning framework designed for rapidly setting up DevOps tooling and Kubernetes environments in disposable lab and cloud instances.

### Key Features

- ✅ **493 commits** of infrastructure automation expertise
- ✅ Modular bash scripts for tool installations (Docker, Kubernetes, Jenkins, etc.)
- ✅ Automated Kubernetes cluster setup (kubeadm, K3s, Kind)
- ✅ Service deployment automation (Jenkins, SonarQube, Nexus)
- ✅ Comprehensive MkDocs documentation

### What It Provided

#### Component Installations
- Docker Engine
- Kubernetes CLI (kubectl, helm)
- Terraform, Trivy, and other DevOps tools
- Full automation for consistent setup

#### Kubernetes Automation
- kubeadm cluster setup (control-plane + workers)
- K3s lightweight clusters
- Kind local development clusters

#### Service Deployments
- Jenkins CI/CD server
- SonarQube code quality platform
- Nexus artifact repository
- Jumpbox servers

---

## 🔄 Why Was This Archived?

This repository has been **consolidated into SilverStack** as part of a broader DevOps toolkit reorganization:

### Before (Scattered)
```
├── infra-bootstrap/       (This repo - provisioning)
├── SilverKube/            (K8s manifests)
├── SilverFix/             (Troubleshooting)
└── [Other tools...]
```

### After (Unified)
```
silver-stack/              (Unified DevOps toolkit)
├── infra-bootstrap/       (Provisioning - preserved here!)
├── kubernetes/            (K8s configs)
├── docker-compose/        (Container stacks)
├── troubleshooting/       (Case studies)
└── terraform/             (Infrastructure as Code)
```

**Result:** Better organization, single source of truth, easier maintenance.

---

## 📚 Documentation

The complete documentation site remains **active and maintained**:

### 🌐 [bootstrap.ibtisam-iq.com](https://bootstrap.ibtisam-iq.com)

All scripts, usage guides, and references are fully documented and accessible.

---

## 🔗 Quick Links

### New Repository
- **Main Repo:** [SilverStack](https://github.com/ibtisam-iq/silver-stack)
- **Direct Path:** [silver-stack/infra-bootstrap](https://github.com/ibtisam-iq/silver-stack/tree/main/infra-bootstrap)

### Documentation
- **Live Docs:** [bootstrap.ibtisam-iq.com](https://bootstrap.ibtisam-iq.com)
- **Knowledge Base:** [nectar.ibtisam-iq.com](https://nectar.ibtisam-iq.com)

### Related Projects
- 📋 [SilverOps](https://github.com/ibtisam-iq/silver-ops) - DevOps portfolio
- 🐛 [DebugBox](https://github.com/ibtisam-iq/debugbox) - Container debugging toolkit
- 📚 [Nectar](https://github.com/ibtisam-iq/nectar) - Engineering knowledge base

---

## 💻 Quick Start (From New Location)

### Install Docker
```bash
curl -sL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/infra-bootstrap/scripts/components/docker-setup.sh | sudo bash
```

### Setup Kubernetes Cluster

**Control Plane Node**
```bash
curl -sL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/infra-bootstrap/scripts/kubernetes/entrypoints/init-controlplane.sh | sudo bash
```

**Worker Node**
```bash
curl -sL https://raw.githubusercontent.com/ibtisam-iq/silver-stack/main/infra-bootstrap/scripts/kubernetes/entrypoints/init-worker-node.sh | sudo bash
```

**Full documentation:** [bootstrap.ibtisam-iq.com](https://bootstrap.ibtisam-iq.com)

---

## 🎯 For Historical Reference

This repository remains available in read-only mode for:

- Historical commit reference
- Previous issues and discussions
- Legacy documentation
- Attribution and project timeline

All **493 commits** of development history are preserved.

---

## 🙏 Thank You

Thank you to everyone who used, contributed to, or provided feedback on this project!

The work continues in **[SilverStack](https://github.com/ibtisam-iq/silver-stack)** as part of a more comprehensive DevOps toolkit.

---

## 📬 Contact

**Muhammad Ibtisam** | Silver Medalist | DevOps Engineer

- 🌐 [ibtisam-iq.com](https://ibtisam-iq.com)
- 💼 [LinkedIn](https://linkedin.com/in/ibtisam-iq)

---

<div align="center">

**This repository is part of the Silver Series**

📋 [SilverOps](https://github.com/ibtisam-iq/silver-ops) |
🛠️ [SilverStack](https://github.com/ibtisam-iq/silver-stack) |
📚 [Nectar](https://github.com/ibtisam-iq/nectar) |
🐛 [DebugBox](https://github.com/ibtisam-iq/debugbox)

**Built with ❤️ by Muhammad Ibtisam**

</div>
