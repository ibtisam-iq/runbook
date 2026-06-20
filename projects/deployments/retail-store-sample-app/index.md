# Deploying Retail Store Microservices on Amazon EKS

!!! info "What this runbook is"
    This is a complete operational record of deploying the **Retail Store Sample App**
    onto Amazon EKS cluster `ibtisam-iq-eks-cluster` (us-east-1, Kubernetes 1.34).
    It documents every infrastructure decision, command, and validation step taken —
    from IAM roles and CloudFormation node groups through Helmfile orchestration,
    EBS storage, ALB Ingress, AWS-managed databases, and observability.

---

## About the Application

The **Retail Store Sample App** is a deliberately polyglot microservices e-commerce
store, originally authored by the
[AWS Containers team](https://github.com/aws-containers/retail-store-sample-app)
and forked at
[ibtisam-iq/retail-store-sample-app](https://github.com/ibtisam-iq/retail-store-sample-app).

It models the kind of heterogeneous stack found in real-world platform engineering —
five independent services, five different runtimes, five different persistence backends.

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

## Phase 0 — Prerequisites & Environment Setup

!!! info "Lab Context"
    I executed this entire deployment inside [KodeKloud's AWS Playground](https://learn.kodekloud.com/user/playgrounds/playground-aws) — a time-boxed AWS environment with a real account, real services, but a restricted IAM user. No personal AWS account was used.

    Running EKS on this playground comes with non-trivial IAM permission gaps (e.g., no `iam:PassRole`, no `iam:PutRolePolicy` in some contexts). The workarounds for those restrictions are documented in a dedicated runbook: [EKS on KodeKloud AWS Playground →](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-aws-playground/)

### Dev Machine

I use [SilverStack Dev Machine](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7) — a custom root filesystem on iximiuz Labs, which I maintain with all DevOps tools pre-installed (`kubectl`, `eksctl`, `terraform`, `helm`, `helmfile`, `aws cli`, etc.). No local machine setup is required.

### Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     AKIA2UC3FDA33YOHSI62
# AWS Secret Access Key: <secret>
# Default region name:  us-east-1
# Default output format: json
```

### Clone Repo & Set Env Vars

```bash
git clone https://github.com/ibtisam-iq/retail-store-sample-app.git
cd retail-store-sample-app

CLUSTER_NAME=ibtisam-iq-eks-cluster
REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $ACCOUNT_ID   # 730335615031
```

---

## Phase 1 — IAM Roles for EKS Cluster via Terraform

!!! info "Why Terraform instead of eksctl?"
    The lab IAM user does not have `iam:PassRole` permission, which `eksctl create cluster` triggers internally when it creates and assigns roles. Creating the roles with Terraform beforehand — and then referencing them in `cluster.yaml` — avoids that permission entirely.

    For more information, see [Terraform Code for IAM Roles for EKS Cluster](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-aws-playground/)

### Write `main.tf`

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

resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_role.name
}
```

### Apply

```bash
terraform init
terraform apply -auto-approve
# Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

**Result:** `eksClusterRole` and `eksNodeRole` created with all required policy attachments.

---

## Phase 2 — EKS Control Plane via eksctl

### Write `cluster.yaml`

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ibtisam-iq-eks-cluster
  region: us-east-1
  version: "1.34"

iam:
  serviceRoleARN: arn:aws:iam::<account-id>:role/eksClusterRole
  withOIDC: false  # OIDC associated manually in the next step

accessConfig:
  authenticationMode: API_AND_CONFIG_MAP

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

!!! warning "No OIDC in cluster.yaml"
    `withOIDC: false` is intentional. Enabling OIDC in the cluster config causes `eksctl` to call `iam:PassRole` during cluster creation, which fails under the lab user's permissions. OIDC is associated manually after the cluster is up.

### Create Cluster

```bash
# Step 1: Create cluster (no OIDC, no role auto-attachment)
eksctl create cluster -f cluster.yaml
```

`eksctl` automatically provisioned:

- VPC with public/private subnets in `us-east-1d` and `us-east-1b`
- EKS addons: `vpc-cni`, `kube-proxy`, `coredns`, `metrics-server`
- kubeconfig saved to `~/.kube/config`

### Associate OIDC Provider

```bash
# Step 2: Associate OIDC provider manually
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve
# ✔  created IAM Open ID Connect provider for cluster "ibtisam-iq-eks-cluster"
```

---

## Phase 3 — Self-Managed Worker Nodes via CloudFormation

!!! info "Why Self-Managed Nodes?"
    Managed node groups are the standard way to run worker nodes in EKS, but they come with a catch:

    - **They create a full IAM role and attach it automatically**, which fails under the lab user's IAM permissions (no `iam:PassRole`).
    - **eksctl creates them behind the scenes**, which also triggers the same permission failure.

    To avoid these IAM permission issues, I created the roles manually in Phase 1 using Terraform, and now I'm bootstrapping the worker nodes myself using CloudFormation.

### Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name eks-nodes-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/eks-nodes-key.pem

chmod 400 ~/.ssh/eks-nodes-key.pem
```

### Collect Cluster Parameters

```bash
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

CLUSTER_SG=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

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
```

!!! tip "AUTH_MODE Translation"
    The AWS CF node template expects human-readable strings, not the API enum values. Translate before passing to CloudFormation:
    ```bash
    case "$AUTH_MODE" in
      API)                AUTH_MODE_PARAM="EKS API" ;;
      API_AND_CONFIG_MAP) AUTH_MODE_PARAM="EKS API and ConfigMap" ;;
      CONFIG_MAP)         AUTH_MODE_PARAM="ConfigMap" ;;
    esac
    # Result: AUTH_MODE_PARAM="EKS API and ConfigMap"
    ```

### Build CloudFormation Parameters File

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

### Deploy Node Stack

```bash
aws cloudformation create-stack \
  --stack-name eks-nodes-stack \
  --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2025-11-26/amazon-eks-nodegroup.yaml \
  --parameters file:///tmp/cf-params.json \
  --capabilities CAPABILITY_IAM

# Poll until complete
aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].StackStatus" \
  --output text
# CREATE_COMPLETE
```

### Join Nodes to Cluster (aws-auth ConfigMap)

```bash
NODE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name eks-nodes-stack \
  --query "Stacks[0].Outputs[?OutputKey=='NodeInstanceRole'].OutputValue" \
  --output text)

aws eks update-kubeconfig --region us-east-1 --name "$CLUSTER_NAME"

curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/aws-auth-cm.yaml

sed -i "s|<ARN of instance role (not instance profile)>|$NODE_ROLE_ARN|g" aws-auth-cm.yaml

kubectl apply -f aws-auth-cm.yaml
# configmap/aws-auth created
```

### Verify Nodes

```bash
kubectl get nodes
# NAME                              STATUS   ROLES    AGE   VERSION
# ip-192-168-105-165.ec2.internal   Ready    <none>   79s   v1.34.8-eks-3385e9b
# ip-192-168-112-206.ec2.internal   Ready    <none>   78s   v1.34.8-eks-3385e9b
# ip-192-168-88-246.ec2.internal    Ready    <none>   82s   v1.34.8-eks-3385e9b
```

![EKS Cluster Resources with Self-Managed Nodes](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/02-eks-cluster-resources-self-managed-nodes.png)

---

## Phase 4 — EKS Add-ons

### 4A — AWS Load Balancer Controller

!!! info "For more details, see: [Deploy AWS Load Balancer Controller](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-aws-load-balancer-controller/)

```bash
# 1. Download and create IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 2. Create IRSA (IAM Role for Service Account)
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --role-name aws-load-balancer-controller \
  --override-existing-serviceaccounts \
  --region $REGION \
  --approve

# 3. Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.14.0
```

#### Verify

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
# NAME                           READY   UP-TO-DATE   AVAILABLE
# aws-load-balancer-controller   2/2     2            2

kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
# eks.amazonaws.com/role-arn: arn:aws:iam::730335615031:role/aws-load-balancer-controller
```

---

### 4B — EBS CSI Driver

!!! info "For more details, see: [Install EBS CSI Driver](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/install-ebs-csi-driver/)"

```bash
# 1. Create IAM role only (no SA creation yet — addon creates it)
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)

# 2. Install addon
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE
```

!!! warning "SA annotation race condition"
    The addon creates `ebs-csi-controller-sa` asynchronously. Wait for it to appear before annotating — polling with `kubectl get deploy -n kube-system | grep ebs-csi` until `0/2` appears works, then annotate and restart.

```bash
# 3. Annotate SA and restart controller
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite

kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout status deployment ebs-csi-controller -n kube-system
# deployment "ebs-csi-controller" successfully rolled out
```

### Set gp3 as Default StorageClass

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
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

kubectl patch storageclass gp2 \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl get sc
# NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
# gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false
# gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true
```

---

## Phase 5 — ACM Certificate (TLS for Custom Domain)

```bash
export CERT_ARN=$(aws acm request-certificate \
  --domain-name retail-microservices.ibtisam-iq.com \
  --validation-method DNS \
  --region us-east-1 \
  --query CertificateArn \
  --output text)
echo $CERT_ARN
# arn:aws:acm:us-east-1:730335615031:certificate/f0afb980-b86d-47cd-beaf-e8494affd00a
```

### Get DNS Validation Record

```bash
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"
# {
#   "Name":  "_ab1c5499789efdc982a79ac4fa03a4ee.retail-microservices.ibtisam-iq.com.",
#   "Type":  "CNAME",
#   "Value": "_9d76931dd1cbceac5d14293b7463ce92.jkddzztszm.acm-validations.aws."
# }
```

!!! note "DNS Validation"
    I added the CNAME record to the `ibtisam-iq.com` DNS zone in Cloudflare. ACM polls until the record resolves, then marks the certificate as `ISSUED`.

```bash
# Block until ISSUED (usually ~10-15 min)
aws acm wait certificate-validated --certificate-arn $CERT_ARN --region us-east-1

aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 \
  --query "Certificate.Status"
# "ISSUED"
```

---

## Phase 6 — Application-Level AWS Resources

### 6A — DynamoDB Table for Cart Service

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Create table
aws dynamodb create-table \
  --table-name cart \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=customerId,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes '[{
    "IndexName": "idx_global_customerId",
    "KeySchema": [{"AttributeName": "customerId","KeyType": "HASH"}],
    "Projection": {"ProjectionType": "ALL"}
  }]'

