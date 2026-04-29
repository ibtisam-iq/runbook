# Runbook

This site is a field-tested knowledge base built from real infrastructure work — bare-metal servers, production Kubernetes clusters, self-hosted platforms, and DevSecOps pipelines. Every page documents something that was actually run: the exact commands, the decisions made, and the failures encountered before things worked correctly.

This is not a course. It is not a reference manual. It is what was learned by doing, written down immediately after the work was finished.

---

## What This Site Contains

The runbook is organized into focused domains. Each domain owns a specific layer of the infrastructure stack, and nothing lives in two places at once.

| Domain | What it covers |
|---|---|
| [Bootstrap](bootstrap/) | Installing tools from scratch — Docker, Kubernetes, Helm, Terraform, Jenkins, and more. One file per tool: manual steps + a one-shot automation script. |
| [Linux](linux/) | OS-level administration — server setup, users, storage, networking, firewall rules, hardening, and system-level troubleshooting. |
| [Containers](containers/) | Image building, Dockerfile patterns, multi-stage builds, container registries, and runtime configuration. |
| [Kubernetes](kubernetes/) | Cluster setup, workloads, networking, storage, security, autoscaling, GitOps, and debugging. The largest and most active domain. |
| [Networking](networking/) | DNS, TLS, load balancing, Nginx/HAProxy, ingress and gateway controllers, VPNs, and firewalls — the layer between the internet and the application. |
| [Storage](storage/) | Block storage, object storage, databases, and backup/restore procedures. |
| [Delivery](delivery/) | CI pipelines, CD deployments, artifact management, GitOps workflows, and project runtime identification before containerization. |
| [Security](security/) | Secrets management, vulnerability scanning, RBAC, OS hardening, and certificate workflows. |
| [Observability](observability/) | Metrics, logging, tracing, and alerting — knowing what is happening inside running systems. |
| [Cloud](cloud/) | AWS-focused: IAM, VPCs, EC2, EKS, and managed services. GCP and Azure sections will grow over time. |
| [IaC](iac/) | Terraform workflows — provisioning, remote state, and reusable modules. |
| [Self-Hosted](self-hosted/) | Services deployed and operated personally: Nexus, SonarQube, Jenkins, Nextcloud, and more. Every setup documented from scratch. |
| [Incident Response](incident-response/) | Structured playbooks for known failure scenarios — not debugging notes, but step-by-step response procedures. |

---

## The Engineering System

This runbook is one part of a larger personal engineering system. Each layer has a distinct role, and they connect in one direction: learn → apply → document → publish.

```
Nectar          → where concepts are studied and understood
    ↓
Real infrastructure work
    ↓
Runbook ← you are here  → what was done, step by step
    ↓
SilverStack             → the reusable scripts and manifests referenced here
    ↓
Blog                    → distilled write-ups of what was built and learned
```

| Layer | Purpose | Link |
|---|---|---|
| **Nectar** | Personal engineering knowledge base — concepts, theory, and fundamentals | [nectar.ibtisam-iq.com](https://nectar.ibtisam-iq.com) |
| **Runbook** | Documented steps from real infrastructure work | [runbook.ibtisam-iq.com](https://runbook.ibtisam-iq.com) |
| **SilverStack** | Reusable Bash scripts, Kubernetes manifests, and Docker artifacts — the Runbook links here whenever a command depends on a hosted script | [github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack) |
| **Blog** | Public write-ups of projects, lessons, and engineering decisions | [blog.ibtisam-iq.com](https://blog.ibtisam-iq.com) |

---

## How Pages Are Written

Every page in this runbook was written after the work was done — not before. The tone is first-person and operational: what was run, what the output looked like, what failed, and how it was resolved. There are no hypothetical steps and no "you should" instructions. If a page exists here, the commands on it have been executed on real infrastructure.

When a tool is installed for the first time, a page gets created in `bootstrap/` before moving on. When a self-hosted service is set up, its documentation goes into `self-hosted/`. When a production incident is debugged and resolved, the resolution is captured in the relevant domain's `troubleshooting/` subfolder or in `incident-response/`. The runbook grows by doing — not by planning.

---

## About

Built by [Muhammad Ibtisam Iqbal](https://ibtisam-iq.com) — a DevOps and platform engineering professional working with Kubernetes, CI/CD pipelines, infrastructure automation, and self-hosted platform tooling.

[ibtisam-iq.com](https://ibtisam-iq.com) · [LinkedIn](https://linkedin.com/in/ibtisam-iq) · [GitHub](https://github.com/ibtisam-iq)
