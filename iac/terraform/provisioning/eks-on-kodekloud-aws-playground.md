# EKS Cluster Setup on KodeKloud AWS Playground

## Overview

This runbook documents a **verified, end-to-end workaround** for provisioning a fully functional EKS cluster with self-managed worker nodes on a **KodeKloud AWS playground lab account** — an environment where an AWS Organizations Service Control Policy (SCP) silently blocks several standard EKS operations.

I wrote this after hitting every one of these restrictions in production lab sessions and working through each failure systematically. Nothing here is theoretical — every command, error message, and workaround has been confirmed on a live KodeKloud playground.

**Target environment:** KodeKloud AWS playground labs only. Personal AWS accounts are not subject to these restrictions.

**End state after following this runbook:**

- Two SCP-compliant IAM roles (`eksClusterRole`, `eksNodeRole`) provisioned via Terraform
- EKS control plane running and `Active`
- Self-managed AL2023 worker nodes joined to the cluster
- `kubectl get nodes` returns nodes in `Ready` state

**Hard constraints — not negotiable on this platform:**

- `iam:PassRole` is allowed **only** for roles named `eksClusterRole` or `eksNodeRole` — any other name returns `implicitDeny`
- `eks:CreateNodegroup` is **blocked unconditionally** — managed node groups are impossible regardless of tool

---

## Prerequisites

Confirm the following before starting:

| Requirement | Notes |
| --- | --- |
| Active KodeKloud lab session | Credentials expire with the session — do not start if less than 45 min remain |
| AWS CLI configured | Run `aws sts get-caller-identity` to confirm |
| `terraform` installed | `terraform version` — any recent version works |
| `eksctl` installed | Required only for Option B cluster creation |
| `kubectl` installed | Required from Step 5 onward |

---

## End-to-End Phase Map

The full workflow has three phases. Understand the map before starting — the Track choice in Phase 3 is a one-time decision that affects every subsequent step.

