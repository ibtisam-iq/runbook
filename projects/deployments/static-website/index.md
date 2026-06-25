# Secure Static Hosting and Global Distribution (S3 + CloudFront + KMS + IAM + CloudTrail)

A production-grade, globally distributed static site deployment on AWS: private S3 origin served through CloudFront with Origin Access Control, KMS encryption at rest, Cross-Region Replication for disaster recovery, and full audit logging via CloudTrail.

---

## Use Case

The following stack is for static-only websites (React, Vue, Angular, Hugo, Jekyll, Next.js static exports, etc.) hosted in a cost-effective, highly available, globally distributed manner, without requiring any compute resources like ECS or EC2.

**Ideal for:**

- Portfolio sites like [My Portfolio Site](https://ibtisam-iq.com/)
- Marketing landing pages
- Product documentation sites
- Small business/blog sites

!!! note
    - I used my [portfolio-site](https://github.com/ibtisam-iq/portfolio-site) repository as the static content for this deployment because it is a production static site with a real `dist/` build output.
    - I have also included the [Complete Terminal Session](https://github.com/ibtisam-iq/platform-engineering-systems/blob/main/systems/static-website/terminal-session.txt) that I ran to deploy this stack.

---

## Architecture Overview

```text
Browser
   |
   v
Cloudflare DNS  -->  ibtisam.qzz.io
   |                 (CNAME to CloudFront distribution domain)
   v
CloudFront Distribution (HTTPS, OAC, custom domain)
   |   ^ ACM certificate (us-east-1) for ibtisam.qzz.io
   |   ^ KMS key (us-east-1): CloudFront decrypts on read
   v
S3 Primary Bucket  (us-east-1, private, KMS-SSE, Bucket Key ON, versioning ON)
   |   portfolio-site-primary-<account-id>
   |
   |-- CloudTrail  -->  S3 logging bucket  (API audit trail)
   |-- S3 Server Access Logs  -->  S3 logging bucket
   |
   v  Cross-Region Replication (CRR)
S3 Replica Bucket  (us-west-2, private, KMS-SSE, Bucket Key ON, versioning ON)
       portfolio-site-replica-<account-id>
       ^ KMS key (us-west-2): re-encrypts replicated objects
```

### AWS Services Used

| Service | Role |
|---|---|
| S3 (primary, us-east-1) | Origin bucket: stores all static site files, private, versioned |
| S3 (replica, us-west-2) | Disaster recovery / Cross-Region Replication target |
| KMS (us-east-1) | Encrypts objects at rest in the primary bucket; used by CloudFront (OAC) and CRR |
| KMS (us-west-2) | Encrypts replicated objects at rest in the replica bucket |
| CloudFront | Global CDN: serves content from S3 via OAC, handles TLS termination |
| ACM | TLS certificate for `ibtisam.qzz.io` (must be issued in `us-east-1` for CloudFront) |
| IAM | Replication role granting S3 cross-region copy permissions; CloudFront OAC service principal |
| CloudTrail | Audit log of every API call against both buckets (management + data events) |
| S3 Server Access Logs | Per-request HTTP-level access log on the origin bucket |
| Cloudflare DNS | CNAME record pointing `ibtisam.qzz.io` to CloudFront distribution domain |
| Lifecycle Policy | Transitions older object versions to Glacier after 30 days |

---

## Key Decisions

Architectural and operational decisions made for this static site hosting platform.

- **Private S3 Origin with CloudFront OAC:** Origin Access Control (OAC) with SigV4 signing is used to authenticate CloudFront requests to S3. Public S3 access is blocked at the account level, offering better security than legacy Origin Access Identity (OAI) or public buckets. ([Stage 3](cloudfront-cdn.md))
- **KMS Encryption with S3 Bucket Keys:** SSE-KMS encrypts data at rest using customer-managed keys (CMK). Enabling S3 Bucket Keys reduces KMS `GenerateDataKey` calls by up to 99%, substantially cutting KMS costs for high-traffic sites while preserving security. ([Stage 1](storage-encryption.md))
- **Cross-Region Replication (CRR) on KMS Objects:** To successfully replicate KMS-encrypted objects to another region, the replication rule must explicitly set `SourceSelectionCriteria.SseKmsEncryptedObjects` to `Enabled`, and the IAM replication role must have `kms:Decrypt` (source) and `kms:Encrypt` (destination) permissions. ([Stage 2](iam-replication.md))
- **S3 Server Access Logs Policy:** Setting `TargetBucket` in the logging configuration is not enough. The logging bucket must explicitly grant `s3:PutObject` to the `logging.s3.amazonaws.com` principal. ([Stage 5](observability-lifecycle.md))

---

## Phases

The project is documented across 5 stages. Each stage has its own runbook with step-by-step commands and decisions.

<div class="grid cards" markdown>

- **[:material-database: Stage 1: Storage & Encryption](storage-encryption.md)**
  Created private versioned S3 primary & replica buckets. Created two regional KMS keys and applied SSE-KMS with Bucket Key enabled.

- **[:material-account-key: Stage 2: IAM / CRR & Upload](iam-replication.md)**
  Created CRR IAM role and enabled CRR with KMS re-encryption. Synced `dist/` to S3 with explicit SSE-KMS key ID.

- **[:material-web: Stage 3: CloudFront CDN and DNS](cloudfront-cdn.md)**
  Issued ACM certificate in us-east-1. Created CloudFront OAC and distribution (HTTPS, SPA error handling). Applied S3 bucket policy and configured Cloudflare CNAME.

- **[:material-eye: Stage 4: Observability & Lifecycle](observability-lifecycle.md)**
  Created CloudTrail trail with data events and S3 Server Access Logs. Added Glacier lifecycle policy.

- **[:material-check-all: Stage 5: Verification, Troubleshooting & Teardown](verification.md)**
  Verified HTTPS, S3 403 blocks, CloudTrail events, Bucket Key state, and CRR count. Includes common troubleshooting issues and full resource teardown steps.

</div>
