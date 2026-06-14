# EKS Cluster on KodeKloud AWS Playground via Terraform

!!! info "What this runbook is"
    A complete, verified operational record of provisioning a production-pattern
    EKS cluster on a **KodeKloud AWS Playground** account using Terraform — an
    environment where an AWS Organizations SCP silently blocks several standard
    EKS operations. Every architectural decision in this runbook exists because
    a standard approach was blocked and tested against the SCP.

    End state:
    
    - VPC with public/private subnets across 3 AZs
    - Bastion host in a public subnet (SSH-accessible)
    - EKS 1.35 control plane with private API endpoint
    - Three AL2023 self-managed worker nodes joined and `Ready`
    - Full `kubectl` access from the bastion

    For every error encountered during development, see the companion runbook:
    [KodeKloud EKS Terraform — Challenges and Fixes →](./eks-on-kodekloud-terraform-challenges.md)

---

## SCP Constraints — Non-Negotiable on This Platform

KodeKloud playground accounts operate under an AWS Organizations SCP that blocks
specific actions. These are the confirmed constraints:

| Blocked Action | Consequence | Workaround |
|---|---|---|
| `iam:PassRole` (non-whitelisted name) | Cluster creation fails unless the role name is exactly `eksClusterRole` | Create roles with whitelisted names in a separate `iam-eks.tf` |
| `iam:TagPolicy` | KMS encryption IAM policy creation fails | Disable all KMS encryption in the cluster config |
| `eks:CreateNodegroup` | Managed node groups impossible regardless of tool | Self-managed nodes via CloudFormation |
| `eks:AssociateAccessPolicy` | Cannot attach Kubernetes policies to access entries | Use `bootstrap_cluster_creator_admin_permissions = true` directly on the cluster resource |
| `eks:DeleteAddon` | `terraform destroy` fails on addon deletion | `preserve = true` on all EKS addon resources |
| `logs:DeleteLogGroup` | `terraform destroy` fails on CW log group deletion | Do not manage the log group in Terraform |

!!! warning "Why the `terraform-aws-modules/eks/aws` module does not work here"
    The EKS module v21.x **silently drops** `bootstrap_cluster_creator_admin_permissions`
    from the cluster's `access_config` block when `create_iam_role = false`. Since
    `iam:PassRole` requires the whitelisted name `eksClusterRole`, `create_iam_role`
    must be `false` — which means the module leaves the cluster with no admin access.
    The workaround is to bypass the module and use a raw `aws_eks_cluster` resource
    where the setting is passed directly to the AWS API.

---

## Repository Structure

```
microservices-demo/terraform/eks-kodekloud/
├── terraform.tf      # Provider requirements (aws ~> 6.42)
├── variables.tf      # All input variables
├── data.tf           # AMI lookup, caller identity, region, public IP
├── vpc.tf            # VPC via terraform-aws-modules/vpc (no SCP issues)
├── bastion.tf        # Bastion via terraform-aws-modules/ec2-instance
├── iam-eks.tf        # SCP-whitelisted IAM roles: eksClusterRole + eksNodeRole
├── eks.tf            # Raw aws_eks_cluster + OIDC provider + addons
└── outputs.tf        # All outputs
```

---

## Dev Machine

I use [SilverStack Dev Machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) — a custom root filesystem on iximiuz Labs, which I maintain with all DevOps tools pre-installed (`kubectl`, `eksctl`, `terraform`, `helm`, `helmfile`, `aws cli`, etc.). No local machine setup is required.

---

## Phase 1 — IAM Roles (`iam-eks.tf`)

The SCP allows `iam:PassRole` only for roles named exactly `eksClusterRole` and
`eksNodeRole`. The EKS module auto-generates role names that do not match
(e.g., `silver-stack-eks-cluster-20260610...`), so roles must be created
explicitly before anything else.

