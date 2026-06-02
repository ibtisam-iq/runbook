# Install EKS EBS CSI Driver

Install the Amazon EBS Container Storage Interface (CSI) driver to enable Kubernetes workloads on EKS to dynamically provision and manage EBS volumes as PersistentVolumes. Follow the sequence to create the IAM role, install the addon, apply the fallback workaround when `iam:PassRole` is unavailable, and verify the installation.

---

## Meet Prerequisites

Ensure the following prerequisites are in place before starting:

- An EKS cluster is running and `kubectl` is configured.
- `eksctl` is installed.
- AWS CLI is installed and authenticated.
- Access exists to create IAM roles and install EKS addons, or at minimum to create IAM roles and patch Kubernetes ServiceAccounts.

!!! note
    Treat `iam:PassRole` as a separate and mandatory IAM permission for the standard addon installation path. Without it, the `aws eks create-addon` command fails even when the IAM role itself exists.

---

## Export the Cluster Name

Export the cluster name as an environment variable:

```bash
export CLUSTER_NAME=<eks-cluster-name>
```

Verify the variable before continuing:

```bash
echo "$CLUSTER_NAME"
```

!!! warning
    Verify that `$CLUSTER_NAME` is not empty. If the variable is empty, AWS CLI returns the following error:

    ```text
    An error occurred (ParamValidation): argument --cluster-name: expected one argument
    ```

---

## Create the IAM Role

Run the following command:

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

This command creates the IAM role required by the EBS CSI driver. It configures the role for IRSA (IAM Roles for Service Accounts) so the Kubernetes ServiceAccount can later assume the role through the cluster OIDC provider.

| Flag | Purpose |
|------|---------|
| `--name ebs-csi-controller-sa` | Define the Kubernetes ServiceAccount name that will later use this role. |
| `--namespace kube-system` | Define the namespace where the controller runs. |
| `--cluster $CLUSTER_NAME` | Bind the trust relationship to the target cluster OIDC provider. |
| `--role-name AmazonEKS_EBS_CSI_DriverRole` | Assign a fixed IAM role name. |
| `--role-only` | Create only the IAM role. Do not create or annotate the Kubernetes ServiceAccount. |
| `--attach-policy-arn ...AmazonEBSCSIDriverPolicy` | Attach the AWS-managed policy required by the EBS CSI controller. |
| `--approve` | Apply immediately without prompting for confirmation. |

### Understand the role of `--role-only`

Use `--role-only` to stop `eksctl` from creating or modifying the Kubernetes ServiceAccount. Leave ServiceAccount creation to the EKS addon installation flow or to a manual patching step in the fallback path.

By default, `eksctl create iamserviceaccount` performs two actions:

1. Create the IAM role.
2. Create or update the Kubernetes ServiceAccount with the IAM role annotation.

With `--role-only`, perform only the first action.

!!! info
    Do not expect `ebs-csi-controller-sa` to appear immediately after this step. This command creates the IAM role only. It does not create the Kubernetes ServiceAccount.

---

## Check the addon versions

Check the supported addon versions for the cluster Kubernetes version:

```bash
eksctl utils describe-addon-versions --kubernetes-version 1.35 | grep AddonName
```

Replace `1.35` with the actual cluster version if required.

Check the cluster version with:

```bash
aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.version" --output text
```

---

## Install the addon with the IAM role ARN

Retrieve the IAM role ARN:

```bash
ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)
```

Install the addon with the role ARN:

```bash
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $ROLE_ARN \
  --configuration-values '{"defaultStorageClass":{"enabled":true}}'
```

This command installs the AWS-managed EBS CSI addon on the cluster and attach the previously created IAM role to the addon-managed ServiceAccount.

