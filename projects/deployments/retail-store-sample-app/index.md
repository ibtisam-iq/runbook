# End-to-End Platform Engineering: eksctl, Helmfile Orchestration, and AWS Managed Services on Amazon EKS

## Overview

This is a complete operational record of deploying the **Retail Store Sample App** onto Amazon EKS cluster `ibtisam-iq-eks-cluster` (us-east-1, Kubernetes 1.34). It documents every infrastructure decision, command, and validation step taken — from IAM roles and CloudFormation node groups through Helmfile orchestration, EBS storage, ALB Ingress, AWS-managed databases, and observability.

---

## About the Application

The **Retail Store Sample App** is a deliberately polyglot microservices e-commerce
store, originally authored by the
[AWS Containers team](https://github.com/aws-containers/retail-store-sample-app)
and forked at
[ibtisam-iq/retail-store-sample-app](https://github.com/ibtisam-iq/retail-store-sample-app).

It models the kind of heterogeneous stack found in real-world platform engineering —
five independent services, five different runtimes, five different persistence backends.

Since this project marked my transition from monolithic 3-tier architectures to polyglot microservices, I conducted an in-depth analysis of the application's source code and inter-service communication. My detailed architectural breakdowns for each service can be found in the [repository's runbooks directory](https://github.com/ibtisam-iq/retail-store-sample-app/tree/main/runbooks).

| Service | Language | Role | Database |
|---|---|---|---|
| **UI** | Java | Store frontend — routes all user traffic | None (calls all services) |
| **Catalog** | Go | Product catalog REST API | MySQL / MariaDB |
| **Cart** | Java | Shopping cart state management | DynamoDB / In-memory |
| **Orders** | Java | Order processing and persistence | PostgreSQL + SQS (on EKS) |
| **Checkout** | Node.js | Checkout orchestration | Redis / ElastiCache |

---

## What I Built on Top

The upstream repository ships the application source code and base Helm charts.
Everything below is original work I authored on top of that foundation.

**Per-service `values-*.yaml` overrides**

Each service ships with a base `values.yaml` inside its own `chart/` directory.
I studied each one and authored additional override files on top — one per deployment
scenario — so the same chart can be deployed across different target environments
without touching the chart itself. Each service has its own dedicated runbook
documenting every override decision.

**Three Helmfile configurations**

Rather than running five separate `helm install` commands in the right order every
time, I authored three Helmfile configurations — one per deployment target — each
declaring all five releases with explicit dependency ordering via `needs:`:

| Helmfile | Target | Storage | Message Broker | UI Exposure |
|---|---|---|---|---|
| [`helmfile-baremetal-ephemeral.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-ephemeral.yaml) | Any Kubernetes cluster | Ephemeral (no PVC) | In-memory | NodePort |
| [`helmfile-baremetal-persistent.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-persistent.yaml) | Bare-metal with `local-path` | PVC | RabbitMQ | NodePort |
| [`helmfile-eks.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-eks.yaml) | AWS EKS | `gp3` EBS PVC | AWS SQS | ALB Ingress |

!!! tip "Any cluster, any Helmfile"
    The ephemeral and persistent Helmfiles are not bare-metal-exclusive. They can run
    on any Kubernetes cluster — kubeadm, EKS, GKE — wherever the referenced
    `values-*.yaml` assumptions hold. The EKS Helmfile is the one that requires
    AWS-specific infrastructure: EBS CSI driver, ALB Ingress Controller, DynamoDB,
    SQS, and ACM — which is exactly what this runbook provisions.

**This runbook**

The final Helmfile command for this deployment is one line:

```bash
helmfile -f helmfile/helmfile-eks.yaml apply
```

But that single command only works after an entire infrastructure stack has been
built correctly. This runbook is the record of everything that had to exist before
that command could succeed.

## Related Runbooks

| Topic | Link |
|---|---|
| kubeadm cluster bootstrap (SilverStack) | [Cluster Bootstrap Runbook](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-kubeadm/) |
| EKS provisioning on KodeKloud Playground | [EKS on KodeKloud Runbook](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-aws-playground/) |

---

## Getting Started

---

## Phases

The project deployment is documented across 6 phases. Each phase has its own runbook with step-by-step commands, configurations, and verification steps.

<div class="grid cards" markdown>

- **[:material-aws: Phase 0-3: AWS Infrastructure](aws-infrastructure.md)**
  Prerequisites, IAM Roles, EKS Control Plane, Self-Managed Nodes

- **[:material-puzzle: Phase 4-5: Cluster Add-ons & ACM](cluster-addons.md)**
  ALB Controller, EBS CSI Driver, ACM TLS Certificate

- **[:material-database: Phase 6: Application Resources](application-resources.md)**
  DynamoDB Table, SQS Queue, SNS Topic & Lambda

- **[:material-rocket: Phase 7: Microservices Deployment](microservices-deployment.md)**
  Deploying all 5 services using Helmfile

- **[:material-chart-line: Phase 8-9: Observability Stack](observability.md)**
  kube-prometheus-stack, CloudWatch Container Insights

- **[:material-check-all: Phase 10: End-to-End Validation](validation.md)**
  ALB validation, HTTPS testing, DNS resolution, Stack review

</div>

---

## Key Decisions

Architectural and engineering decisions made across the deployment phases to accommodate environment constraints and optimize the platform.

### Infrastructure and Lab Constraints

- **Simplified VPC Creation via eksctl.** Instead of explicitly defining a VPC and its private subnets in the cluster manifest, I leveraged `eksctl`'s automated provisioning. This kept the infrastructure code simple while still ensuring the EKS cluster was securely placed into private subnets. ([Phase 1-3](aws-infrastructure.md))
- **Dev Machine over Bastion for Administration.** Instead of installing `kubectl`, `helmfile`, and other DevOps tools onto a bastion host, I administered the cluster directly from my SilverStack Dev Machine which had the complete toolchain pre-installed. ([Phase 1-3](aws-infrastructure.md))
- **Bastion Host for Node Troubleshooting.** While cluster administration was done from the Dev Machine, a bastion host was still utilized to SSH into the self-managed worker nodes for troubleshooting. When nodes initially failed to join the cluster due to an incorrect authentication mode, SSH access via the bastion proved critical for identifying the issue before tearing down and recreating the node stack with the correct parameters. ([Phase 1-3](aws-infrastructure.md))
- **Authentication Mode: API_AND_CONFIG_MAP.** I explicitly set the authentication mode to `API_AND_CONFIG_MAP` (the modern 2023 standard using EKS Access Entries alongside the traditional aws-auth ConfigMap), bypassing legacy restrictions and ensuring robust access control. ([Phase 1-3](aws-infrastructure.md))
- **IAM Roles via Terraform, not eksctl.** The KodeKloud lab user lacks `iam:PassRole` permissions. Allowing `eksctl` to automatically create roles during cluster creation would fail. Roles were pre-provisioned via Terraform and explicitly passed to eksctl. ([Phase 1-3](aws-infrastructure.md))
- **Self-Managed Nodes over Managed Node Groups.** EKS Managed Node Groups also trigger the blocked `iam:PassRole` permission. To bypass this, worker nodes were deployed manually using an AWS CloudFormation template. ([Phase 1-3](aws-infrastructure.md))
- **Delayed OIDC Association.** OIDC was disabled in `cluster.yaml` (`withOIDC: false`) because it also triggers permission failures during cluster creation. It was associated manually via `eksctl utils` after the control plane was up. ([Phase 1-3](aws-infrastructure.md))

### Deployment Orchestration

- **Why Helmfile instead of ArgoCD?** Because this was my first deep-dive into microservices, I intentionally prioritized mastering deployment orchestration, multi-environment configurations, and release dependencies natively via Helmfile before abstracting the workflow behind a GitOps controller (which I subsequently implemented in my next project).
- **Layered `values*.yaml` Strategy.** Instead of generating a monolithic values file (`helm show values`) and manually mutating it, I kept the upstream charts pristine. I authored dedicated, decoupled `values-*.yaml` override files for each service. This allowed me to elegantly expand the Helmfile orchestration across three distinct target behaviors: bare-metal ephemeral, bare-metal persistent, and fully-managed EKS.
- **Single Runtime Override.** Because of the layered `values*.yaml` strategy, all infrastructure configurations were pre-defined. The only manual edit required during the entire deployment phase is injecting the dynamically generated ACM Certificate ARN into the UI service's ingress values file right before executing the grand `helmfile -f` command.
- **Helmfile for Dependency Management.** Instead of running five separate `helm install` commands, Helmfile was used to declare all five releases. Explicit dependency ordering (`needs:`) ensures databases are ready before microservices start. ([Phase 7](microservices-deployment.md))

### Cloud-Native Integrations

- **CloudWatch over ELK Stack.** While I utilized the ELK stack with Beats in my other microservices project, this deployment is heavily oriented towards native AWS EKS integrations. Choosing CloudWatch Container Insights via Fluent Bit perfectly aligns with the project's cloud-native focus and seamlessly centralizes logs within the AWS ecosystem. ([Phase 8-9](observability.md))
- **Offloading State to AWS Managed Services.** Rather than running databases inside the cluster, the EKS Helmfile configuration binds the microservices to DynamoDB (Cart) and SQS/SNS (Orders) via IAM Roles for Service Accounts (IRSA). ([Phase 6](application-resources.md))
- **Shared ALB via Ingress Group.** The UI, Prometheus, and Grafana all share a single Application Load Balancer using `alb.ingress.kubernetes.io/group.name: ecom-eks`. The ALB routes traffic based on the Host header, eliminating the cost of multiple load balancers. ([Phase 8-9](observability.md))
- **gp3 as Default StorageClass.** `gp2` was patched out and `gp3` was set as the default `StorageClass` for the EBS CSI driver, providing a cheaper and more performant storage baseline for the stateful databases (MySQL, PostgreSQL). ([Phase 4-5](cluster-addons.md))

---

## Screenshots

| # | Screenshot | Phase | Link |
|---|------------|-------|------|
| 01 | CloudFormation EKS Cluster Stack | 10 | [`01-cloudformation-eks-cluster-stack-create-complete.png`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/assets/01-cloudformation-eks-cluster-stack-create-complete.png) |
| 02 | EKS Cluster Resources with Self-Managed Nodes | 3 | [`02-eks-cluster-resources-self-managed-nodes.png`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/assets/02-eks-cluster-resources-self-managed-nodes.png) |
| 03 | ALB Resource Map and Target Groups | 10 | [`03-alb-resource-map-and-target-groups.png`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/assets/03-alb-resource-map-and-target-groups.png) |
| 04 | Retail Store Live over HTTPS | 10 | [`04-retail-store-live-over-https.png`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/assets/04-retail-store-live-over-https.png) |
| 05 | CloudWatch Container Insights Log Groups | 9 | [`05-cloudwatch-container-insights-log-groups.png`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/assets/05-cloudwatch-container-insights-log-groups.png) |

