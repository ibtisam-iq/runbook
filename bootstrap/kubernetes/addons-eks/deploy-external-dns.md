# Deploy ExternalDNS on EKS

ExternalDNS automatically creates and manages Route53 DNS records from Kubernetes `Gateway`, `HTTPRoute`, `Service`, and `Ingress` resources. When a `Gateway` is assigned an ALB address or a `Service` receives a `LoadBalancer` hostname, ExternalDNS reads the declared hostname and writes the corresponding A or CNAME record in Route53 — no manual Route53 edits are needed after the initial setup.

This runbook uses **EKS Pod Identity** for IAM binding, not IRSA. The two methods accomplish the same goal — granting a pod AWS credentials at runtime — but through different mechanisms. Pod Identity requires no ServiceAccount annotation and no credential-related flags in the Helm install.

---

## Official Sources

| Resource | URL |
|---|---|
| ExternalDNS GitHub | https://github.com/kubernetes-sigs/external-dns |
| AWS tutorial (official) | https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md |
| ArtifactHub (chart) | https://artifacthub.io/packages/helm/external-dns/external-dns |

Always check ArtifactHub for the latest chart version before installing. The `--version` flag in every command below pins the chart to a specific release; replace it with the current version if a newer one is available.

---

## How ExternalDNS Works

```
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

ExternalDNS is a **read-and-sync agent**, not a proxy. It does not sit in the traffic path. It only reads hostnames from Kubernetes resources and writes DNS records to Route53. Route53 then resolves those hostnames to the ALB address so that traffic reaches the cluster.

---

## Prerequisites

- An EKS cluster is running and `kubectl` is configured.
- The AWS Load Balancer Controller is deployed with `NLBGatewayAPI=true` and `ALBGatewayAPI=true` feature gates enabled.
- Gateway API CRDs are installed and a `Gateway` resource is provisioned.
- A Route53 hosted zone exists for the target domain.
- Helm is installed.
- `eksctl` is installed.

See [deploy-aws-load-balancer-controller.md](./deploy-aws-load-balancer-controller.md) and [deploy-gateway-api.md](./deploy-gateway-api.md) before proceeding.

---

## Deployment Overview

The installation follows these steps in order:

1. **Set variables** — export `CLUSTER_NAME` and `ACCOUNT_ID`.
2. **Create the IAM policy** — `AllowExternalDNSUpdates` grants Route53 read/write permissions.
3. **Install the Pod Identity Agent** — `eks-pod-identity-agent` DaemonSet; skip if already present on the cluster.
4. **Create the namespace** — `external-dns` namespace scopes the Pod Identity Association.
5. **Create the Pod Identity Association** — binds `external-dns` ServiceAccount in `external-dns` namespace to the IAM role; replaces the IRSA `iamserviceaccount` + annotation pattern entirely.
6. **Install ExternalDNS via Helm** — plain install, no credential flags required.
7. **Apply the Gateway API sources patch** — a thin override file adds `gateway-httproute` and related sources so ExternalDNS watches `HTTPRoute` and `Gateway` resources in addition to `Service` and `Ingress`.
8. **Verify** — confirm the pod is running and Route53 records are being created.

!!! note "Pod Identity vs IRSA — side-by-side"
    | | IRSA | Pod Identity (this runbook) |
    |---|---|---|
    | **Pre-requisite component** | OIDC provider (cluster-level, usually already present) | `eks-pod-identity-agent` DaemonSet |
    | **Binding lives in** | IAM trust policy + ServiceAccount annotation | EKS Pod Identity Association object |
    | **ServiceAccount annotation** | `eks.amazonaws.com/role-arn: <ARN>` required | Not needed |
    | **Helm install credential flag** | `--set serviceAccount.annotations...` required | Not needed |
    | **eksctl command** | `eksctl create iamserviceaccount` | `eksctl create podidentityassociation` |
    | **Trust principal in IAM role** | OIDC issuer URL | `pods.eks.amazonaws.com` |
    | **Introduced** | EKS 2019 | EKS 2023 |

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

Export the ARN for use in Step 5:

```bash
export POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AllowExternalDNSUpdates`].Arn' \
  --output text)

echo "POLICY_ARN : $POLICY_ARN"
```

!!! note "Policy permissions"
    | Permission | Scope | Purpose |
    |---|---|---|
    | `route53:ChangeResourceRecordSets` | `hostedzone/*` | Create and update A/CNAME records |
    | `route53:ListResourceRecordSets` | `hostedzone/*` | Read existing records to avoid duplicates |
    | `route53:ListTagsForResources` | `hostedzone/*` | Filter zones by tag when `--aws-zone-tag-filter` is used |
    | `route53:ListHostedZones` | `*` | Discover all hosted zones in the account |

