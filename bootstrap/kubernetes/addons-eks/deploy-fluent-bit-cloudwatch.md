# Deploy Fluent Bit for CloudWatch Logging on EKS

Kubernetes has no built-in log storage. Container logs are written as JSON files
to `/var/log/pods/*.log` on each node. When a pod restarts those logs are lost.
When a node is replaced, they are gone permanently. A log shipping pipeline is
required to centralise, retain, and search logs across the cluster.

Kubernetes defines three levels of logging:

- **Basic** — `kubectl logs <pod>` reads the JSON log file on the node. Useful
  for quick debugging, not for retention.
- **Node-level** — the container runtime (containerd on EKS) captures `stdout`
  and `stderr` from every container and writes them to `/var/log/pods/*.log`.
  Kubelet and containerd write their own logs to `/var/log/` or to `journald`.
- **Cluster-level** — a log-capturing agent runs on every node as a DaemonSet.
  It tails the log files on the local filesystem and ships them to a centralised
  destination such as CloudWatch Logs.

---

## Why Fluent Bit

AWS officially recommends Fluent Bit as the log-shipping agent for EKS. It
replaced Fluentd in the AWS Container Insights stack for the following reasons:

| | Fluentd | Fluent Bit |
|---|---|---|
| Language | Ruby | C |
| Memory footprint | ~40 MB | ~1 MB |
| containerd support | Poor | Native |
| AWS recommendation | Deprecated | ✅ Current |

Fluent Bit runs as a **DaemonSet** — one pod per node. Each pod reads logs from
that node and ships them to CloudWatch under three log groups:

| Log Group | Contains | Source Path on Node |
|---|---|---|
| `/aws/containerinsights/<cluster>/application` | All container logs | `/var/log/containers/*.log` |
| `/aws/containerinsights/<cluster>/host` | Node OS logs (kernel, disk, network) | `/var/log/dmesg`, `/var/log/messages` |
| `/aws/containerinsights/<cluster>/dataplane` | Kubernetes control-plane logs | kubelet, kube-proxy, containerd journal |

!!! note
    AWS creates a log group only when the **first log event is received**. The
    log groups do not appear in the CloudWatch console until traffic reaches the
    pods or the node produces system events.

---

## Requirements

Ensure the following before starting:

- An EKS cluster is running and `kubectl` is configured.
- `eksctl` is installed.
- AWS CLI is installed and authenticated.
- The IAM OIDC provider is associated with the cluster.
- Access exists to create IAM policies and roles in the AWS account.

Set the following variables:

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

---

## Step 1 — Associate the IAM OIDC provider

Associate the EKS cluster with an IAM OIDC provider if not already done:

```bash
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster "$CLUSTER_NAME" \
  --approve
```

!!! note
    Treat this step as **optional** when the cluster was created with OIDC
    already enabled (for example, by Terraform or a manifest file). If an OIDC
    provider already exists for the cluster, this command prints a message and
    performs no changes.

---

## Step 2 — Create the `amazon-cloudwatch` namespace

All Fluent Bit Kubernetes resources live inside this namespace:

```bash
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
```

Verify:

```bash
kubectl get ns amazon-cloudwatch
```

---

## Step 3 — Create the ConfigMap `fluent-bit-cluster-info`

This ConfigMap is the runtime configuration Fluent Bit reads on startup. It
tells each pod which cluster to label the logs with, which AWS region to ship
to, and how to read the log files:

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
```

Each key in this ConfigMap controls a specific Fluent Bit behaviour:

| Key | Default | Purpose |
|---|---|---|
| `cluster.name` | `$CLUSTER_NAME` | Labels every log event with the cluster name in CloudWatch |
| `logs.region` | `$REGION` | CloudWatch Logs region endpoint Fluent Bit ships to |
| `http.server` | `On` | Exposes a Fluent Bit metrics endpoint (consumed by Prometheus) |
| `http.port` | `2020` | Port for the internal metrics HTTP server |
| `read.head` | `Off` | Do not read log files from the beginning — skip already-written content |
| `read.tail` | `On` | Start tailing from the latest position — avoids flooding CloudWatch with historical logs on first deploy |

Verify:

```bash
kubectl get configmap fluent-bit-cluster-info -n amazon-cloudwatch -o yaml
```

---

## Step 4 — Create the IAM policy

Fluent Bit needs permission to create log groups and streams in CloudWatch and
to push log events into them. Create the policy document:

```bash
cat <<'EOF' > fluentbit-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

