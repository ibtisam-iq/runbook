# KodeKloud EKS Terraform — Challenges, Errors, and Fixes

!!! info "What this runbook is"
    A complete record of every error encountered while provisioning EKS on a
    KodeKloud AWS Playground account via Terraform, in the order they were hit.
    Each entry documents the exact error message, the root cause, and the exact
    fix applied. Nothing is hypothetical — every fix here was verified live.

    The working Terraform configuration produced by resolving all of these is
    documented in the companion runbook:
    [EKS on KodeKloud AWS Playground via Terraform →](./eks-on-kodekloud-terraform.md)

---

## Error Index

| # | Error | Category | Status |
|---|---|---|---|
| 1 | `logs:DeleteLogGroup` blocked on destroy | SCP / state | [Fix](#1-logsdeleteloggroup-blocked-on-destroy) |
| 2 | `ResourceAlreadyExistsException` on log group re-create | State | [Fix](#2-resourcealreadyexistsexception-on-log-group) |
| 3 | `Invalid count argument` on `aws_eks_cluster_versions` | Module bug | [Fix](#3-invalid-count-argument-on-aws_eks_cluster_versions) |
| 4 | `iam:TagPolicy` blocked on KMS policy creation | SCP | [Fix](#4-iamtagpolicy-blocked-on-kms-policy-creation) |
| 5 | `cluster_encryption_config` unsupported argument | Wrong variable name | [Fix](#5-wrong-variable-names-in-eks-module-v21x) |
| 6 | `encryption_config.0.provider.0.key_arn` required | Incomplete fix | [Fix](#6-encryption_config-key_arn-required) |
| 7 | `eks:CreateNodegroup` blocked | SCP | [Fix](#7-ekscreatenodegroup-blocked-unconditionally) |
| 8 | `eks:AssociateAccessPolicy` blocked | SCP | [Fix](#8-eksassociateaccesspolicy-blocked) |
| 9 | `eks:UpdateAccessEntry` blocked | SCP | [Fix](#9-eksupdateaccessentry-blocked) |
| 10 | `system:masters` invalid for STANDARD access entry | EKS restriction | [Fix](#10-systemmasters-invalid-for-standard-access-entry) |
| 11 | kubectl 403 Forbidden after access entry created | No RBAC | [Fix](#11-kubectl-403-forbidden) |
| 12 | kubectl 401 after taint deleted the access entry | No auth entry | [Fix](#12-kubectl-401-after-taint) |
| 13 | `eks:DeleteAddon` blocked on destroy | SCP | [Fix](#13-eksdeleteaddon-blocked-on-destroy) |
| 14 | CoreDNS addon hangs at `Still creating...` for 17+ min | Ordering issue | [Fix](#14-coredns-addon-hangs) |
| 15 | Stale state from expired lab session | Wrong account | [Fix](#15-stale-state-from-expired-lab-session) |
| 16 | `bootstrapClusterCreatorAdminPermissions` not working in module v21.x | Module bug | [Fix](#16-bootstrapclustercreatoradminpermissions-not-working) |
| 17 | AWS credentials not configured on bastion | Ops mistake | [Fix](#17-aws-credentials-not-configured-on-bastion) |

---

## 1. `logs:DeleteLogGroup` Blocked on Destroy

**When:** `terraform destroy` on the EKS module stack.

**Error:**

```
Error: deleting CloudWatch Logs Log Group (/aws/eks/microservices-demo-eks/cluster):
operation error CloudWatch Logs: DeleteLogGroup,
api error AccessDeniedException: User: arn:aws:iam::...:user/kk_labs_user_...
is not authorized to perform: logs:DeleteLogGroup
```

**Root cause:** The EKS module creates a CloudWatch log group for control-plane
logging. The KodeKloud SCP blocks `logs:DeleteLogGroup`. Terraform tries to delete
it on destroy and fails.

**Fix:**

Remove the resource from state so Terraform forgets about it, then retry destroy:

```bash
terraform state rm 'module.eks.aws_cloudwatch_log_group.this[0]'
terraform destroy
```

The log group remains in AWS (orphaned), but since KodeKloud playgrounds are
ephemeral accounts, this is harmless.

**Long-term fix:** In the raw-resource approach, the cluster creates its own log group
unmanaged by Terraform. Setting `create_cloudwatch_log_group = false` in the module
(when using it) prevents Terraform from ever managing it.

---

## 2. `ResourceAlreadyExistsException` on Log Group

**When:** `terraform apply` after removing the log group from state (fix for Error 1).

**Error:**

```
Error: creating CloudWatch Logs Log Group (/aws/eks/microservices-demo-eks/cluster):
ResourceAlreadyExistsException: The specified log group already exists
```

**Root cause:** The log group was removed from Terraform state (fix for Error 1)
but still exists in AWS. On the next apply, Terraform tries to create it again and
finds it already there.

**Fix:**

Import the existing log group back into state so Terraform recognizes it:

```bash
terraform import \
  'module.eks.aws_cloudwatch_log_group.this[0]' \
  '/aws/eks/microservices-demo-eks/cluster'

terraform apply
```

This is the import-then-sync cycle that happens whenever a resource escapes Terraform
management but the config still expects it.

---

## 3. `Invalid count argument` on `aws_eks_cluster_versions`

**When:** `terraform apply -target=module.eks` with EKS module v21.x and managed node groups.

**Error:**

```
Error: Invalid count argument
  on .terraform/modules/eks/modules/eks-managed-node-group/main.tf line 396,
  in data "aws_eks_cluster_versions" "this":
 396:   count = var.create && var.kubernetes_version == null ? 1 : 0

The "count" value depends on resource attributes that cannot be determined
until apply.
```

**Root cause:** The managed node group submodule inside the EKS module has a data
source whose `count` depends on whether `kubernetes_version` is set. When the cluster
doesn't exist yet (first apply), this attribute cannot be resolved during planning.
This is a known module v21.x issue.

**Fix:**

Apply in stages, targeting the cluster resource first:

```bash
# Stage 1: cluster only
terraform apply -target=module.eks.aws_eks_cluster.this[0]

# Stage 2: rest of EKS module
terraform apply -target=module.eks

# Stage 3: everything
terraform apply
```

**Long-term fix:** Removing `eks_managed_node_groups` from the module config
(which is required anyway because `eks:CreateNodegroup` is blocked) eliminates
this data source entirely.

---

## 4. `iam:TagPolicy` Blocked on KMS Policy Creation

**When:** `terraform apply` with the EKS module and default KMS encryption settings.

**Error:**

```
Error: creating IAM Policy (microservices-demo-eks-cluster-ClusterEncryption...):
operation error IAM: CreatePolicy,
api error AccessDenied: User: ...is not authorized to perform: iam:TagPolicy
```

**Root cause:** The EKS module v21.x enables KMS cluster encryption by default.
Creating the accompanying IAM policy for the cluster role to use the KMS key
requires `iam:TagPolicy`, which the KodeKloud SCP blocks.

**Fix:**

Disable all KMS encryption in the module:

```hcl
module "eks" {
  # ...
  create_kms_key           = false
  encryption_config        = null   # null, not {} — see Error 6
  attach_encryption_policy = false
}
```

---

## 5. Wrong Variable Names in EKS Module v21.x

**When:** Setting encryption variables copied from older module documentation.

**Error:**

```
Error: Unsupported argument
  on eks.tf line 58, in module "eks":
  58:   cluster_encryption_config = {}
An argument named "cluster_encryption_config" is not expected here.

Error: Unsupported argument
  on eks.tf line 59, in module "eks":
  59:   attach_cluster_encryption_policy = false
An argument named "attach_cluster_encryption_policy" is not expected here.
```

**Root cause:** Variable names changed between EKS module versions. The v21.x names
are `encryption_config` and `attach_encryption_policy`, not the v18.x/v19.x names.

**Fix:**

Grep the actual variable names from the downloaded module source:

```bash
grep -i 'variable.*kms\|variable.*encrypt' \
  .terraform/modules/eks/variables.tf
```

Use the names that appear in that output. For v21.x:

```hcl
create_kms_key           = false
encryption_config        = null
attach_encryption_policy = false
```

---

## 6. `encryption_config.0.provider.0.key_arn` Required

**When:** `terraform apply` after setting `encryption_config = {}` (empty map).

**Error:**

```
Error: Missing required argument
  with module.eks.aws_eks_cluster.this[0],
  on .terraform/modules/eks/main.tf line 36:
The argument "encryption_config.0.provider.0.key_arn" is required,
but no definition was found.
```

**Root cause:** Setting `encryption_config = {}` tells the module "configure
encryption but with no key." The cluster resource then requires a `key_arn` inside
the block. The module's `enable_encryption_config` local is:

```hcl
enable_encryption_config = var.encryption_config != null && ...
```

`{}` is not `null`, so the condition is `true` and the module generates a
`encryption_config` block on the `aws_eks_cluster` resource without a key ARN.

**Fix:**

Use `null` instead of `{}`:

```hcl
encryption_config = null  # null disables it; {} just makes it empty but still present
```

---

## 7. `eks:CreateNodegroup` Blocked Unconditionally

**When:** `terraform apply` with `eks_managed_node_groups` block in the EKS module.

**Root cause:** The KodeKloud SCP blocks `eks:CreateNodegroup` unconditionally —
AWS Console, eksctl, AWS CLI, and Terraform all receive `AccessDeniedException`.
There is no workaround for managed node groups.

**Verified blocked methods:**

```bash
# IAM policy simulator confirmation
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/kk_labs_user_XXXXXX \
  --action-names eks:CreateNodegroup \
  --resource-arns arn:aws:eks:us-east-1::$ACCOUNT_ID:cluster/microservices-demo-eks
# EvalDecision: implicitDeny
# AllowedByOrganizations: False
```

**Fix:**

Remove `eks_managed_node_groups` from the module entirely. Provision worker nodes
as self-managed via CloudFormation after the cluster is up. See Phase 4 of the
main runbook.

---

## 8. `eks:AssociateAccessPolicy` Blocked

**When:** Terraform apply with `enable_cluster_creator_admin_permissions = true`
in the EKS module.

**Error:**

```
Error: creating EKS Access Policy Association
(microservices-demo-eks#arn:aws:iam::...:user/kk_labs_user_...
#arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy):
api error AccessDeniedException: User: ...is not authorized to perform:
eks:AssociateAccessPolicy
```

**Root cause:** `enable_cluster_creator_admin_permissions = true` instructs the
module to: (1) create an access entry for the Terraform caller, then (2) associate
`AmazonEKSClusterAdminPolicy` with it via `eks:AssociateAccessPolicy`. Step 2 is
blocked by the SCP on every KodeKloud account tested.

**What does NOT work as a workaround:**

- `enable_cluster_creator_admin_permissions = false` with the EKS module: the module
  is supposed to set `bootstrap_cluster_creator_admin_permissions = true` instead,
  but v21.x silently drops this when `create_iam_role = false`. See Error 16.
- Manual `aws eks associate-access-policy` CLI call: same SCP block.

**Fix:**

Bypass the EKS module for the cluster resource entirely. Use a raw `aws_eks_cluster`
with `bootstrap_cluster_creator_admin_permissions = true` explicitly set in the
`access_config` block. EKS handles the admin entry internally at cluster creation
time without any `eks:AssociateAccessPolicy` call.

```hcl
resource "aws_eks_cluster" "this" {
  # ...
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}
```

---

## 9. `eks:UpdateAccessEntry` Blocked

**When:** Attempting to update an existing access entry to add `system:masters`
as a Kubernetes group.

**Error:**

```
An error occurred (AccessDeniedException) when calling the UpdateAccessEntry
operation: User: ...is not authorized to perform: eks:UpdateAccessEntry
```

**Root cause:** SCP blocks `eks:UpdateAccessEntry`. The access entry was created
(that operation works) but cannot be modified after creation.

**No workaround exists** for modifying existing access entries. The only path
forward is to recreate the cluster with correct settings from the start.

---

## 10. `system:masters` Invalid for STANDARD Access Entry

**When:** Attempting `aws eks create-access-entry --kubernetes-groups system:masters`.

**Error:**

```
An error occurred (InvalidParameterException) when calling the CreateAccessEntry
operation: The kubernetes group name system:masters is invalid,
it cannot start with system:
```

**Root cause:** EKS explicitly blocks the `system:` prefix for Kubernetes groups
on STANDARD type access entries. This is an EKS-level restriction, not an SCP
restriction. The `system:masters` group is reserved for Kubernetes internal use
and EKS prevents it from being assigned via the access entry API.

**Note:** `system:masters` IS valid in the `aws-auth` ConfigMap under `groups`.
The restriction only applies to the access entry API for STANDARD type entries.

**No workaround** for this specific path. The correct approach is Error 8's fix:
use `bootstrap_cluster_creator_admin_permissions = true` at cluster creation time.

---

## 11. kubectl 403 Forbidden

**When:** Running kubectl commands after the cluster is created but without
proper access configuration.

**Error:**

```
Error from server (Forbidden): nodes is forbidden:
User "arn:aws:iam::...:user/kk_labs_user_..." cannot list resource "nodes"
in API group "" at the cluster scope
```

**Root cause:** The lab user is authenticated (the access entry exists and the token
is valid) but has no Kubernetes RBAC permissions. This state occurs when:
- An access entry exists but no policy is associated (`eks:AssociateAccessPolicy` blocked)
- `bootstrapClusterCreatorAdminPermissions = false` (module dropped the setting)

403 = authenticated, unauthorized. Distinct from 401 (authentication failed entirely).

**Fix:**

This state requires cluster recreation. See Error 16 for the root cause and
permanent fix. In the interim, `aws eks create-access-entry` succeeds (the entry
creation is allowed) but the subsequent policy association always fails.

---

## 12. kubectl 401 After Taint Deleted the Access Entry

**When:** Running kubectl after a `terraform taint` partially destroyed the cluster's
dependencies (including the access entry) but failed before recreating them.

**Error:**

```
E0610 memcache.go:265 "Unhandled Error"
err="couldn't get current server API group list: the server has asked for the client
to provide credentials"
error: You must be logged in to the server (the server has asked for the client
to provide credentials)
```

**Root cause:** The `terraform taint` operation triggered a replacement sequence.
The access entry created in a previous apply was successfully deleted, but the
addon deletion failed (Error 13), aborting the taint before the cluster was
recreated. The cluster remained with:
- `bootstrapClusterCreatorAdminPermissions = false` (set at creation, cannot change)
- No access entry (deleted during taint)
- No aws-auth ConfigMap entries

401 = completely unrecognized identity. The API server has no record of this user.

**Fix:**

This state is unrecoverable without cluster recreation. The cluster's
`bootstrapClusterCreatorAdminPermissions` setting is create-time-only — it cannot
be changed via `UpdateClusterConfig`. Start a new KodeKloud lab session.

---

## 13. `eks:DeleteAddon` Blocked on Destroy

**When:** `terraform destroy` or `terraform taint` triggering addon deletion.

**Error:**

```
Error: deleting EKS Add-On (microservices-demo-eks:kube-proxy):
operation error EKS: DeleteAddon,
api error AccessDeniedException: User is not authorized to perform this action
```

Same error for `vpc-cni` and `eks-pod-identity-agent`.

**Root cause:** `eks:DeleteAddon` is blocked by the KodeKloud SCP. Any operation
that triggers Terraform to delete an EKS addon — `terraform destroy`, `terraform taint`
on the cluster, or removing the addon from config — will fail.

**Fix:**

Add `preserve = true` to every `aws_eks_addon` resource:

```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  preserve                    = true  # abandons the resource in state on destroy
}
```

With `preserve = true`, Terraform removes the resource from state on destroy
without calling the AWS API. The addon continues to exist in AWS (orphaned), which
is acceptable for ephemeral playground sessions.

---

## 14. CoreDNS Addon Hangs at `Still creating...`

**When:** Including `coredns` in the EKS module addons or as a raw `aws_eks_addon`
resource on a fresh cluster with no nodes.

**Symptom:**

```
module.eks.aws_eks_addon.this["coredns"]: Still creating... [10m51s elapsed]
module.eks.aws_eks_addon.this["coredns"]: Still creating... [11m01s elapsed]
...
module.eks.aws_eks_addon.this["coredns"]: Still creating... [17m01s elapsed]
[terraform hangs until 20-minute timeout, then fails]
```

**Root cause:** The `aws_eks_addon` resource polls until the addon reaches `Active`
status. CoreDNS stays `Degraded` until worker nodes exist to schedule its two pods.
On a fresh cluster with no nodes, CoreDNS is perpetually `Degraded`, and Terraform
waits the full 20-minute default timeout before failing.

**Fix:**

Exclude CoreDNS from Terraform entirely. EKS installs it automatically as a
built-in Kubernetes deployment. Once self-managed nodes join in Phase 4, CoreDNS
pods schedule and become `Running` on their own.

```hcl
# DO NOT add this — it will hang on first apply
# resource "aws_eks_addon" "coredns" { ... }

# CoreDNS is intentionally not declared here. EKS installs it automatically.
# It activates once self-managed nodes exist to schedule its pods.
```

The console will show CoreDNS as a running deployment even though it is not in
the addon management list — this is expected and correct.

---

## 15. Stale State from Expired Lab Session

**When:** Running `terraform plan` or `terraform apply` after starting a new
KodeKloud lab session with a new AWS account, without deleting the local state file.

**Error:**

```
Error: reading IAM OIDC Provider
(arn:aws:iam::533267240574:oidc-provider/...):
operation error IAM: GetOpenIDConnectProvider,
api error AccessDenied: User: arn:aws:iam::851725341232:user/kk_labs_user_...
is not authorized to access this resource
```

The plan output also shows the account ID changing:

```
~ aws_account_id = "533267240574" -> "851725341232"
```

**Root cause:** The `terraform.tfstate` file on disk still references all resources
from the previous lab session (account `533267240574`). With new credentials pointing
to a different account (`851725341232`), Terraform tries to refresh old-account
resources and fails.

**Fix:**

Delete the state file before applying in the new lab session:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
terraform apply
```

Terraform treats this as a fresh deployment and creates everything new in the
current account. Since KodeKloud playground resources are destroyed when the session
expires, deleting the state file only discards references to already-gone resources.

---

## 16. `bootstrapClusterCreatorAdminPermissions` Not Working in EKS Module v21.x

**When:** Using `enable_cluster_creator_admin_permissions = false` in the EKS module
with `create_iam_role = false`, expecting the module to set
`bootstrap_cluster_creator_admin_permissions = true` on the cluster.

**Symptom:** No visible Terraform error. The cluster is created successfully, but:

```bash
aws eks list-access-entries --cluster-name microservices-demo-eks
# Only shows the EKS service role — no entry for the lab user

aws eks describe-cluster --name microservices-demo-eks \
  --query "cluster.accessConfig"
# {"authenticationMode": "API_AND_CONFIG_MAP"}
# bootstrapClusterCreatorAdminPermissions field absent from response

kubectl get nodes
# error: You must be logged in to the server (the server has asked for credentials)
```

**Root cause:** The EKS module v21.x computes `bootstrap_cluster_creator_admin_permissions`
as `!var.enable_cluster_creator_admin_permissions`, which should produce `true` when
the variable is `false`. However, in practice, the combination of
`create_iam_role = false` and `enable_cluster_creator_admin_permissions = false`
results in the field being silently dropped or set to `false` in the API call. The
exact module version behavior was not pinned and the fix was to bypass the module
entirely for the cluster resource.

**Evidence of the bug:**
- `list-access-entries` shows no entry for the lab user (bootstrap entry not created)
- kubectl returns 401 (not 403) — the user is completely unknown to the API server
- 401 changed to 403 only after manually creating an access entry, confirming the
  bootstrap mechanism did not run

**Fix:**

Bypass the EKS module for the cluster. Use a raw `aws_eks_cluster` resource with
the field set as a literal:

```hcl
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_additional.id]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true  # passed directly to AWS API
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
```

With this configuration, `list-access-entries` returns an entry for the lab user
with `AmazonEKSClusterAdminPolicy` associated, and `kubectl get nodes` returns
`No resources found` (correct — no nodes yet, not Forbidden).

---

## 17. AWS Credentials Not Configured on Bastion

**When:** Running kubectl on the bastion host immediately after SSH-ing in.

**Error:**

```
error: You must be logged in to the server (the server has asked for the client
to provide credentials)
```

Appearing identical to Error 12 but with a different root cause.

**Root cause:** The bastion is a fresh EC2 instance with no IAM instance profile.
The `aws eks update-kubeconfig` command writes a kubeconfig that uses
`aws eks get-token` to generate tokens dynamically. `aws eks get-token` requires
valid AWS credentials in the environment. On a bastion with no instance profile and
no configured credentials, the token generation silently produces an empty/invalid
token, and the EKS API server rejects it.

**Diagnosis:**

```bash
aws sts get-caller-identity
# If this fails, credentials are not configured — that is the cause
```

**Fix:**

```bash
aws configure
# Enter the same KodeKloud lab credentials used on the dev machine

aws sts get-caller-identity  # must succeed before proceeding
aws eks update-kubeconfig --region us-east-1 --name microservices-demo-eks
kubectl get nodes
```

!!! note "Instance profile vs manual credentials"
    Attaching an IAM instance profile to the bastion would eliminate this manual
    step. The bastion Terraform config does not currently include an instance profile.
    This is a known gap: for production use, attach an IAM role with sufficient EKS
    and EC2 permissions to the bastion at provision time.

---

## Summary: What the Final Working Configuration Avoids

| SCP-Blocked Operation | How the Working Config Avoids It |
|---|---|
| `iam:PassRole` (wrong name) | `iam-eks.tf` creates `eksClusterRole` with the exact whitelisted name; `aws_eks_cluster` references it directly |
| `iam:TagPolicy` | No KMS encryption, no encryption IAM policy |
| `eks:CreateNodegroup` | No `eks_managed_node_groups`, no `aws_eks_node_group`; CloudFormation for nodes |
| `eks:AssociateAccessPolicy` | `bootstrap_cluster_creator_admin_permissions = true` on the raw cluster resource; EKS handles admin access internally |
| `eks:UpdateAccessEntry` | Never needed — bootstrap permissions set at creation time |
| `eks:DeleteAddon` | `preserve = true` on all `aws_eks_addon` resources |
| `logs:DeleteLogGroup` | EKS manages its own log group; Terraform does not declare one |