# 2. Create IAM policy
cat > cart-dynamo-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllAPIActionsOnCart",
    "Effect": "Allow",
    "Action": "dynamodb:*",
    "Resource": [
      "arn:aws:dynamodb:us-east-1:$ACCOUNT_ID:table/cart",
      "arn:aws:dynamodb:us-east-1:$ACCOUNT_ID:table/cart/index/*"
    ]
  }]
}
EOF

aws iam create-policy \
  --policy-name cart-dynamo \
  --policy-document file://cart-dynamo-policy.json

# 3. Create IRSA for cart service account
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace cart \
  --name cart \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/cart-dynamo \
  --role-name dynamo-table-access-for-cart \
  --approve \
  --override-existing-serviceaccounts
```

---

### 6B — SQS Queue for Orders Service

```bash
# 1. Create queue
aws sqs create-queue --queue-name orders-events

SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/orders-events \
  --attribute-names QueueArn \
  --query "Attributes.QueueArn" \
  --output text)
echo $SQS_QUEUE_ARN
# arn:aws:sqs:us-east-1:730335615031:orders-events

# 2. Create IAM policy
cat > orders-sqs-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllAPIActionsOnOrdersQueue",
    "Effect": "Allow",
    "Action": ["sqs:CreateQueue","sqs:SendMessage","sqs:GetQueueAttributes","sqs:GetQueueUrl"],
    "Resource": "$SQS_QUEUE_ARN"
  }]
}
EOF

