# Deploy ExternalDNS on EKS

ExternalDNS automatically creates and manages Route53 DNS records from Kubernetes `Gateway`, `HTTPRoute`, `Service`, and `Ingress` resources. When a `Gateway` is assigned an ALB address or a `Service` receives a `LoadBalancer` hostname, ExternalDNS reads the declared hostname and writes the corresponding A or CNAME record in Route53. No manual Route53 edits are needed after the initial setup.

ExternalDNS supports two IAM binding methods for pod credentials:

- **Method A — EKS Pod Identity**
- **Method B — IRSA (IAM Roles for Service Accounts)**

Both methods grant AWS credentials to the `external-dns` pod at runtime. Use one method only for a given installation.

---

## Official Sources

| Resource | URL |
|---|---|
| ExternalDNS GitHub | https://github.com/kubernetes-sigs/external-dns |
| AWS tutorial (official) | https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md |
| ArtifactHub (chart) | https://artifacthub.io/packages/helm/external-dns/external-dns |
| EKS IRSA guide | https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html |

Check ArtifactHub for the latest chart version before installing. The `--version` flag in the commands below pins the chart to a specific release; replace it with the required version when standardizing on a newer chart release.

---

## How ExternalDNS Works

```text
Gateway / HTTPRoute / Service
  (hostname: app.example.com declared in spec)
          │
          ▼
    ExternalDNS pod
    watches these resources via the Kubernetes API
          │
          ▼
    AWS Route53
    CREATE / UPDATE A or CNAME record:
    app.example.com → <ALB DNS name>
```

ExternalDNS is a read-and-sync agent, not a proxy. It does not sit in the traffic path. It reads hostnames from Kubernetes resources and writes DNS records to Route53.

---

## Prerequisites

- An EKS cluster is running and `kubectl` is configured.
- The AWS Load Balancer Controller is deployed with `NLBGatewayAPI=true` and `ALBGatewayAPI=true` feature gates enabled.
- Gateway API CRDs are installed and a `Gateway` resource is provisioned.
- A Route53 hosted zone exists for the target domain.
- Helm is installed.
- `eksctl` is installed.

---

## Deployment Overview

Perform the installation in this order:

1. Set variables.
2. Create the IAM policy.
3. Create the namespace.
4. Choose one IAM binding method: Pod Identity or IRSA.
5. Add the Helm repository.
6. Install ExternalDNS.
7. Apply the Gateway API sources patch.
8. Verify pod health and Route53 updates.

---

## IAM Binding Methods

| Item | Method A: Pod Identity | Method B: IRSA |
|---|---|---|
| Pre-requisite component | `eks-pod-identity-agent` add-on | Cluster OIDC provider |
| Binding mechanism | EKS Pod Identity Association | IAM role + ServiceAccount annotation |
| ServiceAccount annotation required | No | Yes (`eks.amazonaws.com/role-arn`) |
| Helm credential flag required | No | Yes, when Helm creates the ServiceAccount |
| eksctl command | `eksctl create podidentityassociation` | `eksctl create iamserviceaccount` |
| IAM trust model | `pods.eks.amazonaws.com` | Cluster OIDC provider |

Use Pod Identity as the primary method where organizational standards prefer EKS-native pod credential delivery. Use IRSA where IAM roles for service accounts are the standard.

---

## Step 1 — Set Variables

```bash
export CLUSTER_NAME=<eks-cluster-name>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Verify:

```bash
echo "CLUSTER_NAME : $CLUSTER_NAME"
echo "ACCOUNT_ID   : $ACCOUNT_ID"
```

---

## Step 2 — Create the IAM Policy

Create the policy document file:

```bash
cat > policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
```

Create the policy in IAM:

```bash
aws iam create-policy \
  --policy-name AllowExternalDNSUpdates \
  --policy-document file://policy.json
```

Export the ARN:

```bash
export POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' \
  --output text)

echo "POLICY_ARN : $POLICY_ARN"
```

---

## Step 3 — Create the Namespace

```bash
kubectl create namespace external-dns
```

---

## Step 4A — Configure Pod Identity (Method A)

Install the Pod Identity Agent if it is not already present:

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
eksctl create addon \
  --cluster $CLUSTER_NAME \
  --name eks-pod-identity-agent
```

Create the Pod Identity Association:

```bash
eksctl create podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --service-account-name external-dns \
  --role-name external-dns-pod-identity-role \
  --permission-policy-arns $POLICY_ARN
```

Verify the association:

```bash
eksctl get podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns
```

When using Pod Identity, do not add any `eks.amazonaws.com/role-arn` annotation in Helm values. Credentials are injected by the Pod Identity Agent.

---

## Step 4B — Configure IRSA (Method B)

Create the IAM service account:

