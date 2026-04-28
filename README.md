# Runbooks

[![Docs](https://github.com/ibtisam-iq/runbook/actions/workflows/deploy.yml/badge.svg)](https://github.com/ibtisam-iq/runbook/actions/workflows/deploy.yml)
[![Site](https://img.shields.io/badge/Live-runbook.ibtisam--iq.com-01696f)](https://runbook.ibtisam-iq.com)

Operational runbooks for Kubernetes, bare-metal infrastructure, DevSecOps pipelines, and platform tooling — written after doing the actual work.

Each page documents something I ran on real infrastructure: the exact steps, the decision points, and the things that failed before I got it right. Reusable scripts and manifests referenced here live in [SilverStack](https://github.com/ibtisam-iq/silver-stack).

---

## How This Fits Into My Engineering System

```mermaid
flowchart LR
    A("❓ Encounter a concept\nI don't understand")
    --> B[("📚 Nectar\nnectar.ibtisam-iq.com")]
    --> C("🔧 Apply it on\nreal infrastructure")
    --> D[("📋 Runbook\nrunbook.ibtisam-iq.com")]
    --> E[("⚙️ SilverStack\n")]

    D --> F[("📖 Blog\nblog.ibtisam-iq.com")]

    style B fill:#1565C0,color:#fff,stroke:#1565C0
    style D fill:#37474F,color:#fff,stroke:#37474F
    style E fill:#2E7D32,color:#fff,stroke:#2E7D32
    style F fill:#E65100,color:#fff,stroke:#E65100
```

| Layer | What it contains | Where |
|---|---|---|
| **Nectar** | My personal engineering knowledge base | [nectar.ibtisam-iq.com](https://nectar.ibtisam-iq.com) |
| **Runbook** ← you are here | My documented steps from real infrastructure work — commands I ran, problems I hit, and how I solved them | [runbook.ibtisam-iq.com](https://runbook.ibtisam-iq.com) |
| **SilverStack** | My reusable infrastructure artifacts — Bash scripts, Kubernetes manifests, and pre-built Docker rootfs images; the Runbook links here whenever a command depends on a hosted artifact | [github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack) |
| **Blog** | My personal blog — distilled write-ups of what I built and what I learned | [blog.ibtisam-iq.com](https://blog.ibtisam-iq.com) |

---

[ibtisam-iq.com](https://ibtisam-iq.com) · [LinkedIn](https://linkedin.com/in/ibtisam-iq)
