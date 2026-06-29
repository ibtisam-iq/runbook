# Multi-Environment Orchestration: Deploying Polyglot Microservices from Bare-Metal to Amazon EKS [eksctl, Terraform, AWS CloudFormation, Helmfile, ALB Ingress Controller, ACM, EBS CSI Driver, DynamoDB, AWS SQS, AWS Lambda, AWS SNS, Fluent Bit, CloudWatch Container Insights]

## Overview

Although this application was originally built as a demo project by the [AWS Containers team](https://github.com/aws-containers/retail-store-sample-app) specifically for Amazon EKS, I set out to deploy it across **three entirely different target environments**: an ephemeral bare-metal cluster, a persistent bare-metal cluster, and finally, Amazon EKS.

It models a real-world heterogeneous stack: five independent services, five different runtimes, and five different persistence backends.

**The Approach (Decoupled Values):**

AWS provided the base Helm charts for the microservices. However, rather than manually editing their charts to accommodate my three target environments, I left the upstream charts completely untouched. Instead, I navigated into each service's `src/` directory and authored my own environment-specific `values-*.yaml` overrides.

**Bare-Metal First:**

Because this application is heavily AWS-oriented, deploying it to a bare-metal Kubernetes cluster required explicitly severing its cloud dependencies. Using the custom `values-*.yaml` overrides, I systematically ripped out AWS DynamoDB (Cart), AWS SQS/SNS (Orders), AWS ElastiCache (Checkout), and the ALB Ingress Controller (UI). I rewired the microservices to run entirely on local, containerized alternatives—such as a local DynamoDB container, RabbitMQ/in-memory messaging, local Redis, and standard NodePorts. This successfully proved the application's portability completely outside of the AWS ecosystem.

!!! info "Bare-Metal Infrastructure Provisioning"
    For the bare-metal environments, I utilized my own custom [SilverStack Dev Machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) to bypass all local setup. On top of this machine, I provisioned a complete multi-node `kubeadm` cluster. The automation and architecture of this cluster are fully documented in my [Cluster Bootstrap Runbook](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-kubeadm/).

**Helmfile Orchestration:**

While the bare-metal deployment was successful, it required executing five separate `helm install` commands in strict dependency order. To eliminate this manual toil, I engineered a Helmfile orchestration layer. This allowed me to deploy the entire stack—with databases provisioning before microservices—via a single command. 

For the bare-metal validations, I authored and applied the following two Helmfile targets:

```bash
# Bare-metal — ephemeral
helmfile -f helmfile/helmfile-baremetal-ephemeral.yaml apply

# Bare-metal — persistent
helmfile -f helmfile/helmfile-baremetal-persistent.yaml apply
```
*(Configurations: [`helmfile-baremetal-ephemeral.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-ephemeral.yaml) and [`helmfile-baremetal-persistent.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-persistent.yaml))*

**The Final Target (Amazon EKS):**

With the Helmfile orchestration successfully automating the deployments, I returned the application to its original intended target: Amazon EKS. Because deploying to EKS required complex, deep native AWS infrastructure provisioning (ALB, EBS CSI, DynamoDB, SQS, SNS, Lambda, and CloudWatch), the vast majority of this runbook is dedicated exclusively to documenting this final, production-grade deployment.

!!! info "EKS Infrastructure Provisioning (KodeKloud Sandbox)"
    Instead of using a personal, unrestricted AWS account, I provisioned this entire stack on the [KodeKloud AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws). Because this sandbox environment enforces strict Service Control Policies (SCPs) and IAM limitations, standard automated provisioning failed. I had to manually engineer around these restrictions to successfully build the EKS cluster. Every constraint I hit and how I resolved it is documented in my [EKS on KodeKloud via eksctl Runbook](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-eksctl/).

---

## Application Architecture

| Service | Language | Role | Database |
|---|---|---|---|
| **UI** | Java | Store frontend - routes all user traffic | None (calls all services) |
| **Catalog** | Go | Product catalog REST API | MySQL / MariaDB |
| **Cart** | Java | Shopping cart state management | DynamoDB / In-memory |
| **Orders** | Java | Order processing and persistence | PostgreSQL + SQS (on EKS) |
| **Checkout** | Node.js | Checkout orchestration | Redis / ElastiCache |

---

## Multi-Environment Configuration

### Three Helmfile Targets
Rather than running five separate `helm install` commands in the right order every time, I authored three Helmfile configurations - one per deployment target - each declaring all five releases with explicit dependency ordering via `needs:`:

| Helmfile | Target | Storage | Message Broker | UI Exposure |
|---|---|---|---|---|
| [`helmfile-baremetal-ephemeral.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-ephemeral.yaml) | Any Kubernetes cluster | Ephemeral (no PVC) | In-memory | NodePort |
| [`helmfile-baremetal-persistent.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-baremetal-persistent.yaml) | Bare-metal with `local-path` | PVC | RabbitMQ | NodePort |
| [`helmfile-eks.yaml`](https://github.com/ibtisam-iq/retail-store-sample-app/blob/main/helmfile/helmfile-eks.yaml) | AWS EKS | `gp3` EBS PVC | AWS SQS | ALB Ingress |

### Layered `values-*.yaml` Override Matrix
This matrix demonstrates how environment-specific overrides were injected across the three deployment targets while leaving the base `values.yaml` untouched.

| Service | Bare-Metal Ephemeral | Bare-Metal Persistent | Amazon EKS |
|---|---|---|---|
| **Catalog** | `values-mysql-ephemeral.yaml` | `values-mysql-pvc-baremetal.yaml` | `values-mysql-pvc-eks.yaml` |
| **Cart** | `values-dynamodb-local.yaml` | `values-dynamodb-local.yaml` | `values-dynamodb-aws.yaml` |
| **Orders** | `values-02-postgresql-ephemeral-msg-in-memory.yaml` | `values-03-postgresql-rabbitmq-pvc-baremetal.yaml` | `values-06-postgresql-pvc-eks-sqs.yaml` |
| **Checkout** | `values-redis-local.yaml` | `values-redis-local.yaml` | `values-redis-local.yaml` |
| **UI** | `values-nodeport.yaml` | `values-nodeport.yaml` | `values-alb-ingress.yaml` |

!!! note "Shared Base Configurations"
    Base `values.yaml` and inter-service endpoint routing (`values-endpoints.yaml`) are universally shared across all platforms.

---

## Amazon EKS Architectural Highlights

The rest of this document exclusively covers the third platform: Amazon EKS. The following highlights define its deep cloud-native integration:

1. **Native AWS Observability:** Because this is an AWS-centric deployment, I explicitly abandoned the ELK stack and Prometheus. I deployed Fluent Bit to stream logs natively into CloudWatch Container Insights, demonstrating deep alignment with the AWS managed ecosystem.
2. **Event-Driven Order Notifications:** I engineered a serverless, event-driven pipeline where AWS SQS queues capture order events. These events immediately trigger an **AWS Lambda** function that executes custom business logic to publish order confirmations to an **AWS SNS** topic for direct email delivery.
3. **Bypassing Service Control Policies (SCPs):** As the lab environment blocked `iam:PassRole` required by EKS Managed Node Groups, I bypassed this restriction by engineering self-managed worker nodes via custom AWS CloudFormation templates.

## EKS Deployment Phases

As established in the **Final Target** overview, running a single `helmfile apply` against Amazon EKS is only possible *after* an extensive amount of native AWS infrastructure has been provisioned and configured.

To document this deep cloud integration, I have broken the entire EKS rollout down into a rigorous **10-Phase deployment lifecycle**. The runbook pages below detail every step from the first IAM role creation to the final end-to-end TLS validation.

!!! note "Abstracted Bare-Metal Deployments"
    Because the bare-metal environments required zero external cloud infrastructure and were entirely abstracted by the simple execution of their respective Helmfiles, they do not require step-by-step documentation. The 10 phases below cover **only** the complex Amazon EKS deployment.

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
- **Single Runtime Override.** Because of the layered `values*.yaml` strategy, all infrastructure configurations were pre-defined. The only manual edit required during the entire deployment phase is injecting the dynamically generated ACM Certificate ARN into the UI service's ingress values file right before executing the grand `helmfile -f` command.

### Cloud-Native Integrations

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

