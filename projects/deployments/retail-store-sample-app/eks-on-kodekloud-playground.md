# Deploying EKS Cluster on KodeKloud AWS Playground via Terraform

- **Repo:** [retail-store-sample-app](https://github.com/ibtisam-iq/retail-store-sample-app)
- **Terraform entry point:** [terraform/eks/minimal](https://github.com/ibtisam-iq/retail-store-sample-app/tree/main/terraform/eks/minimal)
- **Cluster name:** `retail-store`
- **Region:** `us-east-1`

!!! note ""
    This runbook covers the deployment of an Amazon Elastic Kubernetes Service (EKS) cluster using Terraform on the [KodeKloud AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws). It specifically addresses the constraints and permission limitations inherent in the Playground environment, ensuring a successful deployment without errors.

---

## Context

KodeKloud AWS Playground uses an IAM user (`kk_labs_user_*`) with a restrictive permission boundary. Several IAM and EKS actions that the upstream Terraform module expects are **blocked**:

| Blocked Action | Impact |
|---|---|
| `logs:PutRetentionPolicy` | Cannot set CloudWatch log retention |
| `iam:PutRolePolicy` | Cannot attach inline policies to IAM roles |
| `iam:PassRole` on custom names | Only whitelisted role names (`eksClusterRole`) are allowed |
| `eks:CreateNodegroup` | Managed node groups entirely blocked |

The Terraform module at `terraform/lib/eks/eks.tf` wraps `terraform-aws-modules/eks/aws ~> 19.9` and must be patched before applying.

---

## Deployment Overview

Because of the restrictions above, deployment happens in **two phases**:

1. **Pre-apply patches** — modify Terraform source to avoid blocked actions, then run `terraform apply` (first apply)
2. **Node bootstrap** — manually provision self-managed worker nodes via CloudFormation, join them to the cluster, then run `terraform apply` again (second apply)

!!! warning "Do not skip straight to `terraform apply`"
    Running `terraform apply` without the patches in Phase 1 will fail immediately. Running the second `terraform apply` without worker nodes will fail on Helm addon webhooks.

---

## Phase 1 — Patch Terraform & First Apply

### Fix 1 — Disable CloudWatch Log Group

**File:** `terraform/lib/eks/eks.tf`

**Error without this fix:**
```
AccessDeniedException: not authorized to perform: logs:PutRetentionPolicy
```

Add inside `module "eks_cluster"`:

```hcl
create_cloudwatch_log_group = false
```

---

### Fix 2 — Replace Inline IAM Role with Custom Role

**File:** `terraform/lib/eks/eks.tf`

**Error without this fix:**
```
AccessDenied: not authorized to perform: iam:PutRolePolicy
```

The module creates an inline policy on the cluster role by default. Disable it and supply a custom role.

Inside `module "eks_cluster"` add:

```hcl
create_iam_role = false
iam_role_arn    = aws_iam_role.eks_cluster_role.arn
```

Add these new resources to the same file:

```hcl
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}
```

!!! warning "Role name is mandatory"
    The role name MUST be `eksClusterRole`. KodeKloud's permission boundary only grants `iam:PassRole` on a hardcoded whitelist. Any other name causes `AccessDeniedException` on `eks:CreateCluster`.

---

### Fix 3 — Disable Managed Node Groups

**File:** `terraform/lib/eks/eks.tf`

**Error without this fix:**
```
AccessDeniedException: not authorized to perform: eks:CreateNodegroup
```

Replace the `eks_managed_node_groups` block with an empty map:

```hcl
eks_managed_node_groups = {}
```

---

### First `terraform apply`

With all three fixes in place, run the first apply:

```bash
cd ~/retail-store-sample-app/terraform/eks/minimal
terraform apply
```

**Expected partial failures on first apply:**

| Resource | Error | Resolution |
|---|---|---|
| `helm_release.cert_manager` | `no endpoints available for service "aws-load-balancer-webhook-service"` | No worker nodes yet — resolved after Phase 2 |

---

## Phase 2 — Self-Managed Worker Nodes

With the control plane running but no worker nodes, the `cert-manager` Helm webhook fails because the `aws-load-balancer-controller` has nowhere to schedule. Worker nodes must be provisioned manually via the AWS-provided CloudFormation template.

### Step 1 — Create Node IAM Role

```bash
aws iam create-role \
  --role-name eksNodeRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }'

aws iam attach-role-policy --role-name eksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy --role-name eksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy --role-name eksNodeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### Step 2 — Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name eks-nodes-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/eks-nodes-key.pem

chmod 400 ~/.ssh/eks-nodes-key.pem
```

### Step 3 — Fetch Required IDs

Fetch VPC ID:

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=retail-store" \
  --query "Vpcs[0].VpcId" \
  --output text)
```

Fetch the cluster control plane security group ID:

!!! warning ""
    Use the SG named `retail-store-cluster`. Do **not** use `eks-cluster-sg-retail-store-*` (auto-created by EKS) and do **not** use `retail-store-node`.

```bash
CLUSTER_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=retail-store-cluster" \
  --query "SecurityGroups[0].GroupId" \
  --output text)
```

Fetch private subnet IDs (tagged `kubernetes.io/role/internal-elb=1` by the Terraform VPC module):

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text
```

### Step 4 — Create Parameters File

!!! note ""
    Pass parameters via a JSON file. Passing the subnet list inline (even with `\,` escaping) causes the AWS CLI to misparse the value as a Python list.

```bash
cat > /tmp/cf-params.json << 'EOF'
[
  {"ParameterKey": "ClusterName",                         "ParameterValue": "retail-store"},
  {"ParameterKey": "ClusterControlPlaneSecurityGroup",    "ParameterValue": "<CLUSTER_SG_ID>"},
  {"ParameterKey": "NodeGroupName",                       "ParameterValue": "retail-store-nodes"},
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

Replace all `<PLACEHOLDER>` values with the IDs collected in Step 3.

### Step 5 — Launch CloudFormation Stack

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

### Step 6 — Join Nodes to Cluster

```bash
NODE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].Outputs[?OutputKey=='NodeInstanceRole'].OutputValue" \
  --output text)

curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml

sed -i "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|g" aws-auth-cm.yaml

aws eks update-kubeconfig --region us-east-1 --name retail-store

kubectl apply -f aws-auth-cm.yaml
```

### Step 7 — Verify Nodes

```bash
kubectl get nodes
```

All 3 nodes transition from `NotReady` to `Ready` within ~2 minutes.

---

## Second `terraform apply`

With worker nodes running, re-run apply. Terraform retries only the previously failed resources:

```bash
terraform apply
```

Expected outcome: `cert-manager` Helm release succeeds (~1m19s), ADOT addon installs, and the plan ends with:

```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

---

## Post-Deployment Verification

### Verify System Deployments

```bash
kubectl get deployments -n kube-system
```

Expected deployments:

| Deployment | Replicas | Description |
|---|---|---|
| `aws-load-balancer-controller` | 2/2 | ALB Ingress controller |
| `cert-manager` | 1/1 | Certificate manager |
| `cert-manager-cainjector` | 1/1 | CA injector |
| `cert-manager-webhook` | 1/1 | Cert-manager webhook |
| `coredns` | 2/2 | Cluster DNS |

### Verify StorageClass

```bash
kubectl get storageclass
```

`gp2` should be listed and marked as default.

### Verify IngressClass

```bash
kubectl get ingressclass
```

`alb` should be listed.