```hcl
# iam-eks.tf

resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"  # exact whitelisted name — do not change

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "eksClusterRole" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeRole"  # exact whitelisted name — do not change

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "eksNodeRole" }
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

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

!!! note "If the roles already exist from a previous session"
    KodeKloud playground accounts sometimes retain IAM resources across sessions.
    If `terraform apply` fails with `EntityAlreadyExists`:

    ```bash
    terraform import aws_iam_role.eks_cluster_role eksClusterRole
    terraform import aws_iam_role.eks_node_role eksNodeRole
    terraform apply
    ```

---

## Phase 2 — Network and Bastion

`vpc.tf` and `bastion.tf` use the standard community modules. Neither triggers
SCP restrictions — the SCP targets IAM and EKS, not VPC or EC2. No changes
to the module defaults are required for KodeKloud compatibility.

Key decisions:

- **Private subnets** for EKS worker nodes (no direct internet exposure)
- **Public subnets** for the bastion and NAT gateway
- **Single NAT gateway** (dev/staging cost tradeoff)
- **Bastion IP lock**: the security group restricts SSH ingress to the single
  IP that ran `terraform apply`, via `data.http.my_ip`

The bastion requires an IAM role attached if SSM Session Manager access is
needed. With `AmazonSSMManagedInstanceCore` attached to `eksNodeRole`, nodes
can be accessed via SSM without a key pair after they join the cluster.

---

## Phase 3 — EKS Cluster (`eks.tf`)

This file uses **raw `aws_eks_cluster`** and individual `aws_eks_addon` resources
rather than the `terraform-aws-modules/eks/aws` module. See the constraints table
above for why the module cannot be used reliably here.

```hcl
# eks.tf

resource "aws_security_group" "eks_additional" {
  name        = "${var.project_name}-eks-additional-sg"
  description = "Allow bastion host to reach EKS API on port 443"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTPS from bastion host"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-eks-additional-sg" }
}

resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_additional.id]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  tags            = { Name = "${var.project_name}-eks-oidc" }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  preserve                    = true
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  preserve                    = true
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  preserve                    = true
}
```

!!! important "`bootstrap_cluster_creator_admin_permissions = true` is the critical field"
    This passes `bootstrapClusterCreatorAdminPermissions: true` directly to the
    AWS `CreateCluster` API call. EKS handles the admin access entry internally
    at creation time — no `eks:AssociateAccessPolicy` call is made, so the SCP
    is never triggered. Omitting this field (or relying on the module to set it)
    results in a cluster the lab user cannot access.

!!! note "CoreDNS is intentionally absent from the addon list"
    The `aws_eks_addon` resource waits up to 20 minutes for Active status.
    CoreDNS stays Degraded until worker nodes exist to schedule its pods — on a
    fresh cluster with no nodes, the apply hangs and eventually times out. EKS
    installs CoreDNS automatically as a built-in Kubernetes deployment; it
    activates once self-managed nodes join the cluster in Phase 4. No Terraform
    resource and no manual step are needed.

!!! note "`preserve = true` on every addon"
    `eks:DeleteAddon` is blocked by the KodeKloud SCP. With `preserve = true`,
    `terraform destroy` removes the resource from state without calling the AWS
    API, avoiding `AccessDeniedException` on teardown.

---

## Phase 4 — Apply Terraform

### Step 1: Clone and configure terraform in the KodeKloud Lab

!!! info "Use Iximiuz playground as Dev Machine"
    See [Dev Machine](#dev-machine) section for more details.

```bash
# Clone and enter the repo
git clone https://github.com/ibtisam-iq/silver-stack.git
cd silver-stack/terraform/aws/eks-kodekloud

# Configure lab credentials
aws configure
aws sts get-caller-identity  # confirm identity before applying

# If re-running in the same terminal after a previous lab session, wipe state
rm -f terraform.tfstate terraform.tfstate.backup

