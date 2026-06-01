# Deploying EKS Cluster on KodeKloud AWS Playground via Terraform

- **Repo:** [retail-store-sample-app](https://github.com/ibtisam-iq/retail-store-sample-app)
- **Terraform entry point:** [terraform/eks/minimal](https://github.com/ibtisam-iq/retail-store-sample-app/tree/main/terraform/eks/minimal)
- **Cluster name:** `retail-store`
- **Region:** `us-east-1`

!!! note ""
    This runbook covers the deployment of an Amazon Elastic Kubernetes Service (EKS) cluster using Terraform on the [KodeKloud AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws). It specifically addresses the constraints and permission limitations inherent in the Playground environment, ensuring a successful deployment without errors.

---

## Context

KodeKloud AWS Playground uses an IAM user (`kk_labs_user_*`) with a restrictive permission boundary. The following actions are **blocked**:

- `logs:PutRetentionPolicy`
- `iam:PutRolePolicy` (inline policies)
- `iam:PassRole` on custom role names
- `eks:CreateNodegroup` (managed node groups entirely blocked)

The Terraform module at `terraform/lib/eks/eks.tf` wraps `terraform-aws-modules/eks/aws ~> 19.9` and must be patched to work around all four restrictions.

---

## KodeKloud Playground IAM Restrictions — Quick Reference

| Blocked Action | Root Cause | Fix Applied |
|---|---|---|
| `logs:PutRetentionPolicy` | No CloudWatch perms | `create_cloudwatch_log_group = false` |
| `iam:PutRolePolicy` | Inline policies blocked | `create_iam_role = false` + custom role |
| `iam:PassRole` on custom names | Whitelist enforced | Rename role to `eksClusterRole` |
| `eks:CreateNodegroup` | Managed node groups blocked | CloudFormation self-managed nodes |

---

## Fix 1 — Disable CloudWatch Log Group Creation

**File:** `terraform/lib/eks/eks.tf`

**Problem:** The module tries to create `/aws/eks/retail-store/cluster` log group and set a retention policy. Both `logs:CreateLogGroup` (on re-run, due to leftover resource) and `logs:PutRetentionPolicy` fail.

Add these two arguments inside `module "eks_cluster"`:

```hcl
create_cloudwatch_log_group = false
cluster_enabled_log_types   = []
```

---

## Fix 2 — Bypass Inline Policy with Custom IAM Role

**File:** `terraform/lib/eks/eks.tf`

**Problem:** The module creates the cluster IAM role with an inline policy using `iam:PutRolePolicy`, which is blocked. The `iam_role_additional_policies = {}` argument does not suppress the inline policy in v19.

Disable the module's role creation and provide a custom one.

Inside `module "eks_cluster"` add:

```hcl
create_iam_role = false
iam_role_arn    = aws_iam_role.eks_cluster_role.arn
```

Add these new resources to the same `eks.tf`:

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

!!! note "Important"
    The role name MUST be `eksClusterRole`. KodeKloud's permission boundary only grants `iam:PassRole` on a hardcoded whitelist of role names. Any other name causes `AccessDeniedException` on `eks:CreateCluster`.

---

## Fix 3 — Disable Managed Node Groups

**File:** `terraform/lib/eks/eks.tf`

**Problem:** `eks:CreateNodegroup` is entirely blocked on KodeKloud playground. All managed node groups fail with `AccessDeniedException`.

Replace the `eks_managed_node_groups` block with an empty map:

```hcl
eks_managed_node_groups = {}
```

Run Terraform apply after all three fixes above:

```bash
cd ~/retail-store-sample-app/terraform/eks/minimal
terraform apply
```

The EKS control plane takes ~9 minutes to provision. This is expected.

---

## Fix 4 — Add Worker Nodes via Self-Managed CloudFormation Stack

**Problem:** With managed node groups disabled, the cluster has no worker nodes. Self-managed nodes must be provisioned via the AWS-provided CloudFormation template.

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

Fetch the cluster control plane security group ID.

!!! note "Important"
    Use the SG named `retail-store-cluster`. Do NOT use `eks-cluster-sg-retail-store-*` (that is the primary/shared SG auto-created by EKS) and do NOT use `retail-store-node`.

```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=retail-store-cluster" \
  --query "SecurityGroups[0].GroupId" \
  --output text
```

Fetch VPC ID:

```bash
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=retail-store" \
  --query "Vpcs[0].VpcId" \
  --output text)
```

Fetch private subnet IDs (tagged by the Terraform VPC module with `kubernetes.io/role/internal-elb`):

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text
```

### Step 4 — Create Parameters File

Pass parameters via a JSON file to avoid AWS CLI shell-parsing issues with comma-delimited subnet lists. Passing subnets inline (even with `\,` escaping) causes the CLI to incorrectly interpret the value as a Python list.

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

!!! note "Important"
    Replace the placeholder values with the values obtained in the previous steps.

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
