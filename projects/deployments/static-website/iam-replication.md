# Stage 2: IAM Replication Role and CRR

## Phase 3: IAM Role for Cross-Region Replication

S3 needs an IAM role to assume when copying objects from the primary bucket to the replica. The role must allow S3 to read from the source and write to the destination, and must have access to both KMS keys for the decrypt/re-encrypt operation.

!!! note "Why CRR before upload?"
    CRR only replicates objects uploaded after the replication rule is active. Setting up replication first ensures the initial content sync reaches the replica automatically. Uploading first and then enabling CRR would leave the replica empty until the next update.

### Create the Role

```bash
aws iam create-role \
  --role-name s3-crr-portfolio-site \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }]
  }'
```

### Attach the Replication Policy

```bash
aws iam put-role-policy \
  --role-name s3-crr-portfolio-site \
  --policy-name crr-replication-policy \
  --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSourceBucketRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${PRIMARY_BUCKET}"
    },
    {
      "Sid": "AllowSourceObjectRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": "arn:aws:s3:::${PRIMARY_BUCKET}/*"
    },
    {
      "Sid": "AllowDestinationWrite",
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": "arn:aws:s3:::${REPLICA_BUCKET}/*"
    },
    {
      "Sid": "AllowKMSDecryptSource",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "${KMS_KEY_ARN1}"
    },
    {
      "Sid": "AllowKMSEncryptDestination",
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "${KMS_KEY_ARN2}"
    }
  ]
}
EOF
)"
```

### Enable Replication on the Primary Bucket

```bash
export CRR_ROLE_ARN=$(aws iam get-role \
  --role-name s3-crr-portfolio-site \
  --query Role.Arn --output text)

aws s3api put-bucket-replication \
  --bucket $PRIMARY_BUCKET \
  --replication-configuration "$(cat <<EOF
{
  "Role": "${CRR_ROLE_ARN}",
  "Rules": [{
    "ID": "ReplicateAll",
    "Status": "Enabled",
    "Priority": 1,
    "Filter": {},
    "Destination": {
      "Bucket": "arn:aws:s3:::${REPLICA_BUCKET}",
      "EncryptionConfiguration": {
        "ReplicaKmsKeyID": "${KMS_KEY_ARN2}"
      }
    },
    "SourceSelectionCriteria": {
      "SseKmsEncryptedObjects": { "Status": "Enabled" }
    },
    "DeleteMarkerReplication": { "Status": "Enabled" }
  }]
}
EOF
)"
```

!!! note "Why `SourceSelectionCriteria.SseKmsEncryptedObjects`?"
    Without this, S3 silently skips KMS-encrypted objects during replication. This flag is mandatory when the source bucket uses SSE-KMS.
    
    **Why `Priority`?** Required for any replication rule that uses `Filter` (even an empty one). Without it, `put-bucket-replication` returns a `MalformedXML` error.

---

## Phase 4: Upload Site Content

!!! note "Source directory:"
    Only the `dist/` folder was synced. It contains exactly the production build artefacts (HTML, CSS, JS, assets). No `.git/`, no source files, no config files exist in `dist/`, so no `--exclude` flags were needed.

```bash
# Run from the root of the portfolio-site repository
aws s3 sync dist/ s3://$PRIMARY_BUCKET \
  --region us-east-1 \
  --sse aws:kms \
  --sse-kms-key-id $KMS_KEY_ID1 \
  --delete
```

!!! note "`--sse aws:kms`"
    Explicitly enforces KMS encryption on every uploaded object, even if the bucket default is already set. This prevents any object being silently uploaded with SSE-S3 if a caller omits the header.

    **`--sse-kms-key-id $KMS_KEY_ID1`** pins each object to the specific CMK so the Bucket Key on the upload side is engaged correctly. Without this flag, AWS falls back to the bucket default key but the per-request encryption header may not carry the key ID, which can cause CloudFront OAC `kms:Decrypt` failures.

    **`--delete`** removes any S3 objects that no longer exist in `dist/`. Keeps the bucket in sync with the exact build output and prevents stale files from being served.

Verified the upload and confirmed replication reached the replica:

```bash
aws s3 ls s3://$PRIMARY_BUCKET --recursive --human-readable
aws s3 ls s3://$REPLICA_BUCKET --recursive --human-readable

# Check replication status on a specific object
aws s3api head-object \
  --bucket $PRIMARY_BUCKET \
  --key index.html \
  --query ReplicationStatus
# Expected: "COMPLETED"
```
