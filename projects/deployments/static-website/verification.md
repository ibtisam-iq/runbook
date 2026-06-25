# Stage 5: Verification, Troubleshooting, and Teardown

## Phase 11: End-to-End Checks

### 1. HTTPS via Custom Domain

```bash
curl -I https://ibtisam.qzz.io
# Expected: HTTP/2 200, x-cache: Hit from cloudfront (after warm-up)
```

### 2. Direct S3 Access Must Return 403

```bash
curl -I https://$PRIMARY_BUCKET.s3.us-east-1.amazonaws.com/index.html
# Expected: 403 Forbidden, confirms no public S3 access
```

### 3. CloudTrail: Verify Events Are Flowing

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=$PRIMARY_BUCKET \
  --region us-east-1 \
  --max-results 5
```

### 4. Replication: Confirm Object Count Matches

```bash
echo "Primary: $(aws s3 ls s3://$PRIMARY_BUCKET --recursive | wc -l) objects"
echo "Replica: $(aws s3 ls s3://$REPLICA_BUCKET --recursive | wc -l) objects"
# Counts should be equal (allow a few minutes for CRR to complete)
```

### 5. Bucket Key: Confirm Enabled on Both Buckets

```bash
aws s3api get-bucket-encryption --bucket $PRIMARY_BUCKET \
  --query 'ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled'
# Expected: true

aws s3api get-bucket-encryption --bucket $REPLICA_BUCKET \
  --query 'ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled'
# Expected: true
```

### 6. Pre-signed URL (Demonstrates Private Bucket Access)

```bash
aws s3 presign s3://$PRIMARY_BUCKET/index.html \
  --region us-east-1 \
  --expires-in 300
# Returns a time-limited URL valid for 5 minutes
```

---

## Troubleshooting

### CRR Not Replicating (Most Common Issue)

**Symptom:** Objects exist in the primary bucket but the replica is empty or incomplete after several minutes.

**Root cause:** The IAM replication role's KMS permissions are missing or the KMS key policies do not include the `s3.amazonaws.com` service principal.

**Fix:**

1. Check the KMS key policy on the primary bucket's key: confirm the `AllowS3ReplicationUse` statement is present with the correct `aws:SourceAccount` condition.
2. Check the KMS key policy on the replica bucket's key: confirm `AllowS3ReplicationUseReplica` is present.
3. Check the IAM replication role policy: confirm both `kms:Decrypt` (source key ARN) and `kms:Encrypt` (destination key ARN) are present, and both include `kms:DescribeKey`.
4. Verify `SourceSelectionCriteria.SseKmsEncryptedObjects` is set to `Enabled` in the replication rule. Without this, S3 silently skips KMS objects.

```bash
aws s3api get-bucket-replication --bucket $PRIMARY_BUCKET

aws s3api head-object \
  --bucket $PRIMARY_BUCKET \
  --key index.html \
  --query ReplicationStatus
# Should return: "COMPLETED"
```

---

### CloudFront Returns 403 on Root URL

**Symptom:** `https://ibtisam.qzz.io` returns `403 Forbidden` but direct object URLs work.

**Root cause:** The CloudFront distribution's Default root object is not set to `index.html`.

**Fix:**

```bash
# Get current config
aws cloudfront get-distribution-config --id $CF_DISTRIBUTION_ID > /tmp/cf-config.json
ETAG=$(jq -r '.ETag' /tmp/cf-config.json)

# Edit DefaultRootObject and update
jq '.DistributionConfig.DefaultRootObject = "index.html" | .DistributionConfig' /tmp/cf-config.json > /tmp/cf-update.json
aws cloudfront update-distribution --id $CF_DISTRIBUTION_ID --if-match $ETAG --distribution-config file:///tmp/cf-update.json
```

---

### ACM Certificate Stuck in PENDING_VALIDATION

**Symptom:** Certificate status remains `PENDING_VALIDATION` for more than 10 minutes.

**Root cause:** The DNS validation CNAME record was not added to Cloudflare, or Cloudflare is proxying it (orange cloud) which can interfere with ACM's DNS lookup.

**Fix:**

1. In Cloudflare DNS, confirm the ACM validation CNAME record exists with proxy status = DNS only (grey cloud).
2. Verify the record:

```bash
dig _<acm-token>.ibtisam.qzz.io CNAME +short
```

