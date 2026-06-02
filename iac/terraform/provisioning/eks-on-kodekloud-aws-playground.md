# EKS Cluster Setup on KodeKloud AWS Labs

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

This is confirmed by running the IAM policy simulator:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<account-id>:user/<lab-username> \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::<account-id>:role/AmazonEKSClusterRole
```

If `EvalDecision` returns `implicitDeny` and `AllowedByOrganizations` returns `False`, the SCP is the blocker. No workaround exists at the account level — the restriction is enforced at the AWS Organization level above the account.

---

## Whitelisted IAM Role Names

KodeKloud lab SCPs whitelist `iam:PassRole` only for roles with specific names. For EKS, the two confirmed whitelisted names are:

| Role | Exact Name | Purpose |
|------|------------|---------|
| Cluster Role | `eksClusterRole` | EKS control plane |
| Node Role | `eksNodeRole` | Self-managed worker nodes |

Any other role name (e.g., `AmazonEKSClusterRole`, `my-eks-role`, or eksctl auto-generated names) results in `implicitDeny`.

---

## Blocked Operations — Summary

| Action | Console | eksctl | AWS CLI | Terraform |
|--------|---------|--------|---------|-----------|
| `iam:PassRole` (wrong role name) | ❌ | ❌ | ❌ | ❌ |
| `iam:PassRole` (eksClusterRole / eksNodeRole) | ✅ | ✅ | ✅ | ✅ |
| `eks:CreateCluster` | ✅ | ✅ | ✅ | ✅ |
| `eks:CreateNodegroup` (managed) | ❌ | ❌ | ❌ | ❌ |
| Self-managed nodes via CloudFormation | ✅ | N/A | ✅ | ✅ |

!!! note ""
    - `eks:CreateNodegroup` is blocked unconditionally by the SCP regardless of the tool used.
    - Console, eksctl (CLI flags), eksctl (YAML/CloudFormation), AWS CLI, and Terraform all fail with `AccessDeniedException`.
    - **Workaround:** Use self-managed worker nodes provisioned via the AWS EKS CloudFormation node template and joined via `aws-auth`.

---

## Solution

### Step 1 — Create the IAM Roles via Terraform

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
```

!!! note ""
    If `eksClusterRole` already exists from a previous run, the apply will throw a `409 EntityAlreadyExists` error for that role. Import it instead:
    ```bash
    terraform import aws_iam_role.eks_cluster_role eksClusterRole
    terraform apply -auto-approve
    ```

### Step 2 — Apply the Terraform Script

```bash
terraform init
terraform apply -auto-approve
```

Both `eksClusterRole` and `eksNodeRole` are now present in IAM with the correct policies attached.

---

## Create the EKS Cluster

### Option A — AWS Console

1. Go to **EKS → Create Cluster**
2. Select `eksClusterRole` as the cluster service role
3. Complete the cluster creation wizard — the `iam:PassRole` error will not appear
4. Wait for the cluster status to become **Active**

!!! note ""
    **Managed node group creation via Console is blocked** — `eks:CreateNodegroup` is denied by the SCP. Do not attempt to add a managed node group through the Console. Use the self-managed node provisioning steps below instead.

### Option B — eksctl with YAML Config (Cluster Only)

Create `cluster.yaml`:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-cluster
  region: us-east-1

iam:
  serviceRoleARN: arn:aws:iam::<account-id>:role/eksClusterRole

managedNodeGroups: []
```

Run:

```bash
eksctl create cluster -f cluster.yaml
```

!!! note ""
    - Replace `<account-id>` with the AWS account ID visible in the Console top-right corner.
    - **Do not add `managedNodeGroups` entries.** eksctl creates node groups via `eks:CreateNodegroup` — blocked by the SCP. Keep the list empty and use the self-managed node provisioning steps below to attach worker nodes.

---

## Managed Node Groups — Blocked, No Workaround

`eks:CreateNodegroup` is denied by the Organizations SCP unconditionally. This has been verified via:

- AWS Console → `eks:CreateNodegroup` → `AccessDeniedException`
- `eksctl create nodegroup` → CloudFormation rollback → `AccessDeniedException`
- `aws eks create-nodegroup` → `AccessDeniedException`
- `terraform apply` with `aws_eks_node_group` → `AccessDeniedException`
- IAM policy simulator → `EvalDecision: implicitDeny`, `AllowedByOrganizations: False`

```bash
# Verification command
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<account-id>:user/<lab-username> \
  --action-names eks:CreateNodegroup \
  --resource-arns arn:aws:eks:us-east-1:<account-id>:cluster/<cluster-name>
