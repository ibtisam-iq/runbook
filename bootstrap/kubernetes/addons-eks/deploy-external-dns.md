# Deploy ExternalDNS on EKS

Deploy ExternalDNS on an EKS cluster to automatically create and manage Route53 DNS records from Kubernetes `Gateway`, `HTTPRoute`, `Service`, and `Ingress` resources. When a `Gateway` receives an ALB address or a `Service` gets a `LoadBalancer` IP, ExternalDNS reads the hostname and writes the corresponding A or CNAME record in Route53.

This runbook uses **Pod Identity** for IAM binding — not IRSA. The distinction matters for how the IAM role is created and how the Helm install is structured. Both methods produce the same end result (a pod with AWS credentials), but through completely different mechanisms.

!!! note "Why Pod Identity instead of IRSA?"
    | | IRSA | Pod Identity |
    |---|---|---|
    | **Pre-requisite component** | OIDC provider (usually already present) | `eks-pod-identity-agent` DaemonSet |
    | **Binding lives in** | IAM trust policy + ServiceAccount annotation | EKS Pod Identity Association object |
    | **ServiceAccount annotation needed** | `eks.amazonaws.com/role-arn: <ARN>` | None |
    | **Helm `values.yaml` change for credentials** | Yes — must add `serviceAccount.annotations` | No — Helm install is plain |
    | **eksctl command** | `eksctl create iamserviceaccount` | `eksctl create podidentityassociation` |
    | **Introduced** | EKS 2019 | EKS 2023 (newer) |

!!! note "Prerequisite"
    The AWS Load Balancer Controller must already be running with Gateway API feature gates enabled, and the `Gateway` resource must already be provisioned before ExternalDNS can pick up hostnames from it. See the [Deploy AWS Load Balancer Controller](./deploy-aws-load-balancer-controller.md) and [Deploy Gateway API](./deploy-gateway-api.md) runbooks.

---

## What ExternalDNS Does

```
Gateway / HTTPRoute / Service
  (hostname: app.example.com)
          │
          ▼
    ExternalDNS pod
    watches these resources
          │
          ▼
    AWS Route53
    creates / updates A or CNAME record:
    app.example.com → <ALB DNS name>
```

Without ExternalDNS, the ALB address is a long AWS-generated hostname. ExternalDNS is what maps your clean domain (`app.example.com`) to that address automatically, so you never have to touch Route53 manually after the first setup.

---

## Step 1: Set Variables

```bash
export CLUSTER_NAME=<eks-cluster-name>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Verify:

```bash
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "ACCOUNT_ID:   $ACCOUNT_ID"
```

---

## Step 2: Create the IAM Policy

Create the policy document. This grants ExternalDNS the minimum permissions it needs to read hosted zones and write DNS records in Route53:

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

Create the policy in AWS IAM:

```bash
aws iam create-policy \
  --policy-name AllowExternalDNSUpdates \
  --policy-document file://policy.json
```

Export the policy ARN for use in the next step:

```bash
export POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' \
  --output text)

echo "POLICY_ARN: $POLICY_ARN"
```

!!! note "Policy permissions explained"
    | Permission | Scope | Why |
    |---|---|---|
    | `route53:ChangeResourceRecordSets` | Hosted zones | Write A/CNAME records |
    | `route53:ListResourceRecordSets` | Hosted zones | Read existing records to avoid duplicates |
    | `route53:ListTagsForResources` | Hosted zones | Filter zones by tag if `--aws-zone-tag-filter` is used |
    | `route53:ListHostedZones` | All (`*`) | Discover which hosted zones exist in the account |

---

## Step 3: Install the Pod Identity Agent (if not already present)

Pod Identity requires an agent DaemonSet (`eks-pod-identity-agent`) running on every node. This agent intercepts pod startups and injects AWS credentials. Check whether it is already installed:

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
```

If the DaemonSet exists and is `READY`, skip to Step 4. If it is absent, install it as an EKS managed add-on:

```bash
eksctl create addon \
  --cluster $CLUSTER_NAME \
  --name eks-pod-identity-agent
```

Verify the DaemonSet is running on all nodes:

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

Expected output:

```text
NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
eks-pod-identity-agent   2         2         2       2            2
```

!!! note "Why this is not needed for IRSA"
    IRSA injects credentials via environment variables and a projected token volume directly into the pod spec — it is handled by the Kubernetes API server itself. Pod Identity requires an external agent running on the node to intercept and inject credentials at pod startup. That agent is what this step installs.

---

## Step 4: Create the Namespace

```bash
kubectl create namespace external-dns
```

ExternalDNS will run in this namespace. The Pod Identity Association created in the next step is scoped to this exact namespace and ServiceAccount name.

---

## Step 5: Create the Pod Identity Association

This single command replaces the entire IRSA flow (`eksctl create iamserviceaccount` + ServiceAccount annotation). It:

1. Creates an IAM role named `external-dns-pod-identity-role` with `pods.eks.amazonaws.com` as the trust principal
2. Attaches the `AllowExternalDNSUpdates` policy to that role
3. Creates an EKS-level Pod Identity Association binding `external-dns` namespace + `external-dns` ServiceAccount → this role

```bash
eksctl create podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --service-account-name external-dns \
  --role-name external-dns-pod-identity-role \
  --permission-policy-arns $POLICY_ARN
```

Verify the association was created:

```bash
eksctl get podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns
```

