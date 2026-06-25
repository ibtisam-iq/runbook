# Stage 3: CloudFront CDN and DNS

## Phase 5: ACM Certificate (us-east-1)

CloudFront requires its TLS certificate to be issued in `us-east-1` regardless of where other resources are. This is a hard AWS constraint.

```bash
export CERT_ARN=$(aws acm request-certificate \
  --domain-name ibtisam.qzz.io \
  --validation-method DNS \
  --region us-east-1 \
  --query CertificateArn --output text)

echo "CERT_ARN=$CERT_ARN"
```

Extracted the DNS validation CNAME record that ACM requires:

```bash
# Wait a few seconds for ACM to generate the validation record
sleep 5

aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.{Name:Name,Value:Value}' \
  --output table
```

Added the CNAME name and value as a DNS record in Cloudflare (proxy status: DNS only / grey cloud). Then waited for the certificate status to change to `ISSUED`:

```bash
# Poll until issued (typically 1 to 5 minutes after DNS propagation)
aws acm wait certificate-validated \
  --certificate-arn $CERT_ARN \
  --region us-east-1

aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.Status'
# Expected: "ISSUED"
```

---

## Phase 6: CloudFront Origin Access Control (OAC)

OAC is the modern replacement for Origin Access Identity (OAI). It signs requests to S3 using SigV4, works with SSE-KMS encrypted buckets, and does not require public S3 access.

```bash
export OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "portfolio-site-oac",
    "Description": "OAC for portfolio-site S3 origin",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }' \
  --query 'OriginAccessControl.Id' \
  --output text)

echo "OAC_ID=$OAC_ID"
```

---

## Phase 7: Create the CloudFront Distribution

Created the distribution with the S3 REST API endpoint as origin, OAC signing, HTTPS redirect, the ACM certificate for the custom domain, and `CachingOptimized` as the managed cache policy.

!!! note "`CachingOptimized` policy ID:"
    `658327ea-f89d-4fab-a63d-7e88639e58f6` is the AWS-managed CachingOptimized cache policy. It sets a default TTL of 86400s (24h), enables Gzip and Brotli compression, and forwards no headers, cookies, or query strings to the origin. This is the recommended policy for static site origins.

```bash
ORIGIN_DOMAIN="${PRIMARY_BUCKET}.s3.us-east-1.amazonaws.com"
CALLER_REF=$(date +%s)

CF_OUTPUT=$(aws cloudfront create-distribution \
  --distribution-config "$(cat <<EOF
{
  "CallerReference": "${CALLER_REF}",
  "Comment": "portfolio-site CDN",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Aliases": {
    "Quantity": 1,
    "Items": ["ibtisam.qzz.io"]
  },
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3Origin",
      "DomainName": "${ORIGIN_DOMAIN}",
      "OriginAccessControlId": "${OAC_ID}",
      "S3OriginConfig": {
        "OriginAccessIdentity": ""
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "${CERT_ARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "CustomErrorResponses": {
    "Quantity": 1,
    "Items": [{
      "ErrorCode": 403,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 0
    }]
  },
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_100"
}
EOF
)" --output json)

export CF_DISTRIBUTION_ID=$(echo $CF_OUTPUT | jq -r '.Distribution.Id')
export CF_DOMAIN=$(echo $CF_OUTPUT | jq -r '.Distribution.DomainName')
export CF_ETAG=$(echo $CF_OUTPUT | jq -r '.ETag')

echo "CF_DISTRIBUTION_ID=$CF_DISTRIBUTION_ID"
echo "CF_DOMAIN=$CF_DOMAIN"
```

!!! note "`S3OriginConfig.OriginAccessIdentity: \"\"`"
    It is required even when using OAC. It tells CloudFront this is an S3 REST API origin (not a custom origin) but that OAI is not in use. Omitting this field causes a validation error.

    **`CustomErrorResponses` for 403:** A single-page application (SPA) with client-side routing returns 403 from S3 for any path other than `index.html`, because no such S3 key exists. This error response maps 403 back to `index.html` with HTTP 200 so the client router handles the path.

    **`PriceClass_100`:** Limits edge locations to North America and Europe, the cheapest tier. Sufficient for a portfolio site; avoids charges from Asia/South America edge locations with minimal traffic.

    **`HttpVersion: http2and3`:** Enables HTTP/3 (QUIC) for clients that support it, reducing connection latency on mobile and lossy networks.

---

## Phase 8: S3 Bucket Policy (Allow CloudFront OAC)

After creating the distribution, applied the bucket policy that grants the CloudFront service principal access to the bucket, scoped to the specific distribution ARN.

```bash
aws s3api put-bucket-policy \
  --bucket $PRIMARY_BUCKET \
  --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${PRIMARY_BUCKET}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
EOF
)"
```

!!! danger "Critical"
    The `AWS:SourceArn` condition scopes this permission to one specific CloudFront distribution. Without this condition, any CloudFront distribution in any AWS account could read the bucket.

---

## Phase 9: Cloudflare DNS

Added a CNAME record in the Cloudflare dashboard:

| Type | Name | Content | Proxy status |
|---|---|---|---|
| CNAME | `portfolio` | `$CF_DOMAIN` (e.g., `d1abc123xyz.cloudfront.net`) | DNS only (grey cloud) |

!!! note "Why \"DNS only\" and not proxied?"
    When Cloudflare proxies the request, it terminates the TLS connection and CloudFront sees Cloudflare's IP instead of the client's. This can break CloudFront's SNI-based certificate matching and geo-restriction features. DNS-only is required for CloudFront origins.

Verified propagation:

```bash
dig ibtisam.qzz.io CNAME +short
# Expected: d1abc123xyz.cloudfront.net.
```