```

**There is no workaround for managed node groups.** Use self-managed worker nodes instead (see next section).

---

## Self-Managed Worker Nodes — Workaround

Since `eks:CreateNodegroup` is blocked, worker nodes can still be attached to the cluster using the **AWS-provided EKS node CloudFormation template**. This creates an Auto Scaling Group of EC2 instances that bootstrap themselves and join the cluster via the `aws-auth` ConfigMap.

### Step 1 — Create an EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name eks-nodes-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/eks-nodes-key.pem

chmod 400 ~/.ssh/eks-nodes-key.pem
```

### Step 2 — Fetch Required IDs

Fetch VPC ID (replace `<cluster-name>` with the actual cluster name):

```bash
VPC_ID=$(aws eks describe-cluster \
  --name <cluster-name> \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo $VPC_ID
```

Fetch the cluster control plane security group ID:

```bash
CLUSTER_SG=$(aws eks describe-cluster \
  --name <cluster-name> \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

echo $CLUSTER_SG
```

Fetch private subnet IDs:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text
```

### Step 3 — Create CloudFormation Parameters File

!!! note ""
    Pass parameters via a JSON file. Passing the subnet list inline causes the AWS CLI to misparse the value.

```bash
cat > /tmp/cf-params.json << 'EOF'
[
  {"ParameterKey": "ClusterName",                         "ParameterValue": "<cluster-name>"},
  {"ParameterKey": "ClusterControlPlaneSecurityGroup",    "ParameterValue": "<CLUSTER_SG_ID>"},
  {"ParameterKey": "NodeGroupName",                       "ParameterValue": "<cluster-name>-nodes"},
  {"ParameterKey": "NodeInstanceType",                    "ParameterValue": "t3.medium"},
  {"ParameterKey": "NodeVolumeSize",                      "ParameterValue": "20"},
  {"ParameterKey": "VpcId",                               "ParameterValue": "<VPC_ID>"},
  {"ParameterKey": "Subnets",                             "ParameterValue": "subnet-xxx,subnet-yyy,subnet-zzz"},
  {"ParameterKey": "KeyName",                             "ParameterValue": "eks-nodes-key"},
  {"ParameterKey": "NodeAutoScalingGroupMinSize",         "ParameterValue": "1"},
  {"ParameterKey": "NodeAutoScalingGroupMaxSize",         "ParameterValue": "3"},
  {"ParameterKey": "NodeAutoScalingGroupDesiredCapacity", "ParameterValue": "3"}
]
EOF
```

Replace all `<PLACEHOLDER>` values with the IDs collected in Step 2.

### Step 4 — Launch CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2022-12-23/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM
```

Monitor until `CREATE_COMPLETE`:

```bash
aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].StackStatus" \
  --output text
```

### Step 5 — Join Nodes to the Cluster

```bash
NODE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].Outputs[?OutputKey=='NodeInstanceRole'].OutputValue" \
  --output text)

curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml

sed -i "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|g" aws-auth-cm.yaml

aws eks update-kubeconfig --region us-east-1 --name <cluster-name>

kubectl apply -f aws-auth-cm.yaml
```

### Step 6 — Verify Nodes

```bash
kubectl get nodes
```

All nodes transition from `NotReady` to `Ready` within ~2 minutes.

---

## Node Group Decision Matrix

| Method | Supported | Notes |
|--------|-----------|-------|
| Managed node group (Console) | ❌ | `eks:CreateNodegroup` blocked by SCP |
| Managed node group (eksctl) | ❌ | Same SCP block via CloudFormation |
| Managed node group (AWS CLI) | ❌ | Same SCP block |
| Managed node group (Terraform `aws_eks_node_group`) | ❌ | Same SCP block |
| **Self-managed nodes (CloudFormation template)** | ✅ | Supported workaround — this runbook |
| **Self-managed nodes via retail-store Terraform module** | ✅ | Supported — pre-authorized execution context |
