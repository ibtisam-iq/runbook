# Deploy AWS Load Balancer Controller

Deploy the AWS Load Balancer Controller on an existing EKS cluster to manage AWS Application Load Balancers (ALB) and Network Load Balancers (NLB) for Kubernetes Ingress and `LoadBalancer` Services. The controller provisions and configures an ALB or NLB based on the Ingress definition and keeps it in sync with cluster resources.

The controller can be deployed in two ways:

- With **Helm charts**.
- With **Kubernetes manifests**.

This runbook uses the **Helm-based** deployment.

---

## Requirements

Ensure the following before starting:

- An EKS cluster is running and `kubectl` is configured.
- `eksctl` is installed.
- AWS CLI is installed and authenticated.
- Helm is installed.
- Access exists to create IAM policies and roles in the AWS account.

Set the following variables:

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)
```

!!! note
    `VPC_ID` is required for the Helm install. The controller cannot reliably discover the VPC from EC2 instance metadata (IMDS) in all EKS node configurations. Passing it explicitly avoids a startup crash.

---

## Step 1: Associate the IAM OIDC provider

Associate the EKS cluster with an IAM OIDC provider:

```bash
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster "$CLUSTER_NAME" \
  --approve
```

!!! note
    Treat this step as **optional** when the cluster is created with OIDC already enabled (for example, by Terraform or a manifest file). If the cluster already has an IAM OIDC provider, this command prints a message and performs no changes.

---

## Step 2: Create the IAM policy

Download the official IAM policy for the AWS Load Balancer Controller:

```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json
```

Create a customer-managed IAM policy from this file:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

This sequence performs the following:

- Adds a new **customer-managed** IAM policy named `AWSLoadBalancerControllerIAMPolicy` in the account
- Stores the policy document that grants permissions to manage ALBs, NLBs, target groups, listeners, security groups, and related resources
- Leaves the **Entities** list empty initially (no roles are attached yet); this is expected at this stage

---

## Step 3: Create the IAM role and ServiceAccount

Create the IAM role and the Kubernetes ServiceAccount for the controller with IRSA:

```bash
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --role-name aws-load-balancer-controller \
  --override-existing-serviceaccounts \
  --region $REGION \
  --approve
```

This command performs four things:

- Creates an IAM role named `aws-load-balancer-controller`
- Creates a trust policy on that role that allows the `aws-load-balancer-controller` ServiceAccount in `kube-system` to assume it via the cluster's OIDC provider
- Attaches the `AWSLoadBalancerControllerIAMPolicy` policy to this IAM role
- Creates (or updates) the `aws-load-balancer-controller` ServiceAccount in `kube-system` and adds the `eks.amazonaws.com/role-arn` annotation pointing to this IAM role

The `--override-existing-serviceaccounts` flag ensures that if a ServiceAccount with the same name already exists, its metadata (including the IRSA annotation) is updated instead of leaving it unchanged.

Check the ServiceAccount:

```bash
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
```

Expect to see an annotation similar to:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::$ACCOUNT_ID:role/aws-load-balancer-controller
```

---

## Step 4: Deploy the controller with Helm

Add the EKS charts repository and update it:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
```

Deploy the AWS Load Balancer Controller chart and reuse the existing ServiceAccount:

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set controllerConfig.featureGates.NLBGatewayAPI=true \
  --set controllerConfig.featureGates.ALBGatewayAPI=true \
  --version 1.14.0
```

This Helm release is configured as follows:

- `serviceAccount.create=false` prevents Helm from creating a new ServiceAccount; the release uses the ServiceAccount created by `eksctl`.
- `serviceAccount.name=aws-load-balancer-controller` selects that ServiceAccount explicitly.
- `clusterName="$CLUSTER_NAME"` passes the EKS cluster name so the controller can tag and manage AWS resources correctly.
- `region="$REGION"` passes the AWS region explicitly so the controller does not rely on IMDS for region discovery.
- `vpcId="$VPC_ID"` passes the VPC ID explicitly. Without this, the controller attempts to fetch the VPC from EC2 instance metadata, which can fail with a `context deadline exceeded` error in some EKS node configurations, causing a `CrashLoopBackOff`.
- `controllerConfig.featureGates.NLBGatewayAPI=true` enables the Gateway API support for Network Load Balancers.
- `controllerConfig.featureGates.ALBGatewayAPI=true` enables the Gateway API support for Application Load Balancers.

---

## Step 5: Verify the deployment

Check the controller deployment:

```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
```

A healthy deployment typically looks like:

```text
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           28s
```

Check the ServiceAccount and annotation:

```bash
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
```

Check the webhook service has endpoints:

```bash
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

Check controller logs for errors:

```bash
kubectl logs -n kube-system deploy/aws-load-balancer-controller
```

---

## Troubleshooting

### CrashLoopBackOff — failed to get VPC ID from instance metadata

**Symptom:**

```
{"level":"error","logger":"setup","msg":"unable to initialize AWS cloud",
"error":"failed to get VPC ID: failed to fetch VPC ID from instance metadata:
error in fetching vpc id through ec2 metadata: get mac metadata: operation error
ec2imds: GetMetadata, canceled, context deadline exceeded"}
```

**Cause:** The controller tries to discover the VPC ID by calling the EC2 Instance Metadata Service (IMDS). This can time out when:

- The node group has IMDS hop limit set to 1 (default for some launch templates), which blocks containerised processes from reaching the metadata endpoint.
- The node security group or network ACLs block the metadata IP (`169.254.169.254`).

**Fix:** Pass the VPC ID and region explicitly in the Helm install so the controller does not use IMDS for discovery:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set controllerConfig.featureGates.NLBGatewayAPI=true \
  --set controllerConfig.featureGates.ALBGatewayAPI=true \
  --version 1.14.0
```

---

## Quick sequence

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<eks-cluster-region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)
```

```bash
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster "$CLUSTER_NAME" \
  --approve

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --role-name aws-load-balancer-controller \
  --override-existing-serviceaccounts \
  --region $REGION \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set controllerConfig.featureGates.NLBGatewayAPI=true \
  --set controllerConfig.featureGates.ALBGatewayAPI=true \
  --version 1.14.0

kubectl get deploy -n kube-system aws-load-balancer-controller
kubectl get sa -n kube-system aws-load-balancer-controller
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | grep role-arn
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```