terraform init
terraform apply
```

!!! warning "Stale state file from an expired lab"
    KodeKloud credentials expire with the session, but the local `terraform.tfstate`
    persists across sessions. If the state references resources in the old account
    (visible as `aws_account_id` changing in the plan output), delete the state
    file before applying. Terraform will create everything fresh in the new account.
    See [Challenges runbook → Stale state after lab restart](./eks-on-kodekloud-terraform-challenges.md).

Expected apply time: 12 to 15 minutes (EKS control plane creation dominates).

### Step 2: Associate OIDC provider manually (no iam:PassRole triggered here)

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve
```

---

## Phase 5 — Self-Managed Nodes (CloudFormation)

`eks:CreateNodegroup` is blocked unconditionally. Worker nodes are provisioned
via the AWS-provided EKS CloudFormation node template after Terraform apply.

### 5.1 — SSH to Bastion and Configure Credentials

!!! info "Install Tools on bastion"
    Reference: [Install Tools on bastion](../../../bootstrap/kubernetes/client-tools/index.md)

```bash
# Use the ssh command from Terraform outputs
ssh -i silver-stack-eks-bastion-key.pem ubuntu@<bastion_public_ip>

# On the bastion
aws configure
# Enter the same KodeKloud lab credentials used on the dev machine

aws sts get-caller-identity  # confirm before proceeding
aws eks update-kubeconfig --region us-east-1 --name silver-stack-eks
kubectl get nodes  # should return "No resources found" — NOT Forbidden
```

!!! important "Verify kubectl before proceeding"
    If `kubectl get nodes` returns a `Forbidden` or authentication error,
    stop here and consult the [Challenges runbook](./eks-on-kodekloud-terraform-challenges.md).
    Proceeding with broken kubectl access means nodes will join but you will
    not be able to verify or manage them.

### 5.2 — Collect Cluster Metadata

```bash
CLUSTER_NAME=silver-stack-eks
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
BASTION_KEY="${CLUSTER_NAME}-bastion-key"

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

CLUSTER_SG=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

# Private subnets for nodes — they are already tagged by vpc.tf
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

API_SERVER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.endpoint" --output text)

CA_DATA=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.certificateAuthority.data" --output text)

SERVICE_CIDR=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.kubernetesNetworkConfig.serviceIpv4Cidr" --output text)

K8S_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.version" --output text)

AUTH_MODE=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
  --query "cluster.accessConfig.authenticationMode" --output text)

case "$AUTH_MODE" in
  API)                AUTH_MODE_PARAM="EKS API" ;;
  API_AND_CONFIG_MAP) AUTH_MODE_PARAM="EKS API and ConfigMap" ;;
  CONFIG_MAP)         AUTH_MODE_PARAM="ConfigMap" ;;
esac

echo "VPC: $VPC_ID | SG: $CLUSTER_SG | Subnets: $SUBNET_IDS"
echo "API: $API_SERVER | CIDR: $SERVICE_CIDR | K8s: $K8S_VERSION"
echo "Auth: $AUTH_MODE -> $AUTH_MODE_PARAM"
```

Verify none of the variables are blank before continuing. A blank value in
the CF parameters file will cause the stack to fail silently or use defaults.

### 5.3 — Confirm Template Parameter Set (Optional)

The accepted parameter keys differ between CloudFormation template versions.
Always print the authoritative list before writing the params file.

```bash
aws cloudformation get-template-summary \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --query "Parameters[].ParameterKey" \
  --output text | tr '\t' '\n' | sort
```

### 5.4 — Build Parameters File

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
  {"ParameterKey": "KeyName",                             "ParameterValue": "$BASTION_KEY"},
  {"ParameterKey": "NodeAutoScalingGroupMinSize",         "ParameterValue": "1"},
  {"ParameterKey": "NodeAutoScalingGroupMaxSize",         "ParameterValue": "3"},
  {"ParameterKey": "NodeAutoScalingGroupDesiredCapacity", "ParameterValue": "3"}
]
EOF

