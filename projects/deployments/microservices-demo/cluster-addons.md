# Phase 3: Cluster Add-ons and Gateway API

## What This Is

This runbook documents how I installed the platform add-ons on the EKS cluster after the infrastructure was provisioned in Phase 2. These are the foundational components that the application deployment (Phase 4) and observability stack (Phase 5) depend on. Every add-on here was installed from the bastion host via `helm` and `kubectl`.

This is Phase 3 of a 6-phase project.

| Phase | Title | What It Covers |
|-------|-------|----------------|
| 1 | [CI Pipeline and DevSecOps](ci.md) | GitHub Actions workflows, Trivy scanning, GHCR image and chart publish |
| 2 | [AWS Infrastructure](aws-infrastructure.md) | DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes |
| **3** | **Cluster Add-ons and Gateway API (this runbook)** | **ALB Controller, EBS CSI, Gateway API, ExternalDNS** |
| 4 | [GitOps with ArgoCD](gitops-argocd.md) | ArgoCD, Application manifest, Image Updater, CD repo structure, deployment manifests |
| 5 | [Observability Stack](observability.md) | kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes |
| 6 | [Autoscaling, Load Testing, and Final Verification](autoscaling.md) | Metrics Server, HPA, scaling validation, full cluster audit |

At the end of this phase, the cluster can provision ALBs via Gateway API, automatically create DNS records in Route 53, and provide persistent storage for stateful workloads.

### What I Did

```
Step 1  Installed AWS Load Balancer Controller (IRSA + Helm, Gateway API feature gates enabled)
Step 2  Installed EBS CSI Driver (IRSA + EKS add-on, created gp3 StorageClass)
Step 3  Installed Gateway API CRDs, created GatewayClass, LoadBalancerConfiguration, and Gateway
Step 4  Installed ExternalDNS (IRSA + Helm, configured for Gateway API route sources)
```

!!! warning "Metrics Server Omission"

    I forgot to install Metrics Server in this phase. It is required for HPA (Horizontal Pod Autoscaler) which I set up in Phase 6. I installed it then instead. In a clean run, it belongs here alongside the other add-ons.

---

## Add-on Overview

| # | Add-on | Why It Is Needed | Consumed By |
|---|--------|------------------|-------------|
| 1 | AWS Load Balancer Controller | Provisions and manages ALBs from Gateway/HTTPRoute resources. Without it, Gateway objects sit in `Pending` with no ALB created. | Gateway API (this phase), ArgoCD HTTPRoute (Phase 4), app HTTPRoute (Phase 4) |
| 2 | EBS CSI Driver + gp3 StorageClass | Provides dynamic persistent volume provisioning. EKS does not include a CSI driver by default. | Elasticsearch data nodes (Phase 5) need PVCs for index storage |
| 3 | Gateway API (CRDs + GatewayClass + Gateway) | Replaces Ingress with the newer Gateway API model. A single shared ALB serves all HTTPRoutes across namespaces. | Every HTTPRoute in the project: app frontend, ArgoCD UI, Grafana, Kibana |
| 4 | ExternalDNS | Watches Gateway API HTTPRoute resources and automatically creates DNS A records in Route 53. No manual DNS record creation needed. | All subdomains: `app.ibtisam.qzz.io`, `argocd.ibtisam.qzz.io`, `grafana.ibtisam.qzz.io`, `kibana.ibtisam.qzz.io` |

!!! abstract "Decision: Gateway API Instead of Ingress"

    I chose Gateway API because the Kubernetes project itself [recommends Gateway over Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) and states that the Ingress API has been frozen. Gateway API is the modern, actively developed replacement with a cleaner separation between infrastructure operators (who define the Gateway) and application developers (who define HTTPRoutes).

---

## AWS Load Balancer Controller

The ALB Controller watches for Gateway, HTTPRoute, and Ingress resources, then provisions and configures AWS Application Load Balancers to match. I installed it with Gateway API feature gates enabled (`ALBGatewayAPI=true`, `NLBGatewayAPI=true`).

!!! info "Runbook: AWS Load Balancer Controller"

    IRSA setup (OIDC provider, IAM policy, service account), Helm install, and verification steps.
    [runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-aws-load-balancer-controller/](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-aws-load-balancer-controller/)

The installation involved three stages: associating the OIDC provider with the cluster (for IRSA), creating the IAM policy and service account via `eksctl`, and installing the Helm chart.

```bash
# OIDC provider (required for IRSA)
eksctl utils associate-iam-oidc-provider \
  --region $REGION --cluster "$CLUSTER_NAME" --approve

# IAM policy + service account
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts --approve

# Helm install with Gateway API feature gates
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set controllerConfig.featureGates.NLBGatewayAPI=true \
  --set controllerConfig.featureGates.ALBGatewayAPI=true
```

Verification:

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
# NAME                            READY   UP-TO-DATE   AVAILABLE
# aws-load-balancer-controller    2/2     2            2
```

---

## EBS CSI Driver

EKS creates a `gp2` StorageClass by default using the legacy in-tree `kubernetes.io/aws-ebs` provisioner. The EBS CSI Driver provides the modern `ebs.csi.aws.com` provisioner, which is required for `gp3` volumes and supports features like volume expansion. I installed it now because the Elasticsearch data nodes in Phase 5 need persistent volumes for index storage.

!!! info "Runbook: EBS CSI Driver"

    IRSA setup, EKS add-on installation, service account annotation, and gp3 StorageClass creation.
    [runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/)

```bash
# IRSA for the CSI driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# Install as an EKS managed add-on
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts "OVERWRITE"
```

On KodeKloud, the `--service-account-role-arn` parameter does not work with `aws eks create-addon` due to SCP restrictions. I had to manually annotate the service account with the IRSA role ARN after the add-on was created:

```bash
ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)

kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN \
  --overwrite

kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

After the driver was active, I created a `gp3` StorageClass and set it as the cluster default:

```bash
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
```

!!! abstract "Decision: gp3 as Default StorageClass"

    EKS creates a `gp2` StorageClass by default, but `gp3` is cheaper and provides a better baseline: 3,000 IOPS and 125 MB/s throughput included at no extra cost. I created a `gp3` class with the `ebs.csi.aws.com` provisioner and set it as the cluster default so any PVC without an explicit class gets `gp3` automatically.

---

## Gateway API

I chose Gateway API instead of Ingress. The architecture is: one shared Gateway provisions a single ALB, and multiple HTTPRoutes (from different namespaces) attach to it. This means the entire project runs behind one ALB.

!!! info "Runbook: Gateway API on EKS"

    CRD installation, GatewayClass, LoadBalancerConfiguration (ACM cert, subnets, scheme), and Gateway creation.
    [runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-gateway-api/](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-gateway-api/)

Three resources were created:

**GatewayClass** (`amazon-alb-gateway-class`) tells the ALB Controller that it is the implementation for Gateway API resources.

**LoadBalancerConfiguration** specifies the ALB parameters: internet-facing scheme, public subnets, and the ACM certificate ARN from Phase 2 (`arn:aws:acm:us-east-1:767397778924:certificate/47da9369-...`) for HTTPS termination.

**Gateway** (`app-alb-gateway`) defines two listeners: HTTP on port 80 and HTTPS on port 443. Both accept HTTPRoutes from any namespace (`allowedRoutes.namespaces.from: All`). When this Gateway is created, the ALB Controller provisions the actual AWS ALB. The Gateway status took approximately 5 minutes to transition to `Programmed: True` while the ALB was being provisioned and health checks passed.

The manifests for these three resources live in the CD repo at [`addons/gateway-api/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/gateway-api).

---

## ExternalDNS

ExternalDNS watches Kubernetes resources (in this case, Gateway API HTTPRoutes) and automatically creates DNS A records in Route 53. Every HTTPRoute with a `hostname` field (like `app.ibtisam.qzz.io`) gets a DNS record pointing to the ALB's DNS name. No manual Route 53 record creation needed.

!!! info "Runbook: ExternalDNS on EKS"

    IRSA setup for Route 53 access, Helm install, and source configuration for Gateway API.
    [runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-external-dns/](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-external-dns/)

The key configuration was the `sources` list. By default, ExternalDNS only watches `service` and `ingress` resources. I patched it to also watch Gateway API route types:

```yaml
sources:
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
  - gateway-tcproute
  - gateway-udproute
```

This patch lives in the CD repo at [`addons/external-dns/`](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo/addons/external-dns).

After ExternalDNS was running, every HTTPRoute I created in later phases automatically got a DNS record. The Route 53 hosted zone populated itself:

![Route 53 records created by ExternalDNS](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/09_route53_records_externaldns_reconciliation.png?raw=true)

The ALB resource map showing the routing targets:

![ALB resource map with routing targets](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/12_aws_alb_resource_map_routing_targets.png?raw=true)

---

## Final State

At the end of Phase 3, the cluster had these add-ons operational:

```
kube-system namespace
  ├── aws-load-balancer-controller (2 replicas, Gateway API feature gates on)
  ├── ebs-csi-controller (2 replicas, IRSA-backed)
  └── coredns, kube-proxy (EKS defaults)

default namespace
  ├── GatewayClass: amazon-alb-gateway-class
  ├── LoadBalancerConfiguration: with ACM cert for *.ibtisam.qzz.io
  └── Gateway: app-alb-gateway (HTTP + HTTPS listeners, ALB provisioned)

external-dns namespace
  └── external-dns (watching gateway-httproute sources, Route 53 write access)

StorageClass
  └── gp3 (default, WaitForFirstConsumer, allowVolumeExpansion)
```

The cluster was ready to accept HTTPRoutes from any namespace and automatically provision DNS records for them.

---

## Terminal Sessions and Evidence

| # | Session | What It Covers | Link |
|---|---------|----------------|------|
| 1 | Cluster Add-ons Installation | OIDC setup, ALB Controller IRSA + Helm, EBS CSI IRSA + add-on + gp3 class, Gateway API CRDs + GatewayClass + Gateway, ExternalDNS IRSA + Helm | [`03_cluster_addons_installation.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/03_cluster_addons_installation.txt) |

| # | Screenshot | What It Shows | Link |
|---|------------|---------------|------|
| 1 | Route 53 Records | All DNS records auto-created by ExternalDNS from HTTPRoutes | [`09_route53_records_externaldns_reconciliation.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/09_route53_records_externaldns_reconciliation.png) |
| 2 | ALB Resource Map | ALB routing targets showing traffic flow to backend services | [`12_aws_alb_resource_map_routing_targets.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/12_aws_alb_resource_map_routing_targets.png) |

---

## Next Phase

[Phase 4: GitOps with ArgoCD](gitops-argocd.md) covers installing ArgoCD, creating the Application manifest, deploying the Online Boutique via the CD repo, and configuring ArgoCD Image Updater for continuous delivery.