aws iam create-policy \
  --policy-name orders-sqs-policy \
  --policy-document file://orders-sqs-policy.json

# 3. Create IRSA for orders service account
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --namespace orders \
  --name orders \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/orders-sqs-policy \
  --role-name orders-to-sqs \
  --approve \
  --override-existing-serviceaccounts
```

---

### 6C — SNS Topic + Lambda for Order Notifications

!!! warning "IAM Constraint — Lambda created via Console"
    `iam:PassRole` and `iam:PutRolePolicy` were blocked for the lab user via CLI. The Lambda function and its event source mapping (SQS trigger) were created through the AWS Console. `AdministratorAccess` was attached to the Lambda execution role as a lab workaround.

```bash
# Create SNS topic
aws sns create-topic --name order-notifications
# TopicArn: arn:aws:sqs:$REGION:$ACCOUNT_ID:order-notifications

# Subscribe email endpoint
aws sns subscribe \
  --topic-arn arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications \
  --protocol email \
  --notification-endpoint contact@ibtisam-iq.com
# SubscriptionArn: pending confirmation
# → Confirm the subscription from the email inbox
```

```bash
# Create Lambda function
mkdir -p /tmp/lambda-fn && cat > /tmp/lambda-fn/lambda_function.py << 'EOF'
import json
import boto3

