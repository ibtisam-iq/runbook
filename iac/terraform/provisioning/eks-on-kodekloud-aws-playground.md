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

| Role         | Exact Name       | Purpose                   |
| ------------ | ---------------- | ------------------------- |
| Cluster Role | `eksClusterRole` | EKS control plane         |
| Node Role    | `eksNodeRole`    | Self-managed worker nodes |

Any other role name (e.g., `AmazonEKSClusterRole`, `my-eks-role`, or eksctl auto-generated names) results in `implicitDeny`.

---

## Blocked Operations — Summary

| Action                                        | Console | eksctl | AWS CLI | Terraform |
| --------------------------------------------- | ------- | ------ | ------- | --------- |
| `iam:PassRole` (wrong role name)              | ❌       | ❌      | ❌       | ❌         |
| `iam:PassRole` (eksClusterRole / eksNodeRole) | ✅       | ✅      | ✅       | ✅         |
| `eks:CreateCluster`                           | ✅       | ✅      | ✅       | ✅         |
| `eks:CreateNodegroup` (managed)               | ❌       | ❌      | ❌       | ❌         |
| Self-managed nodes via CloudFormation         | ✅       | N/A    | ✅       | ✅         |

!!! note ""

    - `eks:CreateNodegroup` is blocked unconditionally by the SCP regardless of the tool used.
    - Console, eksctl (CLI flags), eksctl (YAML/CloudFormation), AWS CLI, and Terraform all fail with `AccessDeniedException`.
    - **Workaround:** Use self-managed worker nodes provisioned via the AWS EKS CloudFormation node template and joined via either an EKS **access entry** or the legacy **aws-auth** ConfigMap, depending on the cluster's authentication mode (see [Step 5](#step-5--join-nodes-to-the-cluster)).


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

# Optional: enables AWS Systems Manager Session Manager access to nodes,
# avoiding SSH key management on ephemeral playground instances.
resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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

