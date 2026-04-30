title: Home

---

# Runbook

**Documented steps from real infrastructure work - bare-metal servers, Kubernetes clusters, self-hosted platforms, and DevSecOps pipelines.**

[![Docs](https://github.com/ibtisam-iq/runbook/actions/workflows/deploy.yml/badge.svg)](https://github.com/ibtisam-iq/runbook/actions/workflows/deploy.yml)

Every page here documents something that was actually run - the exact commands, the decision points, and the failures encountered before things worked. This is not a course, not a reference manual. It is what was learned by doing, written down immediately after the work was finished.

---

## Browse by Domain

<div class="grid cards" markdown>

- **[:material-package-down: Bootstrap](bootstrap/index.md)**
  Install any tool from scratch - Docker, Kubernetes, Helm, Terraform, Jenkins, and more. One file per tool: manual steps + a one-shot automation script.

- **[:material-linux: Linux](linux/index.md)**
  OS-level administration - server setup, users, storage, networking, firewall rules, hardening, and system-level troubleshooting.

- **[:material-docker: Containers](containers/index.md)**
  Dockerfile patterns, multi-stage builds, layer caching, container registries, and runtime configuration.

- **[:material-kubernetes: Kubernetes](kubernetes/index.md)**
  Cluster setup, workloads, networking, storage, security, autoscaling, GitOps, and debugging. The largest and most active domain.

- **[:material-network: Networking](networking/index.md)**
  DNS, TLS, load balancing, Nginx/HAProxy, ingress and gateway controllers, VPNs, and firewalls.

<!-- This section is intentionally not yet included in navigation.
- **[:material-database: Storage](storage/)**
  Block storage, object storage, databases, and backup/restore procedures.
-->

- **[:material-pipe: Delivery](delivery/index.md)**
  CI pipelines, CD deployments, artifact management, GitOps, and identifying how a project runs before containerizing it.

- **[:material-shield-lock: Security](security/index.md)**
  Secrets management, vulnerability scanning, RBAC, OS hardening, and certificate workflows.

- **[:material-chart-line: Observability](observability/index.md)**
  Metrics, logging, tracing, and alerting - knowing what is happening inside running systems.

- **[:material-cloud: Cloud](cloud/index.md)**
  AWS-focused: IAM, VPCs, EC2, EKS, and managed services. GCP and Azure sections grow over time.

- **[:material-terraform: IaC](iac/index.md)**
  Terraform workflows - provisioning, remote state management, and reusable modules.

- **[:material-server: Self-Hosted](self-hosted/index.md)**
  Services deployed and operated personally: Nexus, SonarQube, Jenkins, Nextcloud, and more. Every setup documented from scratch.

<!-- This section is intentionally not yet included in navigation.
- **[:material-alert-circle: Incident Response](incident-response/)**
  Step-by-step playbooks for known failure scenarios - not debugging notes, but structured response procedures.
-->
</div>

---

## The Engineering System

This runbook is one layer in a connected personal engineering system. Each layer has a distinct role.

| Layer | What it contains | Where |
|---|---|---|
| **Nectar** | Concepts, theory, and fundamentals - studied before anything is built | [nectar.ibtisam-iq.com](https://nectar.ibtisam-iq.com) |
| **Runbook** ← you are here | Documented steps from real infrastructure work - commands run, problems hit, and how they were solved | [runbook.ibtisam-iq.com](https://runbook.ibtisam-iq.com) |
| **SilverStack** | Reusable Bash scripts, Kubernetes manifests, and Docker artifacts - the Runbook links here whenever a command depends on a hosted script | [github.com/ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack) |
| **Blog** | Distilled write-ups of what was built and what was learned | [blog.ibtisam-iq.com](https://blog.ibtisam-iq.com) |

---

**Start anywhere that matches what you're working on.**

Built with ❤️ by [@ibtisam-iq](https://github.com/ibtisam-iq) · [ibtisam-iq.com](https://ibtisam-iq.com) · [LinkedIn](https://linkedin.com/in/ibtisam-iq)