!!! note "IRSA equivalent for reference"
    If this were IRSA, the equivalent command would be:
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
    And then the Helm `values.yaml` would need:
    ```yaml
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/external-dns-irsa-role
    ```
    With Pod Identity, none of that annotation work is required.

---

## Step 6: Install ExternalDNS with Helm

Add the ExternalDNS Helm chart repository:

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns
```

Install the chart. No credential-related flags are needed — the Pod Identity Agent handles credential injection transparently at runtime:

```bash
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0
```

Verify the pod is running:

```bash
kubectl get pods -n external-dns
```

Expected output:

```text
NAME                            READY   STATUS    RESTARTS   AGE
external-dns-6f95d4687d-6tc2g   1/1     Running   0          94s
```

!!! note "Compare with IRSA Helm install"
    With IRSA, this same `helm install` would require an additional `--set` or `values.yaml` entry:
    ```bash
    helm install external-dns external-dns/external-dns \
      --namespace external-dns \
      --version 1.20.0 \
      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
    ```
    With Pod Identity, the install is plain — the agent injects credentials without the pod knowing anything about IAM.

---

## Step 7: Add Gateway API Sources

By default, ExternalDNS watches only `Service` and `Ingress` resources. This project uses Gateway API (`HTTPRoute`, `Gateway`), so the `sources` list must be extended.

Export the default values file for editing:

```bash
helm show values external-dns/external-dns --version 1.20.0 > external-dns-values-1.20.0.yaml
```

Edit the `sources` section in `external-dns-values-1.20.0.yaml`. Find the existing `sources` block and replace it with:

```yaml
sources:
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
  - gateway-tcproute
  - gateway-udproute
```

Upgrade the Helm release to apply the updated values:

```bash
helm upgrade -i external-dns external-dns/external-dns \
  -f external-dns-values-1.20.0.yaml \
  --namespace external-dns \
  --version 1.20.0
```

Verify the pod restarted with the new config:

```bash
kubectl get pods -n external-dns
kubectl logs -n external-dns deploy/external-dns | head -30
```

!!! note "Why Gateway API sources are not in the default values"
    ExternalDNS was built before Gateway API existed. The default `sources` list (`service`, `ingress`) reflects the classic Kubernetes networking model. `gateway-httproute` and the other gateway sources are opt-in additions that tell ExternalDNS to also watch `HTTPRoute`, `TCPRoute`, `TLSRoute`, and `UDPRoute` objects and extract hostnames from them. Without adding these, ExternalDNS completely ignores all `Gateway` and `HTTPRoute` resources — no DNS records are created for your application hostnames.

---

## Step 8: Verify DNS Record Creation

Check ExternalDNS logs to confirm it is reading hostnames and writing to Route53:

```bash
kubectl logs -n external-dns deploy/external-dns --follow
```

Look for log lines similar to:

```text
time="..." level=info msg="Desired change: CREATE app.example.com A [Id: /hostedzone/ZXXXXX]"
time="..." level=info msg="2 record(s) in zone example.com. were successfully updated"
```

Confirm the Route53 record exists in AWS:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <YOUR_HOSTED_ZONE_ID> \
  --query "ResourceRecordSets[?Name=='app.example.com.']"
```

Confirm DNS resolution from your machine:

```bash
nslookup app.example.com
# or
dig app.example.com
```

---

## Comparison: ExternalDNS IAM Binding Methods

| Step | IRSA method | Pod Identity method (this runbook) |
|---|---|---|
| **Create IAM policy** | Same — `aws iam create-policy` | Same — `aws iam create-policy` |
| **OIDC provider needed** | ✅ Yes | ❌ No |
| **Agent DaemonSet needed** | ❌ No | ✅ `eks-pod-identity-agent` |
| **Create IAM role + binding** | `eksctl create iamserviceaccount` | `eksctl create podidentityassociation` |
| **ServiceAccount annotation** | ✅ Required | ❌ Not needed |
| **Helm `values.yaml` change for IAM** | ✅ Add `serviceAccount.annotations` | ❌ None |
| **Helm `values.yaml` change for Gateway API** | ✅ Add gateway sources | ✅ Add gateway sources (same) |
| **Credential injection mechanism** | Kubernetes API (projected token + env vars) | Node agent (intercepted at pod startup) |

---

## Quick Sequence

```bash
# Variables
export CLUSTER_NAME=<eks-cluster-name>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Step 2: IAM policy
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

# Step 3: Pod Identity Agent (skip if already installed)
eksctl create addon --cluster $CLUSTER_NAME --name eks-pod-identity-agent
kubectl get daemonset -n kube-system eks-pod-identity-agent

# Step 4: Namespace
kubectl create namespace external-dns

# Step 5: Pod Identity Association
eksctl create podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --service-account-name external-dns \
  --role-name external-dns-pod-identity-role \
  --permission-policy-arns $POLICY_ARN

# Step 6: Helm install
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0
kubectl get pods -n external-dns

# Step 7: Add Gateway API sources
helm show values external-dns/external-dns --version 1.20.0 > external-dns-values-1.20.0.yaml
# Edit sources in external-dns-values-1.20.0.yaml (add gateway-httproute, gateway-tlsroute, etc.)
helm upgrade -i external-dns external-dns/external-dns \
  -f external-dns-values-1.20.0.yaml \
  --namespace external-dns \
  --version 1.20.0

# Step 8: Verify
kubectl get pods -n external-dns
kubectl logs -n external-dns deploy/external-dns | head -30
```
