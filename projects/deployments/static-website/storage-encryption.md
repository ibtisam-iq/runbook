# Stage 1: Storage and Encryption

## Phase 1: S3 Buckets (Primary + Replica)

Created two buckets: one in `us-east-1` as the CloudFront origin, one in `us-west-2` as the CRR target. Both buckets are fully private; no public access is ever granted directly.

S3 bucket names are globally unique across all AWS accounts. Appending the AWS Account ID as a suffix guarantees uniqueness without guessing.

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export PRIMARY_BUCKET="portfolio-site-primary-${ACCOUNT_ID}"
export REPLICA_BUCKET="portfolio-site-replica-${ACCOUNT_ID}"
export LOG_BUCKET="portfolio-site-logs-${ACCOUNT_ID}"

# Primary bucket (us-east-1)
aws s3 mb s3://$PRIMARY_BUCKET --region us-east-1

# Replica bucket (us-west-2)
aws s3 mb s3://$REPLICA_BUCKET --region us-west-2

# Block all public access on both buckets
for BUCKET in $PRIMARY_BUCKET $REPLICA_BUCKET; do
  aws s3api put-public-access-block --bucket $BUCKET \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
done

# Enable versioning on both (required for CRR)
for BUCKET in $PRIMARY_BUCKET $REPLICA_BUCKET; do
  aws s3api put-bucket-versioning \
    --bucket $BUCKET \
    --versioning-configuration Status=Enabled
done
```

!!! note "Why versioning?"
    Cross-Region Replication only works when versioning is enabled on both source and destination buckets. It also enables lifecycle policies to transition old versions to Glacier, and protects against accidental overwrites or deletes.

---

## Phase 2: KMS Encryption Keys

KMS keys are regional: a key in `us-east-1` cannot encrypt or decrypt objects in `us-west-2`. Two separate keys were required.

### Key 1: Primary Bucket (us-east-1)

This key protects objects stored in the primary bucket. CloudFront uses this key to decrypt objects when serving them via OAC. During CRR, S3 uses this key to decrypt the object at the source before replicating.

```bash
KMS_KEY_ID1=$(aws kms create-key \
  --description "S3 encryption key for portfolio-site primary bucket" \
  --region us-east-1 \
  --query KeyMetadata.KeyId --output text)

KMS_KEY_ARN1=$(aws kms describe-key \
  --key-id $KMS_KEY_ID1 --region us-east-1 \
  --query KeyMetadata.Arn --output text)

aws kms create-alias \
  --alias-name alias/portfolio-site-primary \
  --target-key-id $KMS_KEY_ID1 \
  --region us-east-1
```

**Key policy for the primary bucket:**

```bash
aws kms put-key-policy \
  --key-id $KMS_KEY_ID1 \
  --region us-east-1 \
  --policy-name default \
  --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountRootFullAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${ACCOUNT_ID}:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudFrontToDecrypt",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ReplicationUse",
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    }
  ]
}
EOF
)"
```

!!! note "What this policy does:"
    Root retains full control. CloudFront can decrypt for delivery. S3 (scoped to the account) can decrypt at the CRR source side.
    
    The heredoc (`<<EOF`) causes the shell to interpolate `${ACCOUNT_ID}` from the current session before the JSON is passed to the AWS CLI.

### Key 2: Replica Bucket (us-west-2)

S3 uses this key to re-encrypt the replicated data at the destination. CloudFront never reads from the replica, so no CloudFront statement is needed here.

```bash
KMS_KEY_ID2=$(aws kms create-key \
  --description "S3 encryption key for portfolio-site replica bucket" \
  --region us-west-2 \
  --query KeyMetadata.KeyId --output text)

KMS_KEY_ARN2=$(aws kms describe-key \
  --key-id $KMS_KEY_ID2 --region us-west-2 \
  --query KeyMetadata.Arn --output text)

aws kms create-alias \
  --alias-name alias/portfolio-site-replica \
  --target-key-id $KMS_KEY_ID2 \
  --region us-west-2
```

**Key policy for the replica bucket:**

```bash
aws kms put-key-policy \
  --key-id $KMS_KEY_ID2 \
  --region us-west-2 \
  --policy-name default \
  --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountRootFullAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${ACCOUNT_ID}:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ReplicationUseReplica",
      "Effect": "Allow",
      "Principal": { "Service": "s3.amazonaws.com" },
      "Action": ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    }
  ]
}
EOF
)"
```

### Apply Default Bucket Encryption with Bucket Key Enabled

The S3 Bucket Key is a performance and cost optimization that sits between S3 and KMS. Without it, S3 makes one `GenerateDataKey` KMS API call per object on every PUT and GET, meaning 1,000 uploads = 1,000 KMS calls. With `BucketKeyEnabled: true`, KMS generates a single short-lived bucket-level key that S3 reuses locally to derive per-object keys, reducing KMS API calls by up to 99% and cutting KMS costs proportionally. The security model is identical either way.

!!! note "Why set it here and not in Phase 1?"
    The Bucket Key is part of the SSE-KMS encryption configuration (`put-bucket-encryption`), which requires the KMS key ID to be known. Phase 1 only creates the buckets. This command must run after `KMS_KEY_ID1` and `KMS_KEY_ID2` are exported.

```bash
# Primary bucket: SSE-KMS with Bucket Key enabled
aws s3api put-bucket-encryption \
  --bucket $PRIMARY_BUCKET \
  --server-side-encryption-configuration "$(cat <<EOF
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "${KMS_KEY_ID1}"
    },
    "BucketKeyEnabled": true
  }]
}
EOF
)"

# Replica bucket: SSE-KMS with Bucket Key enabled
aws s3api put-bucket-encryption \
  --bucket $REPLICA_BUCKET \
  --server-side-encryption-configuration "$(cat <<EOF
{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "aws:kms",
      "KMSMasterKeyID": "${KMS_KEY_ID2}"
    },
    "BucketKeyEnabled": true
  }]
}
EOF
)"
```

Verified Bucket Key status on both buckets:

```bash
aws s3api get-bucket-encryption --bucket $PRIMARY_BUCKET \
  --query 'ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled'
# Expected: true

aws s3api get-bucket-encryption --bucket $REPLICA_BUCKET \
  --query 'ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled'
# Expected: true
```

!!! note "Bucket Key and CRR:"
    When the source bucket has a Bucket Key enabled, replicated objects at the destination also inherit the Bucket Key behaviour, provided `BucketKeyEnabled: true` is set on the replica bucket encryption config as well (done above).