| Flag | Purpose |
|------|---------|
| `--cluster-name $CLUSTER_NAME` | Select the target EKS cluster. |
| `--addon-name aws-ebs-csi-driver` | Select the AWS-managed EBS CSI addon. |
| `--service-account-role-arn` | Pass the IAM role ARN created earlier. |
| `--configuration-values '{"defaultStorageClass":{"enabled":true}}'` | Enable creation of a default EBS-backed StorageClass. |

After successful completion, expect the following resources to appear:

- The EBS CSI controller deployment in `kube-system`.
- The `ebs-csi-controller-sa` ServiceAccount in `kube-system`.
- A default EBS-backed StorageClass.

!!! note
    Use this path only when the IAM caller has `iam:PassRole` permission on `AmazonEKS_EBS_CSI_DriverRole`.

---

## Apply the fallback workaround when `iam:PassRole` is unavailable

Use the fallback path when the environment does not allow adding the missing IAM permission, such as a third-party AWS playground or KodeKloud AWS playground. In that case, create the addon without passing the role ARN, then manually annotate the ServiceAccount and restart the controller.

### Recognize the failure

Expect the standard addon command to fail with an error similar to the following:

```text
AccessDeniedException: User ... is not authorized to perform: iam:PassRole on resource ... because no identity-based policy allows the iam:PassRole action
```

### Create the addon without the role ARN

Run the addon installation without `--service-account-role-arn`:

```bash
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --configuration-values '{"defaultStorageClass":{"enabled":true}}' \
  --resolve-conflicts "OVERWRITE"
```

Wait for the addon resources to appear.

### Annotate the ServiceAccount manually

Retrieve the IAM role ARN:

```bash
ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)
```

Annotate the ServiceAccount manually:

```bash
kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN \
  --overwrite
```

### Restart the controller

Restart the controller deployment so the pods pick up the new annotation:

```bash
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

Wait for the rollout to complete:

```bash
kubectl rollout status deployment ebs-csi-controller -n kube-system
```

!!! warning
    Use this workaround only when `iam:PassRole` cannot be granted. Prefer the standard addon installation path whenever the required IAM permission is available.

---

## Verify the installation

Check the addon state:

```bash
aws eks describe-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status"
```

Check the deployment and ServiceAccount:

```bash
kubectl get deploy -n kube-system | grep ebs-csi
kubectl get sa -n kube-system | grep ebs-csi-controller-sa
```

Check the StorageClass:

```bash
kubectl get storageclass
```

Confirm the ServiceAccount annotation:

```bash
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep role-arn
```

---

## Troubleshoot common failures

### Fix `iam:PassRole` failures

Use the fallback workaround section in environments where IAM policy changes are not possible. If IAM policy changes are possible, add `iam:PassRole` permission on `AmazonEKS_EBS_CSI_DriverRole` and use the standard addon installation path.

### Handle a missing ServiceAccount before addon installation

Treat this as expected behavior. The ServiceAccount is not created by the `eksctl create iamserviceaccount ... --role-only` command. The ServiceAccount appears only after addon installation, or after a manual creation path outside this runbook.

---

## Quick Run

```bash
export CLUSTER_NAME=<eks-cluster-name>
echo "$CLUSTER_NAME"
```

```bash
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

ROLE_ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query "Role.Arn" --output text)

aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $ROLE_ARN \
  --configuration-values '{"defaultStorageClass":{"enabled":true}}'

aws eks describe-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status"

kubectl get deploy -n kube-system | grep ebs-csi
kubectl get sa -n kube-system | grep ebs-csi-controller-sa
kubectl get storageclass
```

### Fallback for `iam:PassRole` failures

```bash
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --configuration-values '{"defaultStorageClass":{"enabled":true}}' \
  --resolve-conflicts "OVERWRITE"

kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN \
  --overwrite

kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout status deployment ebs-csi-controller -n kube-system

aws eks describe-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status"

kubectl get deploy -n kube-system | grep ebs-csi
kubectl get sa -n kube-system | grep ebs-csi-controller-sa
kubectl get storageclass
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep role-arn
```
