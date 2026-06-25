# Stage 4: Observability, Audit, and Lifecycle

## Phase 10: CloudTrail Audit Logging

Created a dedicated logging bucket before enabling CloudTrail or S3 access logging. This bucket grants write access to both the CloudTrail service and the S3 log delivery service.

```bash
aws s3 mb s3://$LOG_BUCKET --region us-east-1

aws s3api put-public-access-block --bucket $LOG_BUCKET \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**Bucket policy for the logging bucket** (grants both CloudTrail and S3 Server Access Logging):

```bash
aws s3api put-bucket-policy \
  --bucket $LOG_BUCKET \
  --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${LOG_BUCKET}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${LOG_BUCKET}/AWSLogs/${ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Sid": "S3ServerAccessLogsWrite",
      "Effect": "Allow",
      "Principal": { "Service": "logging.s3.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${LOG_BUCKET}/s3-access-logs/*",
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

!!! note "Why the `S3ServerAccessLogsWrite` statement?"
    The original runbook only granted CloudTrail permissions. The `put-bucket-logging` call in Phase 10 would succeed, but S3 would silently fail to deliver access logs because the target bucket never authorized the `logging.s3.amazonaws.com` service principal.

### Create the Trail

```bash
aws cloudtrail create-trail \
  --name portfolio-site-trail \
  --s3-bucket-name $LOG_BUCKET \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --region us-east-1

aws cloudtrail start-logging \
  --name portfolio-site-trail \
  --region us-east-1
```

### Enable S3 Data Events

By default, CloudTrail only logs management events (bucket creates, policy updates). Enabled data events to also log every `GetObject`, `PutObject`, and `DeleteObject` call on the primary bucket:

```bash
aws cloudtrail put-event-selectors \
  --trail-name portfolio-site-trail \
  --event-selectors "$(cat <<EOF
[{
  "ReadWriteType": "All",
  "IncludeManagementEvents": true,
  "DataResources": [{
    "Type": "AWS::S3::Object",
    "Values": ["arn:aws:s3:::${PRIMARY_BUCKET}/"]
  }]
}]
EOF
)" \
  --region us-east-1
```

### Enable S3 Server Access Logging

CloudTrail logs API calls. S3 Server Access Logs capture the raw HTTP request log, useful for debugging cache misses and access patterns.

```bash
aws s3api put-bucket-logging \
  --bucket $PRIMARY_BUCKET \
  --bucket-logging-status "$(cat <<EOF
{
  "LoggingEnabled": {
    "TargetBucket": "${LOG_BUCKET}",
    "TargetPrefix": "s3-access-logs/"
  }
}
EOF
)"
```

---

## Phase 10B: Lifecycle Policy (Glacier Tiering)

Transitioned non-current object versions (old deploys) to Glacier after 30 days. This prevents storage costs from accumulating across iterations of the site.

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket $PRIMARY_BUCKET \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "archive-old-versions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionTransitions": [{
        "NoncurrentDays": 30,
        "StorageClass": "GLACIER"
      }],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 365
      }
    }]
  }'
```