3. Wait up to 5 minutes after `dig` confirms propagation.

---

### CloudFront 403 After OAC Setup

**Symptom:** Distribution is deployed but all requests return 403.

**Root cause:** The S3 bucket policy was not updated after creating the OAC-based distribution.

**Fix:** Re-apply the bucket policy from Phase 8 with the correct `CF_DISTRIBUTION_ID`. Also confirm the KMS key policy includes `AllowCloudFrontToDecrypt`.

---

## Teardown

Delete all resources in reverse dependency order. CloudFront distributions must be disabled before deletion, and S3 buckets must be emptied before removal.

!!! note "KMS keys:"
    KMS does not allow immediate deletion. The minimum scheduling window is 7 days. The keys cost nothing while pending deletion.

### Step 1: Disable and Delete the CloudFront Distribution

```bash
# Get current config and ETag
aws cloudfront get-distribution-config --id $CF_DISTRIBUTION_ID > /tmp/cf-config.json
ETAG=$(jq -r '.ETag' /tmp/cf-config.json)

# Disable the distribution
jq '.DistributionConfig.Enabled = false | .DistributionConfig' /tmp/cf-config.json > /tmp/cf-disable.json
aws cloudfront update-distribution \
  --id $CF_DISTRIBUTION_ID \
  --if-match $ETAG \
  --distribution-config file:///tmp/cf-disable.json

echo "Waiting for distribution to reach Deployed state (this takes several minutes)..."
aws cloudfront wait distribution-deployed --id $CF_DISTRIBUTION_ID

# Get the updated ETag after disable
ETAG=$(aws cloudfront get-distribution-config --id $CF_DISTRIBUTION_ID --query 'ETag' --output text)

# Delete the distribution
aws cloudfront delete-distribution --id $CF_DISTRIBUTION_ID --if-match $ETAG
```

### Step 2: Delete the OAC

```bash
OAC_ETAG=$(aws cloudfront get-origin-access-control --id $OAC_ID --query 'ETag' --output text)
aws cloudfront delete-origin-access-control --id $OAC_ID --if-match $OAC_ETAG
```

### Step 3: Delete the ACM Certificate

```bash
aws acm delete-certificate --certificate-arn $CERT_ARN --region us-east-1
```

### Step 4: Stop and Delete CloudTrail

```bash
aws cloudtrail stop-logging --name portfolio-site-trail --region us-east-1
aws cloudtrail delete-trail --name portfolio-site-trail --region us-east-1
```

### Step 5: Remove Replication Configuration

```bash
aws s3api delete-bucket-replication --bucket $PRIMARY_BUCKET
```

### Step 6: Empty and Delete All S3 Buckets

```bash
# Empty all three buckets (including all versions and delete markers)
for BUCKET in $PRIMARY_BUCKET $REPLICA_BUCKET $LOG_BUCKET; do
  echo "Emptying $BUCKET..."
  aws s3api list-object-versions --bucket $BUCKET --output json \
    | jq -r '.Versions[]? | "aws s3api delete-object --bucket '"$BUCKET"' --key \"\(.Key)\" --version-id \(.VersionId)"' \
    | bash 2>/dev/null
  aws s3api list-object-versions --bucket $BUCKET --output json \
    | jq -r '.DeleteMarkers[]? | "aws s3api delete-object --bucket '"$BUCKET"' --key \"\(.Key)\" --version-id \(.VersionId)"' \
    | bash 2>/dev/null
  aws s3 rb s3://$BUCKET
done
```

### Step 7: Delete the IAM Replication Role

```bash
aws iam delete-role-policy --role-name s3-crr-portfolio-site --policy-name crr-replication-policy
aws iam delete-role --role-name s3-crr-portfolio-site
```

### Step 8: Schedule KMS Key Deletion

```bash
aws kms schedule-key-deletion --key-id $KMS_KEY_ID1 --pending-window-in-days 7 --region us-east-1
aws kms schedule-key-deletion --key-id $KMS_KEY_ID2 --pending-window-in-days 7 --region us-west-2
```

### Step 9: Remove Cloudflare DNS Records

Manually remove from the Cloudflare dashboard:

1. The CNAME record for `portfolio` pointing to the CloudFront domain.
2. The ACM validation CNAME record (the `_<token>.ibtisam.qzz.io` entry).
