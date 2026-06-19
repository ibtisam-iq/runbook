# Phase 2: AWS Infrastructure

## What This Is

This runbook documents how I provisioned the AWS infrastructure for the Online Boutique project: DNS hosted zone, TLS certificate, EKS cluster control plane, bastion host, and self-managed worker nodes. Everything runs on a [KodeKloud AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws) with SCP restrictions, not a personal AWS account.

This is Phase 2 of a 6-phase project.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| 1 | [CI Pipeline and DevSecOps](../ci.md) | GitHub Actions workflows, Trivy scanning, GHCR image and chart publish |
| **2** | **AWS Infrastructure (this runbook)** | **DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes (Terraform)** |
| 3 | Cluster Add-ons and Gateway API | ALB Controller, EBS CSI, Gateway API CRDs, GatewayClass, Gateway, ExternalDNS |
| 4 | GitOps with ArgoCD | ArgoCD, Application manifest, Image Updater, CD repo structure, deployment manifests |
| 5 | Observability Stack | kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes |
| 6 | Autoscaling and Load Testing | Metrics Server, HPA, load generation, scaling verification |

At the end of this phase, the EKS cluster is fully operational with worker nodes ready to accept workloads, DNS is delegated, and the ACM certificate is issued for TLS termination in later phases.

### What I Did

```
Step 1  Launched the SilverStack dev machine on iximiuz, configured AWS CLI
Step 2  Created a Route 53 public hosted zone for ibtisam.qzz.io
Step 3  Delegated nameservers at the domain registrar (digitalplat.org)
Step 4  Requested a wildcard ACM certificate (*.ibtisam.qzz.io), validated via DNS
Step 5  Cloned silver-stack repo, ran terraform init + apply for EKS
        (VPC, subnets, IGW, NAT, bastion host, EKS control plane)
Step 6  SSH'd into the bastion host from the dev machine
Step 7  Installed client tools on bastion (kubectl, helm, eksctl, aws cli)
Step 8  Configured AWS CLI on bastion, updated kubeconfig
Step 9  Added self-managed worker nodes via CloudFormation
Step 10 Verified: nodes joined, cluster fully operational
```