cat /tmp/cf-params.json  # verify no blank values
```

!!! warning "`AuthenticationMode` uses display strings, not API enum values"
    The CloudFormation template's `AuthenticationMode` parameter accepts
    `EKS API`, `EKS API and ConfigMap`, or `ConfigMap` — not the API enum
    values `API`, `API_AND_CONFIG_MAP`, `CONFIG_MAP`. The `case` block above
    translates them. Using the raw enum produces `ValidationError: Parameter
    'AuthenticationMode' must be one of AllowedValues`.

### 5.5 — Launch the Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM

# Poll until CREATE_COMPLETE (~5 min)
watch -n 10 "aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query 'Stacks[0].StackStatus' --output text"
```

### 5.6 — Join Nodes to the Cluster

The AL2023 template with `AuthenticationMode = "EKS API and ConfigMap"` automatically creates an `EC2_LINUX` access entry for the node role, so nodes should register on their own. Verify first:

```bash
kubectl get nodes -w
# Expected: 3 nodes in Ready state within ~2 min of stack completing
```

If nodes are `NotReady` or absent after 5 minutes, apply the aws-auth ConfigMap manually:

```bash
NODE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].Outputs[?OutputKey=='NodeInstanceRole'].OutputValue" \
  --output text)

curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml
sed -i "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|g" aws-auth-cm.yaml
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
kubectl apply -f aws-auth-cm.yaml
```

---

## Phase 6 — Verification

```bash
# All system pods running
kubectl get pods -A

# Three nodes Ready
kubectl get nodes

# OIDC provider present (needed for IRSA in later phases)
aws iam list-open-id-connect-providers

# Cluster access config
aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.accessConfig"
```

Expected `kubectl get nodes` output:

```
NAME                        STATUS   ROLES    AGE   VERSION
ip-10-0-1-20.ec2.internal   Ready    <none>   10m   v1.35.x-eks-xxxxxxx
ip-10-0-2-67.ec2.internal   Ready    <none>   10m   v1.35.x-eks-xxxxxxx
ip-10-0-3-52.ec2.internal   Ready    <none>   10m   v1.35.x-eks-xxxxxxx
```

---

## Phase 7 — Cleanup

`terraform destroy` on KodeKloud has three known SCP-related failure modes.
The recommended approach avoids all of them:

```bash
# Step 1: Remove addon resources from state (eks:DeleteAddon blocked)
# These have preserve = true, so destroy would attempt nothing anyway,
# but removing them makes the plan cleaner.
terraform state rm 'aws_eks_addon.vpc_cni'
terraform state rm 'aws_eks_addon.kube_proxy'
terraform state rm 'aws_eks_addon.pod_identity_agent'

# Step 2: Destroy the rest
terraform destroy
```

!!! note "CloudFormation node stack"
    `terraform destroy` does not manage the CloudFormation node stack (it was
    created manually via AWS CLI). Delete it separately:

    ```bash
    aws cloudformation delete-stack --stack-name eks-nodes-stack
    ```

    Wait for `DELETE_COMPLETE` before running `terraform destroy`, otherwise
    the VPC deletion will fail because the node security group is still attached.

---

## Related Runbooks

| Topic | Link |
|---|---|
| Every error encountered during this setup | [KodeKloud EKS Terraform — Challenges and Fixes](./eks-on-kodekloud-terraform-challenges.md) |
| EKS cluster via eksctl (manual approach) | [EKS on KodeKloud AWS Playground](./eks-on-kodekloud-eksctl.md) |
| EBS CSI driver installation | [Install EBS CSI Driver](../../../bootstrap/kubernetes/addons-eks/install-ebs-csi-driver.md) |
| AWS Load Balancer Controller | [Deploy AWS Load Balancer Controller](../../../bootstrap/kubernetes/addons-eks/deploy-aws-load-balancer-controller.md) |