!!! important "Authentication mode matters for joining nodes later"

    Newer EKS clusters default to `API` authentication mode, in which the legacy `aws-auth` ConfigMap is **silently ignored**. If the Console offers an authentication-mode choice, selecting **`EKS API and ConfigMap`** keeps both join paths available. Either way, you must confirm the mode before joining nodes — see [Step 5](#step-5--join-nodes-to-the-cluster).


!!! note "Managed node group creation via Console is blocked"

    `eks:CreateNodegroup` is denied by the SCP. Do not attempt to add a managed node group through the Console. Use the self-managed node provisioning steps below instead.


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
  withOIDC: true  # required for IRSA (IAM Roles for Service Accounts)

# Make both join paths available (access entries + aws-auth ConfigMap).
# Omit or set to "API" and you must use access entries to join nodes.
accessConfig:
  authenticationMode: API_AND_CONFIG_MAP

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

Since `eks:CreateNodegroup` is blocked, worker nodes can still be attached to the cluster using the **AWS-provided EKS node CloudFormation template**. This creates an Auto Scaling Group of EC2 instances that bootstrap themselves and join the cluster.

### Step 1 — Create an EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name eks-nodes-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/eks-nodes-key.pem

chmod 400 ~/.ssh/eks-nodes-key.pem
```

### Step 2 — Fetch Required IDs

Fetch VPC ID directly from the cluster:

```bash
# Set once and reuse for every lookup below (and in Track B).
CLUSTER_NAME=<cluster-name>
```

```bash
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo $VPC_ID
```

Fetch the cluster security group ID directly from the cluster:

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

    Choose the option that fits the situation.


**Option A — Tag subnets first, then fetch (recommended for full LB support)**

First list all subnets in the VPC to identify their IDs and Availability Zones:

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

    Without the `kubernetes.io/role/internal-elb` and `kubernetes.io/role/elb` tags, the AWS Load Balancer Controller cannot discover subnets and will fail to provision ALB/NLB for your applications. If you use Option B now, apply the tags from Option A before deploying any Ingress or Service of type LoadBalancer.


### Step 3 — Choose a Node Template Track

AWS ships two generations of the self-managed node CloudFormation template, and they are **not** interchangeable. Pick the one that matches your cluster's Kubernetes version, then follow that track's parameter file (Step 3x) and launch command (Step 4x).

| | **Track A — Amazon Linux 2** | **Track B — Amazon Linux 2023** |
| --- | --- | --- |
| Template | `2022-12-23/amazon-eks-nodegroup.yaml` | `2025-11-26/amazon-eks-nodegroup.yaml` |
| Bootstrap | `/etc/eks/bootstrap.sh` (auto-discovers cluster metadata) | `nodeadm` (metadata must be passed explicitly) |
| Kubelet | ships 1.24.17 | tracks AMI / cluster version |
| Works for K8s | only versions that still publish an AL2 AMI | current versions (1.30+ default to AL2023) |
| Extra params needed | none | `ApiServerEndpoint`, `CertificateAuthorityData`, `ServiceCidr`, `AuthenticationMode`, `NodeImageIdSSMParam` |
| Status here | known-working on KodeKloud playground | current AWS default — verify SCP interaction on first run |

!!! danger "Amazon Linux 2 is end-of-life"

    Amazon Linux 2 reached end of support on **2025-06-30**, and the `2022-12-23` template's kubelet 1.24 is long past EKS support. A current control plane will not run 1.24, so AL2/1.24 nodes from Track A will mismatch and fail to register. **Track A is only viable if you deliberately created the cluster at an older Kubernetes version that still publishes an AL2 AMI, and accept running EOL nodes on a throwaway playground.** For anything else, use Track B.

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

Now skip to [monitoring the stack](#monitor-the-stack).

---

#### Track B — Amazon Linux 2023 (current)

AL2023 nodes use `nodeadm` instead of `bootstrap.sh` and no longer auto-discover cluster metadata, so the template requires several values that Track A did not. Collect them first.

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

K8S_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region us-east-1 \
  --query "cluster.version" --output text)

echo "cluster=$CLUSTER_NAME"
echo "endpoint=$API_SERVER"
echo "service_cidr=$SERVICE_CIDR"
echo "auth_mode=$AUTH_MODE"
echo "k8s_version=$K8S_VERSION"
```

##### Step 3B.2 — Create the Parameters File

!!! note ""

    `CertificateAuthorityData` is the base64 CA blob from `describe-cluster` — paste it verbatim, do not decode it. `NodeImageIdSSMParam` pins the AL2023 AMI to a Kubernetes minor version; it must match your cluster (`$K8S_VERSION` above).

```bash
cat > /tmp/cf-params.json << EOF
[
  {"ParameterKey": "ClusterName",                         "ParameterValue": "$CLUSTER_NAME"},
  {"ParameterKey": "ClusterControlPlaneSecurityGroup",    "ParameterValue": "$CLUSTER_SG"},
  {"ParameterKey": "ApiServerEndpoint",                   "ParameterValue": "$API_SERVER"},
  {"ParameterKey": "CertificateAuthorityData",            "ParameterValue": "$CA_DATA"},
  {"ParameterKey": "ServiceCidr",                         "ParameterValue": "$SERVICE_CIDR"},
  {"ParameterKey": "AuthenticationMode",                  "ParameterValue": "$AUTH_MODE"},
  {"ParameterKey": "NodeGroupName",                       "ParameterValue": "${CLUSTER_NAME}-nodes"},
  {"ParameterKey": "NodeInstanceType",                    "ParameterValue": "t3.medium"},
  {"ParameterKey": "NodeImageIdSSMParam",                 "ParameterValue": "/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2023/x86_64/standard/recommended/image_id"},
  {"ParameterKey": "NodeVolumeSize",                      "ParameterValue": "20"},
  {"ParameterKey": "NodeVolumeType",                      "ParameterValue": "gp3"},
  {"ParameterKey": "VpcId",                               "ParameterValue": "$VPC_ID"},
  {"ParameterKey": "Subnets",                             "ParameterValue": "$SUBNET_IDS"},
  {"ParameterKey": "KeyName",                             "ParameterValue": "eks-nodes-key"},
  {"ParameterKey": "NodeAutoScalingGroupMinSize",         "ParameterValue": "1"},
  {"ParameterKey": "NodeAutoScalingGroupMaxSize",         "ParameterValue": "3"},
  {"ParameterKey": "NodeAutoScalingGroupDesiredCapacity", "ParameterValue": "3"}
]
EOF
```

!!! note ""

    This heredoc uses an **unquoted** `EOF` so the shell expands the `$VAR` references captured in Step 2 and Step 3B.1 (`CLUSTER_NAME`, `CLUSTER_SG`, `API_SERVER`, `CA_DATA`, `SERVICE_CIDR`, `AUTH_MODE`, `K8S_VERSION`, `VPC_ID`, `SUBNET_IDS`). Make sure they are all still set in your current shell — re-run the capture commands if you opened a new terminal. After writing the file, `cat /tmp/cf-params.json` to confirm every value resolved and none are blank.

##### Step 4B — Launch the Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM
```

!!! note "Joining is simpler on Track B"

    Because you pass `AuthenticationMode` into the template, the AL2023 template wires up node access for you when the cluster is in `API` or `API_AND_CONFIG_MAP` mode — in those cases the stack `Outputs` step is the last step and you can skip the manual mapping in Step 5. Only `CONFIG_MAP`-mode clusters still need the `aws-auth` step. The Step 5 branch below still applies as a fallback if nodes do not register.

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

The stack creates the EC2 instances and their IAM instance role, but the nodes will return `Unauthorized` from the API server until the **node IAM role is mapped to Kubernetes RBAC**. How you map it depends on the cluster's **authentication mode** — get the node role ARN, then check the mode:

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

echo "Authentication mode: $AUTH_MODE"
```

!!! important ""

    This is the single most common failure point. If `AUTH_MODE` is `API`, the `aws-auth` ConfigMap is **completely ignored** — applying it appears to succeed (`configmap/aws-auth created`) but nodes still get `Unauthorized` forever. Match the path below to your mode.


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

    `eks:CreateAccessEntry` may itself be restricted by the lab SCP. If it returns `AccessDeniedException`, you cannot use this path — recreate the cluster with `authenticationMode: API_AND_CONFIG_MAP` (see "Create the EKS Cluster" above) and then use Path 2. Verify with the simulator:

    ```bash
    aws iam simulate-principal-policy \
      --policy-source-arn arn:aws:iam::<account-id>:user/<lab-username> \
      --action-names eks:CreateAccessEntry \
      --resource-arns arn:aws:eks:us-east-1:<account-id>:cluster/<cluster-name>
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

## Troubleshooting

If `kubectl get nodes` returns `No resources found`:

This is **not** a timing issue and waiting longer will not help — it means the nodes are being rejected by the API server, almost always an authentication-mode/identity-mapping problem from Step 5.

1. Re-check the mode: `aws eks describe-cluster --name <cluster-name> --query "cluster.accessConfig.authenticationMode" --output text`. If it is `API`, the aws-auth ConfigMap is being ignored — switch to Path 1.

2. SSH (or SSM) onto a node and inspect kubelet:

```bash
sudo journalctl -u kubelet --no-pager | tail -30
```

Repeated `"Unable to register node with API server" err="Unauthorized"` confirms the role mapping is the problem, not bootstrap.

3. Confirm the node is assuming the role you mapped:

```bash
curl -s http://169.254.169.254/latest/meta-data/iam/info
```

The `InstanceProfileArn` must trace back to the node role from the CloudFormation stack output. A mismatch (e.g., a stale launch template) produces identical `Unauthorized` symptoms even with a perfect mapping.

4. **Track B (AL2023) only:** nodes initialize via `nodeadm`, not `bootstrap.sh`, so the cloud-init log looks different. If nodes never appear *and* kubelet logs do **not** show `Unauthorized`, the likely cause is missing or wrong `nodeadm` metadata — verify `ApiServerEndpoint`, `CertificateAuthorityData`, and `ServiceCidr` in your params file matched the cluster. Inspect the node's bootstrap with:

```bash
sudo journalctl -u nodeadm-config -u nodeadm-run --no-pager | tail -40
```

---

## Node Group Decision Matrix

| Method                                                   | Supported | Notes                                        |
| -------------------------------------------------------- | --------- | -------------------------------------------- |
| Managed node group (Console)                             | ❌         | `eks:CreateNodegroup` blocked by SCP         |
| Managed node group (eksctl)                              | ❌         | Same SCP block via CloudFormation            |
| Managed node group (AWS CLI)                             | ❌         | Same SCP block                               |
| Managed node group (Terraform `aws_eks_node_group`)      | ❌         | Same SCP block                               |
| **Self-managed nodes (CloudFormation, AL2 template)**    | ⚠️         | Only where an AL2 AMI still exists; AL2 is EOL (Track A) |
| **Self-managed nodes (CloudFormation, AL2023 template)** | ✅         | Current template — recommended (Track B)     |
| **Self-managed nodes via retail-store Terraform module** | ✅         | Supported — pre-authorized execution context |

---

## Authentication Mode Quick Reference

| `authenticationMode`  | aws-auth ConfigMap | Access entries | Node join path |
| --------------------- | ------------------ | -------------- | -------------- |
| `CONFIG_MAP`          | ✅ honored          | ❌ unavailable  | Path 2 (aws-auth) |
| `API_AND_CONFIG_MAP`  | ✅ honored          | ✅ available    | Either path    |
| `API` (current default) | ❌ **ignored**   | ✅ required     | Path 1 (access entry) |