| Item | Value |
|------|-------|
| Domain | `ibtisam.qzz.io` |
| ACM certificate | `*.ibtisam.qzz.io` (wildcard) |
| Region | `us-east-1` |
| Terraform code | [ibtisam-iq/silver-stack](https://github.com/ibtisam-iq/silver-stack/tree/main/terraform/aws/eks-kodekloud) |
| Dev machine | [SilverStack on iximiuz](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) |
| AWS lab | [KodeKloud AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws) |

---

## Dev Machine

I used my [SilverStack dev machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) on the iximiuz platform as the workstation for this project. It comes pre-installed with all tools needed: `aws`, `terraform`, `kubectl`, `helm`, `eksctl`, `jq`, `ssh`, and tab completion configured for all of them. No local setup required.

![SilverStack Dev Machine](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/01_silverstack_dev_machine.png?raw=true)

I configured the AWS CLI with the KodeKloud playground credentials:

```bash
aws configure
# AWS Access Key ID: <from KodeKloud playground>
# AWS Secret Access Key: <from KodeKloud playground>
# Default region: us-east-1
# Default output format: json
```

---

## DNS Hosted Zone (Route 53)

I created a public hosted zone for `ibtisam.qzz.io` in Route 53. This is the foundation for all subdomains used in later phases: `app.ibtisam.qzz.io` (the boutique app), `argocd.ibtisam.qzz.io` (ArgoCD UI), `grafana.ibtisam.qzz.io`, `kibana.ibtisam.qzz.io`, etc.

!!! info "Runbook: Route 53 Hosted Zone"

    Step-by-step procedure for creating a public hosted zone, retrieving nameservers, and delegating from the registrar.
    [runbook.ibtisam-iq.com/cloud/aws/networking/route53/create-hosted-zone/](https://runbook.ibtisam-iq.com/cloud/aws/networking/route53/create-hosted-zone/)

```bash
DOMAIN="ibtisam.qzz.io"

aws route53 create-hosted-zone \
  --name "$DOMAIN" \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config Comment="Public hosted zone for ${DOMAIN}",PrivateZone=false
```

Route 53 assigned the hosted zone ID `Z0210061LY7BBUGRLOK6` and four nameservers. I acquired the `qzz.io` domain for free from [digitalplat.org](https://domain.digitalplat.org/) and updated its nameserver delegation to point `ibtisam.qzz.io` to these AWS nameservers.

!!! info "Runbook: Free Domain, SSL, and Nginx HTTPS"

    How to acquire a free domain, obtain a TLS certificate, and configure Nginx for HTTPS. Also covers another free domain provider I discovered and tested.
    [runbook.ibtisam-iq.com/networking/domain-tls-setup/free-domain-ssl-nginx/](https://runbook.ibtisam-iq.com/networking/domain-tls-setup/free-domain-ssl-nginx/)

Verified propagation via Google's public resolver:

```bash
dig NS "$DOMAIN" @8.8.8.8 +short
# ns-566.awsdns-06.net.
# ns-1701.awsdns-20.co.uk.
# ns-331.awsdns-41.com.
# ns-1359.awsdns-41.org.
```

All four nameservers resolved correctly. DNS delegation was active.

---

## TLS Certificate (ACM)

I requested a wildcard certificate for `*.ibtisam.qzz.io` via AWS Certificate Manager. This certificate is consumed later by the Gateway API ALB listener for HTTPS termination.

!!! info "Runbook: ACM Certificate with DNS Validation"

    Step-by-step procedure for requesting a public TLS certificate and validating it via DNS CNAME records.
    [runbook.ibtisam-iq.com/cloud/aws/networking/acm/certificate-dns-validation/](https://runbook.ibtisam-iq.com/cloud/aws/networking/acm/certificate-dns-validation/)

```bash
CERT_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "*.${DOMAIN}" \
  --validation-method DNS \
  --region us-east-1 \
  --query "CertificateArn" \
  --output text)
```

ACM returned the validation CNAME record. I injected it into Route 53:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/acm-validation.json
```

Then waited for ACM to validate and issue the certificate:

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region us-east-1

aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.{Status:Status,DomainName:DomainName}" \
  --output table
# +------------------+----------+
# | DomainName       | Status   |
# +------------------+----------+
# | ibtisam.qzz.io   | ISSUED   |
# +------------------+----------+
```

Certificate ARN: `arn:aws:acm:us-east-1:767397778924:certificate/47da9369-a997-4197-9f4b-60b426a112a3`

This ARN is referenced later in the Gateway API's `LoadBalancerConfiguration` for HTTPS listeners (Phase 3).

!!! abstract "Decision: Wildcard Certificate"

    I requested `*.ibtisam.qzz.io` instead of individual certificates per subdomain. A single wildcard cert covers all subdomains (app, argocd, grafana, kibana) and avoids requesting a new certificate every time a new subdomain is added.

**Terminal session:** [`01_dns_and_ssl_certificate_setup.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01_dns_and_ssl_certificate_setup.txt)

---

## EKS Cluster Provisioning (Terraform)

The upstream `microservices-demo` repo contains Terraform code for GCP. I did not use it. I cloned my own infrastructure repo, [silver-stack](https://github.com/ibtisam-iq/silver-stack), which contains reusable, tested Terraform configurations. The EKS code lives at [`terraform/aws/eks-kodekloud/`](https://github.com/ibtisam-iq/silver-stack/tree/main/terraform/aws/eks-kodekloud).

!!! info "Runbook: EKS on KodeKloud via Terraform"

    Detailed runbook covering SCP constraints, IAM roles, VPC, EKS cluster, bastion host, self-managed nodes, and all the errors hit along the way.
    [runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/)

!!! warning "KodeKloud SCP Restrictions"

    The KodeKloud AWS Playground enforces Service Control Policies that restrict what resources can be created. Key constraints: cannot use the `terraform-aws-modules/eks/aws` module (it creates resources blocked by SCP), IAM roles must be named exactly `eksClusterRole` and `eksNodeRole`, managed node groups are blocked (self-managed nodes via CloudFormation only). The runbook above documents every SCP constraint encountered.

### Terraform Init and Apply

```bash
git clone https://github.com/ibtisam-iq/silver-stack.git
cd silver-stack/terraform/aws/eks-kodekloud/

terraform init    # downloads VPC module, EC2 module, AWS provider
terraform apply   # creates VPC, subnets, IGW, NAT, bastion, EKS control plane
```

Terraform created:

| Resource | Details |
|----------|---------|
| VPC | 3 public subnets, 3 private subnets, IGW, NAT gateway |
| Bastion host | EC2 instance in public subnet, SSH key generated by Terraform |
| IAM roles | `eksClusterRole` (cluster), `eksNodeRole` (nodes) |
| Security groups | Bastion SG, EKS additional SG |
| EKS control plane | API server endpoint in private subnets |

The EKS control plane took approximately 10 minutes to provision. No worker nodes yet. The KodeKloud SCP blocks managed node groups, so self-managed nodes are added in a later step.

**Terminal session:** [`01a_cluster_provisioning_with_terraform.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01a_cluster_provisioning_with_terraform.txt)

**Terraform source:** [`silver-stack/terraform/aws/eks-kodekloud/`](https://github.com/ibtisam-iq/silver-stack/tree/main/terraform/aws/eks-kodekloud)

---

## Bastion Host Access and Tool Installation

Once Terraform completed, the control plane and bastion host were ready. I SSH'd into the bastion from the iximiuz dev machine using the private key Terraform generated:

```bash
ssh -i silver-stack-eks-bastion-key.pem ubuntu@<bastion-public-ip>
```

All remaining phases (cluster add-ons, ArgoCD, application deployment, observability, autoscaling) were performed from the bastion host. I installed the necessary client tools:

!!! info "Runbook: Kubernetes Client Tools"

    Installation steps for kubectl, helm, eksctl, aws cli, and other tools on a fresh Ubuntu instance.
    [runbook.ibtisam-iq.com/bootstrap/kubernetes/client-tools/](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/client-tools/)

After installing the tools, I configured the AWS CLI on the bastion using the same KodeKloud credentials used on the dev machine, then updated the kubeconfig:

```bash
aws configure
aws eks update-kubeconfig --name silver-stack-eks --region us-east-1
kubectl get nodes
# No nodes yet (control plane only)
```

---

## Self-Managed Worker Nodes

The KodeKloud SCP blocks EKS managed node groups. I added self-managed nodes via CloudFormation, following the procedure documented in the EKS runbook.

!!! info "Runbook: Self-Managed Nodes on KodeKloud EKS"

    The CloudFormation stack creation, `aws-auth` ConfigMap update, and node verification steps.
    [runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/#phase-5--self-managed-nodes-cloudformation](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/#phase-5--self-managed-nodes-cloudformation)

After the CloudFormation stack completed and the `aws-auth` ConfigMap was updated, the nodes joined the cluster:

```bash
kubectl get nodes
# NAME                          STATUS   ROLES    AGE   VERSION
# ip-10-0-1-xxx.ec2.internal    Ready    <none>   2m    v1.32.x
# ip-10-0-2-xxx.ec2.internal    Ready    <none>   2m    v1.32.x
```

The cluster was fully operational: control plane + worker nodes + bastion host access.

**Terminal session:** [`02_bastion_access_tool_installation_and_self_managed_nodes.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/02_bastion_access_tool_installation_and_self_managed_nodes.txt)

---

## Final State

At the end of Phase 2, the following AWS resources were provisioned and operational:

```
Route 53
  └── ibtisam.qzz.io (public hosted zone, delegated from registrar)

ACM
  └── *.ibtisam.qzz.io (wildcard cert, ISSUED, DNS-validated)

VPC
  ├── 3 public subnets (bastion, NAT, ALB)
  ├── 3 private subnets (EKS nodes)
  ├── Internet Gateway
  └── NAT Gateway

EKS Cluster (silver-stack-eks)
  ├── Control plane (API server)
  ├── 2 self-managed worker nodes (CloudFormation)
  └── Bastion host (SSH access from dev machine)
```

All subsequent phases operate from the bastion host via `kubectl` and `helm`.

---

## Terminal Sessions and Evidence

Every step in this phase was recorded. The terminal sessions capture the exact commands, outputs, and errors encountered.

| # | Session | What It Covers | Link |
|---|---------|----------------|------|
| 1 | DNS and SSL Certificate Setup | AWS CLI config, Route 53 hosted zone creation, nameserver verification, ACM certificate request, DNS validation, certificate issuance | [`01_dns_and_ssl_certificate_setup.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01_dns_and_ssl_certificate_setup.txt) |
| 2 | Cluster Provisioning with Terraform | silver-stack clone, terraform init, terraform apply, VPC/EKS/bastion creation output | [`01a_cluster_provisioning_with_terraform.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01a_cluster_provisioning_with_terraform.txt) |
| 3 | Bastion Access, Tool Installation, and Self-Managed Nodes | SSH into bastion, kubectl/helm/eksctl install, AWS CLI config, kubeconfig update, CloudFormation node group, node join verification | [`02_bastion_access_tool_installation_and_self_managed_nodes.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/02_bastion_access_tool_installation_and_self_managed_nodes.txt) |

---

## Next Phase

[Phase 3: Cluster Add-ons and Gateway API](../cluster-addons.md) covers installing the AWS Load Balancer Controller, EBS CSI Driver, Gateway API CRDs, GatewayClass, Gateway, and ExternalDNS.