Each action grants a specific capability:

| IAM Action | Why it is required |
|---|---|
| `logs:CreateLogGroup` | Creates `/aws/containerinsights/<cluster>/application` (and host, dataplane) on first log event |
| `logs:CreateLogStream` | Creates a stream per node inside each log group |
| `logs:PutLogEvents` | Writes the actual log lines into the stream |
| `logs:DescribeLogStreams` | Checks whether a stream already exists before attempting to create a duplicate |

Create the policy:

```bash
aws iam create-policy \
  --policy-name FluentBit-CloudWatch-Policy \
  --policy-document file://fluentbit-policy.json
```

---

## Step 5 — Create the IRSA ServiceAccount

Fluent Bit runs in the `amazon-cloudwatch` namespace. The ServiceAccount must
be named `fluent-bit` — this name is hardcoded in the DaemonSet manifest applied
in the next step:

```bash
eksctl create iamserviceaccount \
  --name fluent-bit \
  --namespace amazon-cloudwatch \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FluentBit-CloudWatch-Policy \
  --approve
```

This single command performs five things:

- Creates an IAM role with a trust policy scoped to the `fluent-bit`
  ServiceAccount in `amazon-cloudwatch` via the cluster OIDC provider
- Attaches `FluentBit-CloudWatch-Policy` to that IAM role
- Creates (or updates) the `fluent-bit` Kubernetes ServiceAccount in
  `amazon-cloudwatch`
- Annotates the ServiceAccount with `eks.amazonaws.com/role-arn` so the pod
  identity webhook injects AWS credentials into each Fluent Bit pod at runtime
- Creates a CloudFormation stack that manages the lifecycle of the IAM role

Verify the annotation is present:

```bash
kubectl get sa fluent-bit -n amazon-cloudwatch -o yaml | grep role-arn
```