```bash
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --name external-dns \
  --attach-policy-arn $POLICY_ARN \
  --role-name external-dns-irsa-role \
  --override-existing-serviceaccounts \
  --approve
```

Export the role ARN:

```bash
export ROLE_ARN=$(aws iam get-role \
  --role-name external-dns-irsa-role \
  --query 'Role.Arn' \
  --output text)

echo "ROLE_ARN : $ROLE_ARN"
```

The `eksctl create iamserviceaccount` command creates or updates the Kubernetes ServiceAccount and adds the `eks.amazonaws.com/role-arn` annotation by default unless `--role-only` is used.

---

## Step 5 — Add the Helm Repository

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns
```

---

## Step 6A — Install ExternalDNS with Pod Identity

```bash
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0
```

Use the chart default ServiceAccount behavior for Pod Identity. Do not pass any IAM role annotation in Helm values.

---

## Step 6B — Install ExternalDNS with IRSA

Use IRSA when IAM roles for service accounts are the credential mechanism.

### Pattern 1 — Helm creates the ServiceAccount (optional)

Use this pattern when Helm manages the ServiceAccount lifecycle:

```bash
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

Helm creates the ServiceAccount and writes the IRSA annotation based on the provided role ARN.

### Pattern 2 — Reuse eksctl-managed ServiceAccount (recommended)

Use this pattern when `eksctl create iamserviceaccount` already created and annotated the `external-dns` ServiceAccount:

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns
```

Helm reuses the existing ServiceAccount and does not attempt to create or modify it. Do not pass `serviceAccount.annotations` in Helm when reusing an existing annotated ServiceAccount.

---

## Step 7 — Apply the Gateway API Sources Patch

The chart default `sources` list contains only `service` and `ingress`. Add the Gateway API sources explicitly.

Create the patch file:

```bash
mkdir -p helm-values/external-dns

cat <<'EOF' > helm-values/external-dns/sources-patch.yaml
sources:
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
  - gateway-tcproute
  - gateway-udproute
EOF
```

### 7A — Apply patch with Pod Identity

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml
```

### 7B — Apply patch with IRSA (Pattern 1 — Helm creates ServiceAccount)

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
```

### 7C — Apply patch with IRSA (Pattern 2 — reuse eksctl-managed ServiceAccount, recommended)

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns
```

Helm deep-merges the patch file with the chart defaults. Only the `sources` key is replaced; everything else remains at its chart default.

---

## Step 8 — Verify DNS Record Creation

Follow ExternalDNS logs and confirm detection of hostnames and Route53 changes:

```bash
kubectl logs -n external-dns deploy/external-dns --follow
```

Look for lines similar to:

```text
time="..." level=info msg="Desired change: CREATE app.example.com A [Id: /hostedzone/ZXXXXX]"
time="..." level=info msg="2 record(s) in zone example.com. were successfully updated"
```

Confirm the record in Route53:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <HOSTED_ZONE_ID> \
  --query "ResourceRecordSets[?Name=='app.example.com.']"
```

Confirm DNS resolution:

```bash
nslookup app.example.com
dig app.example.com
```

---

## Quick Sequence

### Pod Identity (Method A)

```bash
export CLUSTER_NAME=silver-stack-eks
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZones"],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name AllowExternalDNSUpdates \
  --policy-document file://policy.json

export POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' \
  --output text)

kubectl get daemonset -n kube-system eks-pod-identity-agent
eksctl create addon --cluster $CLUSTER_NAME --name eks-pod-identity-agent

kubectl create namespace external-dns

eksctl create podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --service-account-name external-dns \
  --role-name external-dns-pod-identity-role \
  --permission-policy-arns $POLICY_ARN

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns

mkdir -p helm-values/external-dns
cat <<'EOF' > helm-values/external-dns/sources-patch.yaml
sources:
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
  - gateway-tcproute
  - gateway-udproute
EOF

helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml

sleep 15

kubectl logs -n external-dns deploy/external-dns
```

### IRSA (Method B, recommended Pattern 2)

```bash
export CLUSTER_NAME=silver-stack-eks
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResources"
      ],
      "Resource": ["arn:aws:route53:::hostedzone/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["route53:ListHostedZones"],
      "Resource": ["*"]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name AllowExternalDNSUpdates \
  --policy-document file://policy.json

export POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' \
  --output text)

kubectl create namespace external-dns

eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --name external-dns \
  --attach-policy-arn $POLICY_ARN \
  --role-name external-dns-irsa-role \
  --override-existing-serviceaccounts \
  --approve

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns

mkdir -p helm-values/external-dns
cat <<'EOF' > helm-values/external-dns/sources-patch.yaml
sources:
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
  - gateway-tcproute
  - gateway-udproute
EOF

helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns

sleep 15

kubectl logs -n external-dns deploy/external-dns
```