---

## Step 3 — Install the Pod Identity Agent

Check whether the agent DaemonSet is already present:

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
```

If the output shows a DaemonSet with `READY` matching `DESIRED`, skip to Step 4.

If absent, install it as an EKS managed add-on:

```bash
eksctl create addon \
  --cluster $CLUSTER_NAME \
  --name eks-pod-identity-agent
```

Verify all nodes have the agent running:

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

Expected output:

```text
NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
eks-pod-identity-agent   2         2         2       2            2
```

!!! note
    IRSA injects credentials via environment variables and a projected token volume directly into the pod spec — the Kubernetes API server handles this with no extra component. Pod Identity requires this agent DaemonSet on every node to intercept pod startups and inject credentials. This is the one additional component that IRSA-based runbooks (LBC, EBS CSI) do not require.

---

## Step 4 — Create the Namespace

```bash
kubectl create namespace external-dns
```

The Pod Identity Association in Step 5 is scoped to a specific namespace and ServiceAccount name. Both must match exactly what Helm creates at install time.

---

## Step 5 — Create the Pod Identity Association

This single command replaces the entire IRSA sequence (`eksctl create iamserviceaccount` + ServiceAccount annotation). It creates the IAM role with `pods.eks.amazonaws.com` as the trust principal, attaches the policy, and registers the EKS-level binding in one operation:

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

!!! note "IRSA equivalent for reference"
    The IRSA equivalent of this step is:
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
    With IRSA, the Helm install also requires an extra values block:
    ```yaml
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/external-dns-irsa-role
    ```
    Pod Identity requires neither the annotation nor any change to the Helm values for credentials.

---

## Step 6 — Add the Helm Repository

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns
```

---

## Step 7 — Install ExternalDNS

Install the chart. No credential flags are required — the Pod Identity Agent injects AWS credentials into the pod transparently at startup:

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

!!! note "IRSA equivalent Helm install"
    With IRSA, the install command would require an additional flag:
    ```bash
    helm install external-dns external-dns/external-dns \
      --namespace external-dns \
      --version 1.20.0 \
      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN
    ```
    With Pod Identity, the install above is complete as written.

---

## Step 8 — Apply the Gateway API Sources Patch

The chart default `sources` list contains only `service` and `ingress`. ExternalDNS ignores `HTTPRoute`, `TCPRoute`, `TLSRoute`, `UDPRoute`, and `Gateway` resources entirely unless those sources are explicitly added.

Create a thin patch file that overrides only the `sources` key and leaves all other chart defaults untouched:

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

Upgrade the release with the patch file:

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0 \
  -f helm-values/external-dns/sources-patch.yaml
```

Helm deep-merges the patch file with the chart defaults. Only the `sources` key is replaced; everything else remains at its chart default.

Verify the pod restarted and the new sources are active:

```bash
kubectl get pods -n external-dns
kubectl logs -n external-dns deploy/external-dns | grep "sources"
```

!!! note "Why Gateway API sources are not in chart defaults"
    ExternalDNS predates the Gateway API. The default `sources` list reflects the classic Kubernetes networking model (`Service`, `Ingress`). The gateway sources are opt-in. Without this patch, ExternalDNS never reads hostnames from `HTTPRoute` or `Gateway` objects and no DNS records are created for Gateway API-based applications.

---

## Step 9 — Verify DNS Record Creation

Follow ExternalDNS logs and confirm it is detecting hostnames and issuing Route53 changes:

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

## Upgrade

To upgrade to a newer chart version, re-run the upgrade command with the new version number. The patch file remains unchanged:

```bash
helm upgrade -i external-dns external-dns/external-dns \
  --namespace external-dns \
  --version <new-version> \
  -f helm-values/external-dns/sources-patch.yaml
```

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
kubectl get daemonset -n kube-system eks-pod-identity-agent
exsctl create addon --cluster $CLUSTER_NAME --name eks-pod-identity-agent

# Step 4: Namespace
kubectl create namespace external-dns

# Step 5: Pod Identity Association
eksctl create podidentityassociation \
  --cluster $CLUSTER_NAME \
  --namespace external-dns \
  --service-account-name external-dns \
  --role-name external-dns-pod-identity-role \
  --permission-policy-arns $POLICY_ARN

eksctl get podidentityassociation --cluster $CLUSTER_NAME --namespace external-dns

# Steps 6 & 7: Helm install
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update external-dns
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --version 1.20.0
kubectl get pods -n external-dns

# Step 8: Gateway API sources patch
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

# Step 9: Verify
kubectl get pods -n external-dns
kubectl logs -n external-dns deploy/external-dns | head -40
```
