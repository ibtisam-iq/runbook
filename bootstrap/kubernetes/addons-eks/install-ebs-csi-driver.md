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
  --service-account-role-arn $ROLE_ARN
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

## Configure the Default StorageClass (gp2 → gp3)

After installing the EBS CSI driver, running `kubectl get sc` shows a `gp2` StorageClass that was never explicitly created:

```text
NAME   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2    kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  68m
```

This StorageClass is created automatically by EKS during cluster bootstrapping. It uses the **in-tree** EBS provisioner (`kubernetes.io/aws-ebs`), which is built into the Kubernetes node itself and does not require any CSI driver. AWS shipped this as the cluster default up through EKS 1.29.

This provisioner is deprecated. It does not support `gp3` volume types. To use `gp3`, create a new StorageClass backed by the modern CSI provisioner (`ebs.csi.aws.com`) and demote `gp2` from the default.

### gp2 vs gp3

| Feature | gp2 | gp3 |
|---|---|---|
| Provisioner | `kubernetes.io/aws-ebs` (in-tree, deprecated) | `ebs.csi.aws.com` (CSI, current standard) |
| Price | $0.10/GiB-month | $0.08/GiB-month (20% cheaper) |
| Baseline IOPS | 3 IOPS/GiB, minimum 100 (size-dependent) | 3,000 flat regardless of volume size |
| Max IOPS | 16,000 | 16,000 |
| Max throughput | 250 MiB/s | 1,000 MiB/s |
| IOPS tuning | Tied to volume size | Independent of size |
| `allowVolumeExpansion` | false (default) | true (configurable) |

The critical gp2 trap: a 10 GiB gp2 volume gets only 30 IOPS. A 10 GiB gp3 volume gets 3,000 IOPS at no extra cost.

### Create the gp3 StorageClass

Apply the following manifest to create a gp3 StorageClass using the CSI provisioner:

```bash
cat <<EOF | kubectl apply -f -
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
```

| Field | Value | Reason |
|---|---|---|
| `provisioner` | `ebs.csi.aws.com` | Uses the modern CSI driver, not the deprecated in-tree driver. |
| `parameters.type` | `gp3` | Selects the gp3 EBS volume type. |
| `volumeBindingMode` | `WaitForFirstConsumer` | Delays volume creation until a pod is scheduled, ensuring the EBS volume is created in the same AZ as the pod. |
| `allowVolumeExpansion` | `true` | Permits online volume resize without recreating the StorageClass later. |
| `is-default-class` | `"true"` | Makes gp3 the default for any PVC that does not specify a StorageClass. |

### Remove the default annotation from gp2

```bash
kubectl patch storageclass gp2 -p \
  '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
```

### Verify

```bash
kubectl get sc
```

Expect the following output:

```text
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                  80m
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   36s
```

!!! note
    Leave `gp2` in place. Deleting it can break workloads that reference `storageClassName: gp2` explicitly. Only remove it after confirming no PVCs depend on it.

Any new PVC that does not specify a `storageClassName` will now automatically provision a gp3 EBS volume with 3,000 IOPS baseline.

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
  --service-account-role-arn $ROLE_ARN

aws eks describe-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status"

sleep 15

kubectl get deploy -n kube-system | grep ebs-csi
kubectl get sa -n kube-system | grep ebs-csi-controller-sa
kubectl get storageclass
```

```bash
# Migrate default StorageClass from gp2 to gp3
cat <<EOF | kubectl apply -f -
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

kubectl patch storageclass gp2 -p \
  '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'

kubectl get sc
```

### Fallback for `iam:PassRole` failures

```bash
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts "OVERWRITE"

sleep 15

kubectl annotate serviceaccount ebs-csi-controller-sa \
  -n kube-system \
  eks.amazonaws.com/role-arn=$ROLE_ARN \
  --overwrite

kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout status deployment ebs-csi-controller -n kube-system

sleep 15

aws eks describe-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --query "addon.status"

kubectl get deploy -n kube-system | grep ebs-csi
kubectl get sa -n kube-system | grep ebs-csi-controller-sa
kubectl get storageclass
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep role-arn
```
