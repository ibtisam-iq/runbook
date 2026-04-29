# What Senior Engineers Actually Write Runbooks For

A runbook is written when a task is **repeated**, **high-stakes**, or **hard to remember from memory**. Here are the real categories:

## 1. Infrastructure Setup (your `servers/` and `kubernetes/`)
Things that need to be reproduced reliably on fresh machines:
- Setting up a Kubernetes cluster (kubeadm, k3s, kubeedge)
- Installing Docker / containerd on Ubuntu/RHEL
- Configuring SSH hardening, firewall rules (ufw/iptables)
- Setting up Nginx as a reverse proxy or load balancer
- Mounting persistent volumes, NFS shares

## 2. Platform Tooling Setup (your `services/`)
Deploying infrastructure components on top of Kubernetes or VMs:
- Installing Jenkins, SonarQube, Nexus, Grafana, Prometheus
- Deploying cert-manager + Let's Encrypt (exactly what cost you 12 hours)
- Setting up MetalLB, Ingress-NGINX, Gateway API
- Configuring external-dns, sealed-secrets, Vault

## 3. CI/CD Pipelines
Not the Jenkinsfile itself, but the *operational steps* around it:
- How to connect GitHub to Jenkins (webhook setup, credentials)
- How to configure SonarQube quality gates
- How to push Docker images to Nexus vs. ECR
- Pipeline failure playbooks — "if stage X fails, check Y"

## 4. Cloud Environment Setup (your missing section)
- Provisioning EC2 with correct security groups for Kubernetes
- Setting up IAM roles for EKS node groups
- Configuring Route53 records + ACM certificates
- EBS CSI driver installation on EKS

## 5. Debugging & Troubleshooting (the most valuable section)
This is what separates a good runbook from a great one. The 12-hour cert-manager problem you described? **That belongs here**, not in a blog post. Format:
```
Problem: cert-manager CertificateRequest stuck in Pending
Environment: bare-metal, kubeadm, Let's Encrypt HTTP-01
Root cause: ClusterIssuer referenced wrong ingress class
Fix: ...
```

## 6. Operational Procedures (day-2 ops)
- How to safely drain and cordon a node
- How to rotate TLS certificates manually
- How to restore from an etcd snapshot
- How to upgrade a Kubernetes cluster version

---

## The Rule for "When Do I Write a Runbook Entry?"

Ask yourself one question after finishing any task:

> *"If I had to do this again in 3 months on a fresh machine, would I remember how?"*

If **no** → write the runbook entry immediately while it's fresh. Takes 10 minutes. Saves hours later.

Your cert-manager story is the perfect example. You spent 12 hours solving it. A 15-minute runbook entry means the next time you hit the same issue — or someone else on a team does — it's solved in 2 minutes.
