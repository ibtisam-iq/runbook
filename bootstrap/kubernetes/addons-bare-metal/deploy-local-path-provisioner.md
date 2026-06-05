# Deploy Storage Provisioner on a Bare-Metal Kubernetes Cluster

## Overview

A **StorageClass** is a Kubernetes API object that defines how dynamic volume
provisioning works — which provisioner handles it, the reclaim policy, and
the binding mode. A StorageClass cannot provision itself; a **provisioner**
(an external controller deployed into the cluster) must exist first.

| Cluster Type         | Default StorageClass | Action Required                    |
|----------------------|----------------------|------------------------------------|
| minikube / kind      | `standard`           | None — ships pre-installed         |
| kubeadm (bare-metal) | None                 | Deploy local-path-provisioner      |
| EKS (AWS)            | `gp2` / `gp3`        | None — use `gp3` in PVC spec       |

!!! warning "kubeadm clusters have no StorageClass by default"
    A PVC deployed on a kubeadm cluster without a provisioner will stay in
    `Pending` indefinitely. No error is shown — it silently waits for a
    provisioner that never comes.

---

## Prerequisites

- A running kubeadm-bootstrapped cluster
- `kubectl` configured to communicate with the cluster
- All nodes show `Ready` status:

```bash
kubectl get nodes
```

---

## Step 1 — Deploy the Local Path Provisioner

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.35/deploy/local-path-storage.yaml
```

This creates the `local-path-storage` namespace, deploys the provisioner
controller, and automatically registers a StorageClass named `local-path`.

Verify both the provisioner pod and the StorageClass are ready:

```bash
kubectl -n local-path-storage get pods
kubectl get storageclass
```

Expected output:

```
NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      DEFAULT
local-path   rancher.io/local-path   Delete          WaitForFirstConsumer
```

!!! note "WaitForFirstConsumer is expected behavior"
    The `local-path` StorageClass uses `WaitForFirstConsumer` binding mode.
    A PersistentVolume is not created until a Pod that consumes the PVC is
    scheduled to a node. The PVC will show `Pending` until then — this is
    normal.

---

## Step 2 — (Optional) Set `local-path` as the Cluster Default

Perform this step only if workloads should use `local-path` automatically
when no `storageClassName` is specified in a PVC.

```bash
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
```

Verify:

```bash
kubectl get storageclass
```

The `local-path` entry should now show `(default)` in the NAME column.

!!! tip
    Only one StorageClass should be marked as default per cluster. If another
    StorageClass is already marked default, remove its annotation first:

    ```bash
    kubectl patch storageclass <existing-default> \
      -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
    ```

---

## Step 3 — Use `local-path` in a New PVC

Specify `storageClassName: local-path` explicitly in the PVC manifest:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>
  namespace: <namespace>
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Apply it:

```bash
kubectl apply -f <pvc-manifest>.yaml
```

---

## Step 4 — Fix a PVC Stuck in `Pending` (Existing Deployments)

!!! warning "storageClassName is immutable on a PVC"
    Once a PVC is created, `spec.storageClassName` cannot be patched or
    updated in place — Kubernetes will reject the request. The only way to
    fix a PVC with a wrong or missing StorageClass is to **delete and
    recreate** it.

### Option A — Imperative (delete and recreate with correct class)

```bash
# 1. Export the existing PVC spec
kubectl get pvc <pvc-name> -n <namespace> -o yaml > pvc-backup.yaml

# 2. Delete the stuck PVC
kubectl delete pvc <pvc-name> -n <namespace>

# 3. Edit pvc-backup.yaml — update storageClassName to local-path,
#    and remove the status block and auto-generated metadata fields
#    (resourceVersion, uid, creationTimestamp, annotations added by k8s)

# 4. Recreate the PVC
kubectl apply -f pvc-backup.yaml
```

### Option B — Declarative (Kustomize strategic merge patch)

A strategic merge patch updates specific fields in an existing manifest
without replacing the entire object. Create a patch file that overrides
only `storageClassName`:

```yaml
# overlays/<environment>/patch-storageclass.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>
  namespace: <namespace>
spec:
  storageClassName: local-path
```

Reference it in `kustomization.yaml`:

```yaml
patches:
  - path: patch-storageclass.yaml
    target:
      kind: PersistentVolumeClaim
      name: <pvc-name>
```

Apply the overlay:

```bash
kubectl apply -k overlays/<environment>/
```

!!! note "When to use which option"
    - Use **Option A** when you need to fix a PVC immediately on a live
      cluster without a Kustomize setup.
    - Use **Option B** when managing multi-environment deployments with
      Kustomize — the patch file is committed to Git and applied
      consistently across environments (bare-metal uses `local-path`,
      EKS uses `gp3`).

---

## Verify Final State

```bash
kubectl get pvc <pvc-name> -n <namespace>
```

Expected:

```
NAME         STATUS   VOLUME                                     CAPACITY   STORAGECLASS
<pvc-name>   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        local-path
```

!!! danger "STATUS remains Pending after recreation"
    If the PVC is still `Pending` after the provisioner is deployed and the
    correct StorageClass is set, run:

    ```bash
    kubectl describe pvc <pvc-name> -n <namespace>
    ```

    Check the `Events` section. A missing provisioner pod or a node
    scheduling issue will be reported there.