Expected output:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/eksctl-<cluster>-addon-iamserviceaccount-Role
```

---

## Step 6 — Deploy the Fluent Bit DaemonSet

Apply the official AWS Container Insights Fluent Bit manifest. This is the
central step — it places one Fluent Bit pod on every node in the cluster and
starts shipping logs to CloudWatch immediately:

```bash
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml
```

This manifest creates the following Kubernetes resources:

| Resource | Name | Purpose |
|---|---|---|
| `ServiceAccount` | `fluent-bit` | Reuses the IRSA-annotated account from Step 5 |
| `ClusterRole` | `fluent-bit-role` | Grants read access to pod metadata so logs can be enriched with namespace, pod name, and container name |
| `ClusterRoleBinding` | `fluent-bit-role-binding` | Binds the ClusterRole to the ServiceAccount |
| `ConfigMap` | `fluent-bit-config` | Contains the Fluent Bit pipeline: inputs (tail log files) → filters (enrich with k8s metadata) → outputs (CloudWatch) |
| `DaemonSet` | `fluent-bit` | Ensures exactly one Fluent Bit pod runs on every node |

---

## Step 7 — Verify the deployment

Confirm one Fluent Bit pod is running on each node:

```bash
kubectl get pods -n amazon-cloudwatch
```

Expected output (one pod per node):

```text
NAME                    READY   STATUS    RESTARTS   AGE
fluent-bit-4xkpz        1/1     Running   0          45s
fluent-bit-8nqtm        1/1     Running   0          45s
fluent-bit-rw72v        1/1     Running   0          45s
```

Inspect the Fluent Bit pipeline configuration:

```bash
kubectl describe configmap fluent-bit-config -n amazon-cloudwatch
```

Check pod logs to confirm CloudWatch output is active:

```bash
kubectl logs daemonset.apps/fluent-bit -n amazon-cloudwatch | tail -20
```

Look for lines confirming the CloudWatch output plugin has connected. The node
count in the DaemonSet should equal the number of nodes:

```bash
kubectl get daemonset fluent-bit -n amazon-cloudwatch
```

---

## Step 8 — Verify log groups in CloudWatch

Open the AWS Console → **CloudWatch → Log groups**. After a short delay the
following groups should appear:

```
/aws/containerinsights/<cluster>/application
/aws/containerinsights/<cluster>/host
/aws/containerinsights/<cluster>/dataplane
```

Use CloudWatch Logs Insights to query application logs:

```sql
fields @timestamp, @message, @logStream, @log
| sort @timestamp desc
| limit 2000
```

!!! warning
    Log groups are created only when the first log event is received. If they do
    not appear immediately, generate some pod traffic or wait a few minutes for
    the node to produce host-level events.

---

## Troubleshooting

### Fluent Bit pods are running but no log groups appear in CloudWatch

**Cause:** The `fluent-bit` ServiceAccount is missing the IRSA annotation, so
the pod cannot assume the IAM role and the AWS SDK silently rejects the
`PutLogEvents` call.

**Fix:** Confirm the annotation exists:

```bash
kubectl get sa fluent-bit -n amazon-cloudwatch -o yaml | grep role-arn
```

If the annotation is absent, re-run Step 5 with `--override-existing-serviceaccounts`:

```bash
eksctl create iamserviceaccount \
  --name fluent-bit \
  --namespace amazon-cloudwatch \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FluentBit-CloudWatch-Policy \
  --override-existing-serviceaccounts \
  --approve
```

Then restart the DaemonSet so pods pick up the new annotation:

```bash
kubectl rollout restart daemonset/fluent-bit -n amazon-cloudwatch
```

### Fluent Bit pod logs show `AccessDeniedException`

**Cause:** The IAM policy attached to the role does not include one of the
required CloudWatch actions.

**Fix:** Verify the policy is attached to the correct role:

```bash
aws iam list-attached-role-policies \
  --role-name $(kubectl get sa fluent-bit -n amazon-cloudwatch \
    -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | \
    awk -F/ '{print $NF}')
```

---

## Quick sequence

```bash
export CLUSTER_NAME=<eks-cluster-name>
export REGION=<region>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

```bash
# OIDC (skip if already associated)
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster "$CLUSTER_NAME" \
  --approve

# Namespace
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# ConfigMap
kubectl create configmap fluent-bit-cluster-info \
  --from-literal=cluster.name="$CLUSTER_NAME" \
  --from-literal=http.server="On" \
  --from-literal=http.port="2020" \
  --from-literal=read.head="Off" \
  --from-literal=read.tail="On" \
  --from-literal=logs.region="$REGION" \
  -n amazon-cloudwatch

# IAM policy
cat <<'EOF' > fluentbit-policy.json
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"],"Resource":"*"}]}
EOF

aws iam create-policy \
  --policy-name FluentBit-CloudWatch-Policy \
  --policy-document file://fluentbit-policy.json

# IRSA ServiceAccount
eksctl create iamserviceaccount \
  --name fluent-bit \
  --namespace amazon-cloudwatch \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FluentBit-CloudWatch-Policy \
  --approve

# DaemonSet
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml

# Verify
kubectl get pods -n amazon-cloudwatch
kubectl get daemonset fluent-bit -n amazon-cloudwatch
kubectl logs daemonset.apps/fluent-bit -n amazon-cloudwatch | tail -20
```