sns = boto3.client('sns')
TOPIC_ARN = "arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications"

def lambda_handler(event, context):
    for record in event['Records']:
        message = record['body']
        sns.publish(
            TopicArn=TOPIC_ARN,
            Message=f"Order confirmed: {message}"
        )
EOF

cd /tmp/lambda-fn && zip function.zip lambda_function.py

# Create trust policy
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create the role
aws iam create-role \
  --role-name orders-sqs-to-sns-role \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name orders-sqs-to-sns-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create inline policy
cat > /tmp/inline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:$REGION:$ACCOUNT_ID:orders-events"
    }
  ]
}
EOF

# Attach inline policy
aws iam put-role-policy \
  --role-name orders-sqs-to-sns-role \
  --policy-name sqs-sns-inline-policy \
  --policy-document file:///tmp/inline-policy.json  

# Wait a few seconds for IAM role to propagate
sleep 10

# create lambda function
aws lambda create-function \
  --function-name orders-sqs-to-sns \
  --runtime python3.14 \
  --role arn:aws:iam::$ACCOUNT_ID:role/orders-sqs-to-sns-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb:/tmp/lambda-fn/function.zip \
  --region $REGION  

# create event source mapping
aws lambda create-event-source-mapping \
  --function-name orders-sqs-to-sns \
  --event-source-arn arn:aws:sqs:$REGION:$ACCOUNT_ID:orders-events \
  --batch-size 10 \
  --region $REGION
```

#### Test the Pipeline

```bash
aws sqs send-message \
  --queue-url https://sqs.$REGION.$ACCOUNT_ID/orders-events \
  --message-body '{"orderId": "TEST-001", "item": "gadget", "qty": 2}' \
  --region $REGION
# MessageId: b9866851-d020-4463-88a2-4736b8e4b23a
# → Email received at contact@ibtisam-iq.com ✅
```

---

## Phase 7 — Microservices Deployment via Helmfile

### Install Helmfile & helm-diff

```bash
HELMFILE_VERSION=1.5.2
LINUX_ARCH=amd64

curl -L "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_${LINUX_ARCH}.tar.gz" \
  -o /tmp/helmfile.tar.gz
tar -xzf /tmp/helmfile.tar.gz -C /tmp
sudo mv /tmp/helmfile /usr/local/bin
sudo chmod +x /usr/local/bin/helmfile
rm /tmp/helmfile.tar.gz

helmfile --version
# helmfile version 1.5.2

helm plugin install https://github.com/databus23/helm-diff
# Installed plugin: diff
```

### Prepare Ingress Values for UI

Edit `src/ui/chart/values-alb-ingress.yaml` with the ACM cert ARN:

```yaml
service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health/liveness
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:730335615031:certificate/f0afb980-b86d-47cd-beaf-e8494affd00a
    alb.ingress.kubernetes.io/group.name: ecom-eks
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
  tls:
    hosts:
      - retail-microservices.ibtisam-iq.com
```

### Deploy All Services

```bash
helmfile -f helmfile/helmfile-eks.yaml apply
```

Helmfile deployed five Helm releases:

| Release | Namespace | Backend | Storage |
|---|---|---|---|
| `catalog` | `catalog` | MySQL 8.0 (StatefulSet) | gp3 PVC 1Gi |
| `cart` | `cart` | DynamoDB (IRSA-bound) | — |
| `orders` | `orders` | PostgreSQL 16.1 (StatefulSet) + SQS | gp3 PVC 1Gi |
| `checkout` | `checkout` | Redis 6.0-alpine | — |
| `ui` | `ui` | ALB Ingress (HTTPS) | — |

### Verify

```bash
# All pods running
kubectl get po -A

# PVCs bound
kubectl get pvc -A
# NAMESPACE   NAME                    STATUS   STORAGECLASS   CAPACITY
# catalog     data-catalog-mysql-0    Bound    gp3            1Gi
# orders      data-orders-postgresql-0 Bound   gp3            1Gi

# Ingress provisioned
kubectl get ingress -A
# NAMESPACE  NAME  CLASS  HOSTS                                    ADDRESS
# ui         ui    alb    retail-microservices.ibtisam-iq.com      k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com

# Add CNAME in DNS:
# retail-microservices.ibtisam-iq.com → k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com
```

### Validate HTTP→HTTPS Redirect & TLS

```bash
# HTTP should 301 redirect
curl -I http://retail-microservices.ibtisam-iq.com
# HTTP/1.1 301 Moved Permanently
# Location: https://retail-microservices.ibtisam-iq.com:443