| Phase | What it does | Sections below |
| --- | --- | --- |
| **Phase 1 — IAM Roles** | Create the two SCP-whitelisted IAM roles via Terraform | [Phase 1](#phase-1--create-scp-compliant-iam-roles-terraform-required) |
| **Phase 2 — EKS Cluster** | Create the control plane (Console or eksctl) | [Create the EKS Cluster](#create-the-eks-cluster) |
| **Phase 3 — Worker Nodes** | Provision self-managed AL2023 nodes via CloudFormation and join them | [Phase 3](#phase-3--self-managed-worker-nodes) Steps 1–6 |

**Post-cluster add-ons** (optional, after nodes are `Ready`): [VPC CNI](#install-vpc-cni) · [EBS CSI Driver](#install-eks-ebs-csi-driver)

> If something goes wrong, jump directly to [Troubleshooting](#troubleshooting). The most common failure — nodes stuck `Unauthorized` — is covered there with root cause and fix.

---

## Node Group Decision Matrix

| Method | Supported | Notes |
| --- | --- | --- |
| Managed node group (Console) | ❌ | `eks:CreateNodegroup` blocked by SCP |
| Managed node group (eksctl) | ❌ | Same SCP block via CloudFormation |
| Managed node group (AWS CLI) | ❌ | Same SCP block |
| Managed node group (Terraform `aws_eks_node_group`) | ❌ | Same SCP block |
| **Self-managed nodes (CloudFormation, AL2 template)** | ⚠️ | Only where an AL2 AMI still exists; AL2 is EOL (Track A) |
| **Self-managed nodes (CloudFormation, AL2023 template)** | ✅ | Current template — recommended (Track B) |
| **Self-managed nodes via retail-store Terraform module** | ✅ | Supported — pre-authorized execution context |

---

## Authentication Mode Quick Reference

| `authenticationMode` | aws-auth ConfigMap | Access entries | Node join path |
| --- | --- | --- | --- |
| `CONFIG_MAP` | ✅ honored | ❌ unavailable | Path 2 (aws-auth) |
| `API_AND_CONFIG_MAP` | ✅ honored | ✅ available | Either path |
| `API` (current default) | ❌ **ignored** | ✅ required | Path 1 (access entry) |

---

## Problem

Creating an EKS cluster or node group via the AWS Console, eksctl, or AWS CLI throws one or more of the following errors:

```
User: arn:aws:iam::<account-id>:user/kk_labs_user_XXXXXX is not authorized to
perform: iam:PassRole on resource: arn:aws:iam::<account-id>:role/AmazonEKSClusterRole
because no identity-based policy allows the iam:PassRole action
```

```
User: arn:aws:iam::<account-id>:user/kk_labs_user_XXXXXX is not authorized to
perform: eks:CreateNodegroup on resource: arn:aws:eks:us-east-1:<account-id>:cluster/<name>
because no identity-based policy allows the eks:CreateNodegroup action
```

---

## Root Cause

KodeKloud lab accounts operate under an **AWS Organizations Service Control Policy (SCP)** that restricts specific IAM and EKS actions for the lab user. The SCP blocks:

- `iam:PassRole` — unless the role being passed has a **whitelisted name**
- `eks:CreateNodegroup` — **blocked unconditionally across all methods**

Confirm this by running the IAM policy simulator:

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID
```

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/<lab-username> \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::$ACCOUNT_ID:role/AmazonEKSClusterRole
```

If `EvalDecision` returns `implicitDeny` and `AllowedByOrganizations` returns `False`, the SCP is the blocker. No workaround exists at the account level — the restriction is enforced at the AWS Organization level above the account.

---

## Whitelisted IAM Role Names

KodeKloud lab SCPs whitelist `iam:PassRole` only for roles with specific names. For EKS, the two confirmed whitelisted names are:

| Role | Exact Name | Purpose |
| --- | --- | --- |
| Cluster Role | `eksClusterRole` | EKS control plane |
| Node Role | `eksNodeRole` | Self-managed worker nodes |

Any other role name (e.g., `AmazonEKSClusterRole`, `my-eks-role`, or eksctl auto-generated names) results in `implicitDeny`.

---

## Blocked Operations — Summary

| Action | Console | eksctl | AWS CLI | Terraform |
| --- | --- | --- | --- | --- |
| `iam:PassRole` (wrong role name) | ❌ | ❌ | ❌ | ❌ |
| `iam:PassRole` (eksClusterRole / eksNodeRole) | ✅ | ✅ | ✅ | ✅ |
| `eks:CreateCluster` | ✅ | ✅ | ✅ | ✅ |
| `eks:CreateNodegroup` (managed) | ❌ | ❌ | ❌ | ❌ |
| Self-managed nodes via CloudFormation | ✅ | N/A | ✅ | ✅ |

!!! note ""

    - `eks:CreateNodegroup` is blocked unconditionally by the SCP regardless of the tool used.
    - Console, eksctl (CLI flags), eksctl (YAML/CloudFormation), AWS CLI, and Terraform all fail with `AccessDeniedException`.
    - **Workaround:** Use self-managed worker nodes provisioned via the AWS EKS CloudFormation node template and joined via either an EKS **access entry** or the legacy **aws-auth** ConfigMap, depending on the cluster's authentication mode (see [Step 5](#step-5--join-nodes-to-the-cluster)).


---

## Phase 1 — Create SCP-Compliant IAM Roles (Terraform Required)

The SCP blocks `iam:PassRole` for any role that is not `eksClusterRole` or `eksNodeRole`. The AWS Console and CLI cannot create these roles correctly under the restriction without Terraform handling the naming explicitly. Run this phase once at the start of every lab session.

### Step 1 — Write the Terraform Configuration

Create a working directory and write the following `main.tf`:

```bash
mkdir ~/eks-iam-setup && cd ~/eks-iam-setup
```

```hcl
# main.tf
provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Optional: enables AWS Systems Manager Session Manager access to nodes,
# avoiding SSH key management on ephemeral playground instances.
resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

### Step 2 — Apply

```bash
terraform init
terraform apply -auto-approve
```

Both `eksClusterRole` and `eksNodeRole` are now present in IAM with the correct policies attached.

!!! note ""

    If `eksClusterRole` already exists from a previous session, the apply will throw a `409 EntityAlreadyExists` error for that role. Import it instead:

    ```bash
    terraform import aws_iam_role.eks_cluster_role eksClusterRole
    terraform apply -auto-approve
    ```

---

## Phase 2 — Create the EKS Cluster

### Option A — AWS Console

1. Go to **EKS → Create Cluster**
2. Select `eksClusterRole` as the cluster service role
3. Complete the cluster creation wizard — the `iam:PassRole` error will not appear
4. Wait for the cluster status to become **Active**

!!! important "Set authentication mode during creation"

    Newer EKS clusters default to `API` authentication mode, in which the legacy `aws-auth` ConfigMap is **silently ignored**. If the Console offers an authentication-mode choice, select **`EKS API and ConfigMap`** — this keeps both node-join paths available and avoids the most common `Unauthorized` failure in Step 5.

!!! note "Managed node group creation via Console is blocked"

    `eks:CreateNodegroup` is denied by the SCP. Do not attempt to add a managed node group through the Console. Use the self-managed node provisioning steps in Phase 3 instead.


### Option B — eksctl with YAML Config (Cluster Only)

Create `cluster.yaml`:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ibtisam-iq-eks-cluster
  region: us-east-1

iam:
  serviceRoleARN: arn:aws:iam::<account-id>:role/eksClusterRole
  withOIDC: false  # ← MUST be false; enable OIDC separately after cluster is up

# Make both join paths available (access entries + aws-auth ConfigMap).
# Omit or set to "API" and access entries become mandatory for joining nodes.
accessConfig:
  authenticationMode: API_AND_CONFIG_MAP

# Explicitly declare addons
addons:
  - name: vpc-cni
    version: latest
  - name: kube-proxy
    version: latest
  - name: coredns
    version: latest

managedNodeGroups: []

autoModeConfig:
  enabled: false
```

Run:

```bash
# Step 1: Create cluster (no OIDC, no role auto-attachment)
eksctl create cluster -f cluster.yaml
```

```bash
# Step 2: Associate OIDC provider manually (no iam:PassRole triggered here)
eksctl utils associate-iam-oidc-provider \
  --cluster <cluster-name> \
  --region <region> \
  --approve
```

!!! warning "Critical rules for this config — I confirmed each the hard way"

    - Run `aws sts get-caller-identity --query Account --output text` for the account ID and `aws configure get region` for the region — do not hardcode assumptions.
    - **`withOIDC: false` is mandatory during create.** Setting `withOIDC: true` triggers `UpdateAddon` on `vpc-cni` with `iam:PassRole` mid-operation. The SCP denies it and the entire cluster creation fails with no partial rollback. Always associate OIDC as a separate step after the cluster is `Active`.
    - **Do not add `managedNodeGroups` entries.** eksctl creates managed node groups via `eks:CreateNodegroup` — blocked by the SCP. Keep the list empty and attach workers in Phase 3.
    - **Do not enable `autoModeConfig`.** It also triggers `CreateNodegroup` and fails the whole operation.

---

## Managed Node Groups — Blocked, No Workaround

`eks:CreateNodegroup` is denied by the Organizations SCP unconditionally. I verified this across every available method:

- AWS Console → `eks:CreateNodegroup` → `AccessDeniedException`
- `eksctl create nodegroup` → CloudFormation rollback → `AccessDeniedException`
- `aws eks create-nodegroup` → `AccessDeniedException`
- `terraform apply` with `aws_eks_node_group` → `AccessDeniedException`
- IAM policy simulator → `EvalDecision: implicitDeny`, `AllowedByOrganizations: False`

```bash
# Verification command
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/<lab-username> \
  --action-names eks:CreateNodegroup \
  --resource-arns arn:aws:eks:us-east-1::$ACCOUNT_ID:cluster/<cluster-name>
```

**There is no workaround for managed node groups.** Use self-managed worker nodes as described in Phase 3.

---

## Phase 3 — Self-Managed Worker Nodes

Since `eks:CreateNodegroup` is blocked, worker nodes are attached to the cluster using the **AWS-provided EKS node CloudFormation template**. This creates an Auto Scaling Group of EC2 instances that bootstrap themselves and join the cluster.

> **Choose a track before continuing.**
>
> AWS ships two generations of the self-managed node template — they are **not** interchangeable. For any cluster created today, use **Track B (AL2023)**. Track A (AL2, EOL since 2025-06-30) is documented for historical reference only — its kubelet 1.24 will not register against a current EKS control plane.

### Step 1 — Create an EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name eks-nodes-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/eks-nodes-key.pem

chmod 400 ~/.ssh/eks-nodes-key.pem
```

### Step 2 — Fetch Required IDs

Set the cluster name once and reuse it for every lookup in this phase:

```bash
CLUSTER_NAME=<cluster-name>
```

Fetch the VPC ID from the cluster:

```bash
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo $VPC_ID
```

Fetch the cluster security group ID:

!!! note "Which security group to use"

    When a cluster is created via the AWS Console or eksctl, EKS automatically creates one security group named `eks-cluster-sg-<cluster-name>-<uniqueID>`. This is the **cluster security group** and it already contains the required rules:

    - **Inbound:** All traffic from itself (self-referencing rule) — allows node-to-node and node-to-control-plane communication
    - **Outbound:** All traffic to `0.0.0.0/0`

    No additional ports need to be opened manually.


```bash
CLUSTER_SG=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

echo $CLUSTER_SG
```

Fetch subnet IDs from the VPC:

!!! note "Why subnet tags matter for Load Balancers"

    The AWS Load Balancer Controller discovers subnets by looking for specific tags:

    - `kubernetes.io/role/internal-elb=1` — for **internal** load balancers (ALB/NLB in private subnets)
    - `kubernetes.io/role/elb=1` — for **internet-facing** load balancers (ALB/NLB in public subnets)


**Option A — Tag subnets first, then fetch (recommended for full LB support)**

List all subnets in the VPC to identify their IDs and Availability Zones:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
  --output table
```

Tag private subnets for internal load balancers:

```bash
aws ec2 create-tags \
  --resources subnet-aaa subnet-bbb subnet-ccc \
  --tags Key=kubernetes.io/role/internal-elb,Value=1
```

Tag public subnets for internet-facing load balancers:

```bash
aws ec2 create-tags \
  --resources subnet-xxx subnet-yyy subnet-zzz \
  --tags Key=kubernetes.io/role/elb,Value=1
```

Then fetch by tag:

```bash
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

echo $SUBNET_IDS
```

**Option B — Fetch all subnets directly (simpler, tag later)**

```bash
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

echo $SUBNET_IDS
```

!!! warning ""

    Without the `kubernetes.io/role/internal-elb` and `kubernetes.io/role/elb` tags, the AWS Load Balancer Controller cannot discover subnets and will fail to provision ALB/NLB. If using Option B now, apply the tags from Option A before deploying any Ingress or Service of type LoadBalancer.


### Step 3 — Choose a Node Template Track

| | **Track A — Amazon Linux 2** | **Track B — Amazon Linux 2023** |
| --- | --- | --- |
| Template | `2022-12-23/amazon-eks-nodegroup.yaml` | `2025-11-26/amazon-eks-nodegroup.yaml` |
| Bootstrap | `/etc/eks/bootstrap.sh` (auto-discovers cluster metadata) | `nodeadm` (metadata must be passed explicitly) |
| Kubelet | ships 1.24.17 | tracks AMI / cluster version |
| Works for K8s | only versions that still publish an AL2 AMI | current versions (1.30+ default to AL2023) |
| Extra params needed | none | `ApiServerEndpoint`, `CertificateAuthorityData`, `ServiceCidr`, `AuthenticationMode`, `NodeImageIdSSMParam` |
| Status | known-working on KodeKloud playground | current AWS default — use this |

!!! danger "Amazon Linux 2 is end-of-life"

    Amazon Linux 2 reached end of support on **2025-06-30**, and the `2022-12-23` template's kubelet 1.24 is long past EKS support. A current control plane will not run 1.24, so AL2/1.24 nodes from Track A will mismatch and fail to register. **Track A is only viable if the cluster was deliberately created at an older Kubernetes version that still publishes an AL2 AMI, and accepting EOL nodes on a throwaway playground.** For anything else, use Track B.

---

#### Track A — Amazon Linux 2 (legacy)

##### Step 3A — Create the Parameters File

!!! note ""

    Pass parameters via a JSON file. Passing the subnet list inline causes the AWS CLI to misparse the value.

```bash
cat > /tmp/cf-params.json << EOF
[
  {"ParameterKey": "ClusterName",                         "ParameterValue": "$CLUSTER_NAME"},
  {"ParameterKey": "ClusterControlPlaneSecurityGroup",    "ParameterValue": "$CLUSTER_SG"},
  {"ParameterKey": "NodeGroupName",                       "ParameterValue": "${CLUSTER_NAME}-nodes"},
  {"ParameterKey": "NodeInstanceType",                    "ParameterValue": "t3.medium"},
  {"ParameterKey": "NodeVolumeSize",                      "ParameterValue": "20"},
  {"ParameterKey": "VpcId",                               "ParameterValue": "$VPC_ID"},
  {"ParameterKey": "Subnets",                             "ParameterValue": "$SUBNET_IDS"},
  {"ParameterKey": "KeyName",                             "ParameterValue": "eks-nodes-key"},
  {"ParameterKey": "NodeAutoScalingGroupMinSize",         "ParameterValue": "1"},
  {"ParameterKey": "NodeAutoScalingGroupMaxSize",         "ParameterValue": "3"},
  {"ParameterKey": "NodeAutoScalingGroupDesiredCapacity", "ParameterValue": "3"}
]
EOF
```

The unquoted `EOF` expands the variables set in Step 2 (`CLUSTER_NAME`, `CLUSTER_SG`, `VPC_ID`, `SUBNET_IDS`). Run `cat /tmp/cf-params.json` afterward to confirm none are blank.

##### Step 4A — Launch the Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2022-12-23/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM
```

Skip to [Monitor the Stack](#monitor-the-stack).

---

#### Track B — Amazon Linux 2023 (current)

AL2023 nodes use `nodeadm` instead of `bootstrap.sh` and no longer auto-discover cluster metadata, so the template requires several values that Track A did not. Collect them first.

##### Step 3B.0 — Confirm the Template's Parameter Set

The accepted parameters differ between template versions, and CloudFormation rejects the whole stack if it receives even one key it doesn't define (`ValidationError: Parameters: [X] do not exist in the template`). Print the authoritative list straight from the template before building the params file:

```bash
aws cloudformation get-template-summary \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --query "Parameters[].ParameterKey" --output text | tr '\t' '\n' | sort
```

Build the `cf-params.json` using only keys that appear in this output. The set below is correct for the `2025-11-26` template at time of writing, but AWS revises these templates — the command above is always the source of truth.

##### Step 3B.1 — Fetch the Extra Cluster Metadata

```bash
# CLUSTER_NAME was set in Step 2; reusing it here.
API_SERVER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.endpoint" --output text)

CA_DATA=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.certificateAuthority.data" --output text)

SERVICE_CIDR=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.kubernetesNetworkConfig.serviceIpv4Cidr" --output text)

AUTH_MODE=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.accessConfig.authenticationMode" --output text)

# The node template's AuthenticationMode parameter uses human-readable display
# strings, NOT the API enum that describe-cluster returns. Translate it:
#   API               -> "EKS API"
#   API_AND_CONFIG_MAP -> "EKS API and ConfigMap"
#   CONFIG_MAP        -> "ConfigMap"
case "$AUTH_MODE" in
  API)                AUTH_MODE_PARAM="EKS API" ;;
  API_AND_CONFIG_MAP) AUTH_MODE_PARAM="EKS API and ConfigMap" ;;
  CONFIG_MAP)         AUTH_MODE_PARAM="ConfigMap" ;;
  *) echo "Unexpected auth mode: $AUTH_MODE" >&2 ;;
esac

K8S_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.version" --output text)

echo "cluster=$CLUSTER_NAME"
echo "endpoint=$API_SERVER"
echo "service_cidr=$SERVICE_CIDR"
echo "auth_mode=$AUTH_MODE -> param=$AUTH_MODE_PARAM"
echo "k8s_version=$K8S_VERSION"
```

##### Step 3B.2 — Create the Parameters File

!!! note ""

    `CertificateAuthorityData` is the base64 CA blob from `describe-cluster` — paste it verbatim, do not decode it. `NodeImageIdSSMParam` pins the AL2023 AMI to a Kubernetes minor version; it must match the cluster's `$K8S_VERSION`.

```bash
cat > /tmp/cf-params.json << EOF
[
  {"ParameterKey": "ClusterName",                         "ParameterValue": "$CLUSTER_NAME"},
  {"ParameterKey": "ClusterControlPlaneSecurityGroup",    "ParameterValue": "$CLUSTER_SG"},
  {"ParameterKey": "ApiServerEndpoint",                   "ParameterValue": "$API_SERVER"},
  {"ParameterKey": "CertificateAuthorityData",            "ParameterValue": "$CA_DATA"},
  {"ParameterKey": "ServiceCidr",                         "ParameterValue": "$SERVICE_CIDR"},
  {"ParameterKey": "AuthenticationMode",                  "ParameterValue": "$AUTH_MODE_PARAM"},
  {"ParameterKey": "NodeGroupName",                       "ParameterValue": "${CLUSTER_NAME}-nodes"},
  {"ParameterKey": "NodeInstanceType",                    "ParameterValue": "t3.medium"},
  {"ParameterKey": "NodeImageIdSSMParam",                 "ParameterValue": "/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2023/x86_64/standard/recommended/image_id"},
  {"ParameterKey": "NodeVolumeSize",                      "ParameterValue": "20"},
  {"ParameterKey": "VpcId",                               "ParameterValue": "$VPC_ID"},
  {"ParameterKey": "Subnets",                             "ParameterValue": "$SUBNET_IDS"},
  {"ParameterKey": "KeyName",                             "ParameterValue": "eks-nodes-key"},
  {"ParameterKey": "NodeAutoScalingGroupMinSize",         "ParameterValue": "1"},
  {"ParameterKey": "NodeAutoScalingGroupMaxSize",         "ParameterValue": "3"},
  {"ParameterKey": "NodeAutoScalingGroupDesiredCapacity", "ParameterValue": "3"}
]
EOF
```

!!! warning "The template's `AuthenticationMode` uses display strings, not the API enum"

    `describe-cluster` returns `API`, `API_AND_CONFIG_MAP`, or `CONFIG_MAP`, but the node template's `AuthenticationMode` parameter only accepts `EKS API`, `EKS API and ConfigMap`, or `ConfigMap`. Passing the raw enum fails with `Parameter 'AuthenticationMode' must be one of AllowedValues`. The `case` block in Step 3B.1 translates this into `$AUTH_MODE_PARAM` — use that variable, not `$AUTH_MODE`, in the params file. Choosing `EKS API` or `EKS API and ConfigMap` makes the template auto-create the node-role access entry, so the manual mapping in Step 5 becomes unnecessary.

!!! note ""

    This heredoc uses an **unquoted** `EOF` so the shell expands the `$VAR` references captured in Step 2 and Step 3B.1 (`CLUSTER_NAME`, `CLUSTER_SG`, `API_SERVER`, `CA_DATA`, `SERVICE_CIDR`, `AUTH_MODE`, `K8S_VERSION`, `VPC_ID`, `SUBNET_IDS`). If a new terminal was opened, re-run the capture commands. After writing the file, run `cat /tmp/cf-params.json` to confirm every value resolved and none are blank.

##### Step 4B — Launch the Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM
```

!!! note "Joining is simpler on Track B"

    Because `AuthenticationMode` is passed into the template, the AL2023 template wires up node access automatically when the cluster is in `API` or `API_AND_CONFIG_MAP` mode — in those cases the stack `Outputs` step is the last step and the manual mapping in Step 5 can be skipped. Only `CONFIG_MAP`-mode clusters still need the `aws-auth` step. The Step 5 branch below still applies as a fallback if nodes do not register.

---

#### Monitor the Stack

Regardless of track, monitor until `CREATE_COMPLETE`:

```bash
aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].StackStatus" \
  --output text
```

### Step 5 — Join Nodes to the Cluster

> ⚠️ **This is the single most common failure point in the entire runbook.**
>
> Nodes that never appear in `kubectl get nodes`, or that appear and stay `NotReady`, are almost always caused by an authentication-mode mismatch here — not a timing issue. **Waiting longer does not fix this.** Read the full step, confirm the mode, then run the correct path.

The stack creates the EC2 instances and their IAM instance role, but the nodes return `Unauthorized` from the API server until the **node IAM role is mapped to Kubernetes RBAC**. The mapping method depends on the cluster's authentication mode — fetch the node role ARN and confirm the mode first:

```bash
NODE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].Outputs[?OutputKey=='NodeInstanceRole'].OutputValue" \
  --output text)

aws eks update-kubeconfig --region us-east-1 --name "$CLUSTER_NAME"

AUTH_MODE=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.accessConfig.authenticationMode" \
  --output text)

echo "Node role ARN: $NODE_ROLE_ARN"
echo "Authentication mode: $AUTH_MODE"
```

!!! important ""

    If `AUTH_MODE` is `API`, the `aws-auth` ConfigMap is **completely ignored** — applying it appears to succeed (`configmap/aws-auth created`) but nodes stay `Unauthorized` forever. Match the path below to the mode.


**Path 1 — `AUTH_MODE` is `API` (use an access entry)**

```bash
aws eks create-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --region us-east-1 \
  --principal-arn "$NODE_ROLE_ARN" \
  --type EC2_LINUX
```

The `EC2_LINUX` type automatically confers the `system:bootstrappers` and `system:nodes` groups — no ConfigMap and no access-policy association are required.

!!! note ""

    `eks:CreateAccessEntry` may itself be restricted by the lab SCP. If it returns `AccessDeniedException`, this path is unavailable — recreate the cluster with `authenticationMode: API_AND_CONFIG_MAP` (see Phase 2) and use Path 2. Verify with the simulator:

    ```bash
    aws iam simulate-principal-policy \
      --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/<lab-username> \
      --action-names eks:CreateAccessEntry \
      --resource-arns arn:aws:eks:us-east-1::$ACCOUNT_ID:cluster/<cluster-name>
    ```


**Path 2 — `AUTH_MODE` is `CONFIG_MAP` or `API_AND_CONFIG_MAP` (use aws-auth)**

```bash
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml

sed -i "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|g" aws-auth-cm.yaml

kubectl apply -f aws-auth-cm.yaml
```

The placeholder must be replaced with the **instance role** ARN, not the instance profile ARN. Confirm the resulting `mapRoles` entry lists both `system:bootstrappers` and `system:nodes` under `groups`.

### Step 6 — Verify Nodes

```bash
kubectl get nodes
```

Once the role is mapped correctly, kubelet retries on its own and nodes register within ~30 seconds, then transition to `Ready` shortly after.

---

## Post-Cluster Add-ons

The following add-ons are not required for nodes to reach `Ready` state but are needed for storage and full networking support in production-grade workloads. Install them after `kubectl get nodes` confirms a healthy cluster.

### Install VPC CNI

If OIDC is enabled on the cluster, the VPC CNI addon should install automatically. Due to the `iam:PassRole` restriction, however, it may fail silently.

Check the addon status:

```bash
aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni --query "addon.status" --output text
```

If the addon is not installed:

**Option A — Console:**

1. Under **Add-on access** — select **"IAM roles for service accounts (IRSA)"**
2. Under **Select IAM role** — **leave it blank / don't choose any role**
3. Click **Next** → **Add**

**Option B — CLI (recommended, faster):**

```bash
# Install vpc-cni with no role — nodes will become Ready
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE

# Confirm addon is active
aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name vpc-cni \
  --query "addon.status"

# Nodes should now be Ready
kubectl get nodes
```

---

### Install EKS EBS CSI Driver

#### Create IAM Role (IRSA)

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

#### Get Role ARN

```bash
ROLE_ARN=$(aws iam get-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --query "Role.Arn" --output text)
echo $ROLE_ARN
```

#### Install Addon

!!! note
    **KodeKloud SCP Restriction:** `iam:PassRole` is blocked, so `--service-account-role-arn` cannot be passed directly to `aws eks create-addon`. Use the workaround below.

**This will fail:**
```bash
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $ROLE_ARN \
  --configuration-values '{"defaultStorageClass":{"enabled":true}}'
```

**Workaround — install without role, annotate manually:**
```bash
# Step 1: Install addon without passing role (bypasses iam:PassRole SCP)
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE

sleep 30

# Step 2: Annotate the service account directly
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN \
  --overwrite

# Step 3: Restart controller to pick up the annotation
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

#### Verify

```bash
kubectl get deploy ebs-csi-controller -n kube-system
kubectl get daemonset ebs-csi-node -n kube-system
```

---

## Troubleshooting

### `kubectl get nodes` returns `No resources found`

This is **not** a timing issue — waiting longer will not help. Nodes are being rejected by the API server, almost always an authentication-mode/identity-mapping problem from Step 5.

**1.** Re-check the mode:

```bash
aws eks describe-cluster --name <cluster-name> --query "cluster.accessConfig.authenticationMode" --output text
```

If the result is `API`, the aws-auth ConfigMap is being ignored — switch to Path 1 (access entry).

**2.** SSH or SSM onto a node and inspect kubelet:

```bash
sudo journalctl -u kubelet --no-pager | tail -30
```

Repeated `"Unable to register node with API server" err="Unauthorized"` confirms the role mapping is the problem, not bootstrap.

**3.** Confirm the node is assuming the correct role:

```bash
curl -s http://169.254.169.254/latest/meta-data/iam/info
```

The `InstanceProfileArn` must trace back to the node role from the CloudFormation stack output. A mismatch (e.g., a stale launch template) produces identical `Unauthorized` symptoms even with a correct mapping.

**4. Track B (AL2023) only:** nodes initialize via `nodeadm`, not `bootstrap.sh`. If nodes never appear *and* kubelet logs do **not** show `Unauthorized`, the likely cause is missing or wrong `nodeadm` metadata — verify `ApiServerEndpoint`, `CertificateAuthorityData`, and `ServiceCidr` in the params file against the cluster. Inspect the node's bootstrap:

```bash
sudo journalctl -u nodeadm-config -u nodeadm-run --no-pager | tail -40
```

**5.** If `kubectl describe node <node-name>` shows `container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady`, the VPC CNI addon is not running. Install it using the [Install VPC CNI](#install-vpc-cni) section above.