# HTTPS should 200 OK
curl -I https://retail-microservices.ibtisam-iq.com
# HTTP/2 200
# content-type: text/plain;charset=UTF-8
```

---

## Phase 8 — Monitoring Stack (Prometheus + Grafana)

!!! note "For more details, see: [Deploy kube-prometheus-stack](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-kube-prometheus-stack)"

### Export Variables

```bash
export CERT_ARN=arn:aws:acm:us-east-1:730335615031:certificate/f0afb980-b86d-47cd-beaf-e8494affd00a
export ALB_GROUP_NAME=ecom-eks
export GRAFANA_HOST=grafana.ibtisam-iq.com
export PROMETHEUS_HOST=prometheus.ibtisam-iq.com
```

### Prepare Helm Values

```bash
mkdir -p helm-values/monitoring

# Grafana values
cat > helm-values/monitoring/grafana-values.yaml << 'EOF'
grafana:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/group.name: ${ALB_GROUP_NAME}
      alb.ingress.kubernetes.io/healthcheck-path: /api/health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - ${GRAFANA_HOST}
EOF

# Prometheus values
cat > helm-values/monitoring/prometheus-values.yaml << 'EOF'
prometheus:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/group.name: ${ALB_GROUP_NAME}
      alb.ingress.kubernetes.io/healthcheck-path: /-/healthy
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      - ${PROMETHEUS_HOST}
    paths:
      - pathType: Prefix
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
EOF

# Substitute env vars
envsubst < helm-values/monitoring/grafana-values.yaml    > helm-values/monitoring/grafana-values-rendered.yaml
envsubst < helm-values/monitoring/prometheus-values.yaml > helm-values/monitoring/prometheus-values-rendered.yaml
```

### Install Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 86.2.0 \
  --namespace monitoring \
  --create-namespace \
  -f helm-values/monitoring/grafana-values-rendered.yaml \
  -f helm-values/monitoring/prometheus-values-rendered.yaml
# STATUS: deployed
```

### Verify

```bash
kubectl get po -n monitoring
# NAME                                                   READY   STATUS
# alertmanager-prometheus-stack-kube-prom-alertmanager-0  2/2    Running
# prometheus-prometheus-stack-kube-prom-prometheus-0      2/2    Running
# prometheus-stack-grafana-7d4cdb7cd8-97wvs               3/3    Running
# prometheus-stack-kube-prom-operator-...                 1/1    Running
# prometheus-stack-kube-state-metrics-...                 1/1    Running
# prometheus-stack-prometheus-node-exporter-* (×3)        1/1    Running

# Add CNAME records in DNS:
# grafana.ibtisam-iq.com    → <same ALB DNS as retail-microservices>
# prometheus.ibtisam-iq.com → <same ALB DNS as retail-microservices>
```

!!! info "Shared ALB via Ingress Group"
    All three services (`ui`, `grafana`, `prometheus`) share a single ALB (`k8s-ecomeks-ca3679ea54`) through `alb.ingress.kubernetes.io/group.name: ecom-eks`. The ALB routes by Host header — no separate load balancer is provisioned per service.

---

## Phase 9 — CloudWatch Container Insights (Fluent Bit)

> Full reference: [Deploy Fluent Bit for CloudWatch](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/addons-eks/deploy-fluent-bit-cloudwatch)

### Create Namespace

```bash
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
# namespace/amazon-cloudwatch created
```

### Create ConfigMap

```bash
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off' || FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

kubectl create configmap fluent-bit-cluster-info \
  --from-literal=cluster.name="$CLUSTER_NAME" \
  --from-literal=http.server="${FluentBitHttpServer:-On}" \
  --from-literal=http.port="${FluentBitHttpPort:-2020}" \
  --from-literal=read.head="${FluentBitReadFromHead:-Off}" \
  --from-literal=read.tail="${FluentBitReadFromTail:-On}" \
  --from-literal=logs.region="$REGION" \
  -n amazon-cloudwatch
# configmap/fluent-bit-cluster-info created
```

### Create IAM Policy & IRSA

```bash
cat > fluentbit-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ],
    "Resource": "*"
  }]
}
EOF

aws iam create-policy \
  --policy-name FluentBit-CloudWatch-Policy \
  --policy-document file://fluentbit-policy.json

eksctl create iamserviceaccount \
  --name fluent-bit \
  --namespace amazon-cloudwatch \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/FluentBit-CloudWatch-Policy \
  --approve
```

### Attach Policy to Node Role

```bash
aws iam attach-role-policy \
  --role-name eks-nodes-stack-NodeInstanceRole-dUvoRmghNCrM \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/FluentBit-CloudWatch-Policy
```

### Deploy Fluent Bit DaemonSet

```bash
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml
```

### Verify

```bash
kubectl get pods -n amazon-cloudwatch
# NAME             READY   STATUS    RESTARTS   AGE
# fluent-bit-54dvp  1/1    Running   0          102s
# fluent-bit-lcd4x  1/1    Running   0          102s
# fluent-bit-mhrgd  1/1    Running   0          102s

kubectl get ds -n amazon-cloudwatch
# DESIRED  CURRENT  READY  UP-TO-DATE  AVAILABLE
# 3        3        3      3           3
```

**CloudWatch Log Groups created:**

| Log Group | Contents |
|---|---|
| `/aws/containerinsights/ibtisam-iq-eks-cluster/application` | Pod stdout/stderr logs |
| `/aws/containerinsights/ibtisam-iq-eks-cluster/dataplane` | Kubernetes control-plane component logs |
| `/aws/containerinsights/ibtisam-iq-eks-cluster/host` | Node-level OS and kernel logs |
| `/aws/lambda/orders-sqs-to-sns` | Lambda invocation logs |

![CloudWatch Container Insights Log Groups](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/05-cloudwatch-container-insights-log-groups.png)

---

## Phase 10 — End-to-End Validation

### ALB & Target Groups

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[].[LoadBalancerName,DNSName,State.Code]" \
  --output table
# k8s-ecomeks-ca3679ea54   k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com   active

aws elbv2 describe-target-groups \
  --query "TargetGroups[].[TargetGroupName,Port,Protocol]" \
  --output table
# k8s-monitori-promethe-7e40748f...   9090   HTTP  (Prometheus)
# k8s-monitori-promethe-5084c1bf...   3000   HTTP  (Grafana)
# k8s-ui-ui-c4951b805b               8080   HTTP  (UI)
```

All three target groups report `healthy` in the ALB console resource map.

![ALB Resource Map and Target Groups](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/03-alb-resource-map-and-target-groups.png)

### Application

```bash
curl https://retail-microservices.ibtisam-iq.com
# INCOMING TRANSMISSION — 23:47 UTC
# TO: FIELD AGENT | FROM: HEADQUARTERS, SUPPLIES DIVISION
# RE: GADGET REPOSITORY ACCESS
# Agent, welcome to the repository...
```

Browser: `https://retail-microservices.ibtisam-iq.com` → **"The most public Secret Shop"** ✅

![Retail Store Live over HTTPS](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/04-retail-store-live-over-https.png)

### DNS Resolution

```bash
nslookup retail-microservices.ibtisam-iq.com
# retail-microservices.ibtisam-iq.com → k8s-ecomeks-ca3679ea54-681063282.us-east-1.elb.amazonaws.com
# Addresses: 44.196.200.40, 3.216.252.243
```

### TLS Certificate

```bash
curl -Lv https://retail-microservices.ibtisam-iq.com 2>&1 | grep -E "subject|issuer|SSL"
# subject: CN=retail-microservices.ibtisam-iq.com
# issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M01
# SSL certificate verify ok.
# SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
```

### CloudFormation Stacks Summary

| Stack | Created | Status |
|---|---|---|
| `eksctl-ibtisam-iq-eks-cluster-cluster` | 2026-06-06 23:09 | ✅ CREATE_COMPLETE |
| `eks-nodes-stack` | 2026-06-06 23:25 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-kube-system-aws-load-balancer-controller` | 2026-06-06 23:33 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-kube-system-ebs-csi-controller-sa` | 2026-06-06 23:35 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-cart-cart` | 2026-06-06 23:44 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-orders-orders` | 2026-06-06 23:48 | ✅ CREATE_COMPLETE |
| `eksctl-...-iamserviceaccount-amazon-cloudwatch-fluent-bit` | 2026-06-07 01:17 | ✅ CREATE_COMPLETE |

![](https://raw.githubusercontent.com/ibtisam-iq/retail-store-sample-app/main/assets/01-cloudformation-eks-cluster-stack-create-complete.png)