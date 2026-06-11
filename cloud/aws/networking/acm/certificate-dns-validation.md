# ACM: Request and Validate a Public TLS Certificate via DNS

!!! abstract ""
    **TLS certificate provisioning** — Requests a public certificate from ACM
    for a domain, injects the DNS validation CNAME record into the authoritative
    DNS provider, and waits for ACM to confirm ownership and issue the certificate.
    Once issued, ACM auto-renews the certificate before expiry without further
    intervention.

    **Prerequisite:** AWS CLI configured with credentials that carry
    `acm:RequestCertificate`, `acm:DescribeCertificate`, and
    `route53:ChangeResourceRecordSets` permissions. The domain must resolve
    publicly — NS delegation must be active before ACM can validate.

---

## Workflow Overview

This runbook covers the following steps in order:

- Request the ACM certificate for the target domain
- Retrieve the CNAME name and value ACM generates for DNS validation
- Add the CNAME record to the authoritative DNS provider (Route 53 or Cloudflare)
- Wait for ACM to detect the record and issue the certificate
- Confirm the issued status

The DNS provider step varies. Follow the Route 53 path if the hosted zone lives
in Route 53. Follow the Cloudflare path if the domain is managed on Cloudflare.
The CNAME Name field is handled differently between the two providers.

---

## Set Variables

```bash
DOMAIN="ibtisam.qzz.io"
REGION="us-east-1"   # Use us-east-1 for CloudFront; match service region for ALB
```

!!! warning "Region matters for CloudFront"
    CloudFront only accepts ACM certificates from `us-east-1`. For ALB or API
    Gateway, request the certificate in the same region as the service. Requesting
    in the wrong region means the certificate will not appear in the service's
    certificate picker and cannot be attached.

If the validation record will be injected into Route 53, capture the hosted zone
ID now.

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"
```

Skip the `HOSTED_ZONE_ID` step entirely if using Cloudflare.

---

## Request the Certificate

Request a certificate that covers the apex domain and all first-level subdomains.

```bash
CERT_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "*.${DOMAIN}" \
  --validation-method DNS \
  --region "$REGION" \
  --query "CertificateArn" \
  --output text)

echo "Certificate ARN: $CERT_ARN"
```

The certificate is created in `PENDING_VALIDATION` state. It stays there until
the DNS CNAME record is added and ACM can verify it.

!!! note "One CNAME covers both apex and wildcard"
    ACM issues a single CNAME validation record that satisfies both
    `ibtisam.qzz.io` and `*.ibtisam.qzz.io`. Only one record needs to be added
    to the DNS provider.

---

## Retrieve the Validation CNAME

Wait a few seconds after the request, then fetch the CNAME name and value ACM
generated for this certificate.

```bash
sleep 10

aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.DomainValidationOptions[*].{Domain:DomainName,Name:ResourceRecord.Name,Value:ResourceRecord.Value,Type:ResourceRecord.Type}" \
  --output table
```

Capture `Name` and `Value` into variables.

```bash
CNAME_NAME=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
  --output text)

CNAME_VALUE=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
  --output text)

echo "CNAME Name:  $CNAME_NAME"
echo "CNAME Value: $CNAME_VALUE"
```

Both are long randomised strings in the format `_<hash>.<domain>.`.

!!! info "What ACM returns for apex vs subdomain"
    For an apex domain `ibtisam.qzz.io`:

    ```
    CNAME Name:  _abc123def456.ibtisam.qzz.io.
    CNAME Value: _xyz789qrs012.acm-validations.aws.
    ```

    For a subdomain `rank.ibtisam.qzz.io`:

    ```
    CNAME Name:  _abc123def456.rank.ibtisam.qzz.io.
    CNAME Value: _xyz789qrs012.acm-validations.aws.
    ```

    The structure is identical. The difference only matters when entering the
    Name field in Cloudflare — not in Route 53.

!!! warning "`describe-certificate` returns `null` for `ResourceRecord`"
    ACM has not yet generated the validation record. Wait 15 to 30 seconds and
    retry. This can happen when `describe-certificate` is called immediately after
    `request-certificate`.

---

## Add the Validation CNAME to DNS

The CNAME record must be added to whichever DNS provider is currently
authoritative for the domain. Choose the path that applies.

### Option A: Route 53

Inject the CNAME directly into the hosted zone using the AWS CLI.

```bash
cat > /tmp/acm-validation.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${CNAME_NAME}",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          { "Value": "${CNAME_VALUE}" }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/acm-validation.json
```

!!! note "No trimming in Route 53 — ever"
    Route 53 accepts the full FQDN exactly as ACM returns it, including the
    trailing dot. This applies to both apex domains and subdomains. Pass
    `$CNAME_NAME` and `$CNAME_VALUE` directly with no modification.

### Option B: Cloudflare

Log in to the Cloudflare dashboard, navigate to the domain, and go to
**DNS > Records > Add record**.

The Name field behaves differently from Route 53. The table below shows exactly
what to enter for each case.

| | Apex domain (`ibtisam.qzz.io`) | Subdomain (`rank.ibtisam.qzz.io`) |
|---|---|---|
| **ACM returns (Name)** | `_abc123.ibtisam.qzz.io.` | `_abc123.rank.ibtisam.qzz.io.` |
| **Enter in Cloudflare Name field** | `_abc123.ibtisam.qzz.io` (trailing dot stripped automatically) | `_abc123.rank` (strip `.ibtisam.qzz.io.` suffix) |
| **ACM returns (Value)** | `_xyz789.acm-validations.aws.` | `_xyz789.acm-validations.aws.` |
| **Enter in Cloudflare Target field** | `_xyz789.acm-validations.aws` (trailing dot stripped automatically) | `_xyz789.acm-validations.aws` (trailing dot stripped automatically) |
| **Proxy status** | DNS only (grey cloud) | DNS only (grey cloud) |

!!! warning "Grey cloud is mandatory for the validation CNAME"
    Set proxy status to **DNS only** on this record. If the record is proxied
    (orange cloud), Cloudflare rewrites the DNS response and ACM cannot read the
    actual CNAME value. The certificate stays in `PENDING_VALIDATION`
    indefinitely.

!!! info "Why the Name field differs between Route 53 and Cloudflare"
    Route 53 stores records relative to the hosted zone and accepts the full
    FQDN. Cloudflare's UI expects only the part relative to the zone root; it
    appends the apex domain internally. For a subdomain certificate this means
    stripping the apex domain suffix from the Name before saving. Both providers
    result in the same DNS record on the wire.

---

## Wait for Issuance

Block until ACM confirms ownership and issues the certificate.

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION"

echo "Certificate issued."
```

The waiter polls every 60 seconds with a maximum of 40 attempts (40 minutes
total). In practice, issuance takes 2 to 5 minutes once the CNAME is present
and NS delegation is fully propagated.

Confirm the final status.

```bash
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.{Status:Status,NotAfter:NotAfter,DomainName:DomainName}" \
  --output table
```

A `Status` of `ISSUED` and a `NotAfter` date 13 months out confirms the
certificate is valid and ready to attach.

---

## Auto-Renewal

ACM renews DNS-validated certificates automatically. The CNAME record added to
the DNS provider remains in place permanently. ACM queries it 60 days before
expiry to renew without any manual step.

!!! warning "Do not delete the validation CNAME"
    Removing the validation CNAME breaks auto-renewal. The next renewal attempt
    will fail and the certificate will eventually expire. Leave the record in
    place for the lifetime of the certificate — on both Route 53 and Cloudflare.

---

## Troubleshooting

**Certificate stays in `PENDING_VALIDATION` after 30 minutes**

Check whether NS delegation is complete.

```bash
dig NS "$DOMAIN" @8.8.8.8 +short
```

If the old nameservers are still returned, propagation has not finished. ACM
cannot find the CNAME because Route 53 is not yet authoritative.

Verify the CNAME record is present in Route 53.

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --query "ResourceRecordSets[?Type=='CNAME']" \
  --output table
```

Confirm the CNAME resolves publicly.

```bash
dig CNAME "$CNAME_NAME" @8.8.8.8 +short
```

For Cloudflare: confirm the record is set to **DNS only** (grey cloud), not
proxied (orange cloud).

**`wait certificate-validated` exits with a non-zero code**

The waiter timed out (40 minutes elapsed). Check NS delegation and CNAME
presence using the steps above, then re-run the waiter.

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION"
```

---

## Quick Reference

Copy and run the setup block. Then choose the DNS injection block that matches
the authoritative provider. Finish with the verification block.

```bash
# Set variables
DOMAIN="ibtisam.qzz.io"
REGION="us-east-1"

# Request the certificate
CERT_ARN=$(aws acm request-certificate \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "*.${DOMAIN}" \
  --validation-method DNS \
  --region "$REGION" \
  --query "CertificateArn" \
  --output text)

echo "Certificate ARN: $CERT_ARN"

# Retrieve the validation CNAME name and value
sleep 10

CNAME_NAME=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
  --output text)

CNAME_VALUE=$(aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
  --output text)

echo "CNAME Name:  $CNAME_NAME"
echo "CNAME Value: $CNAME_VALUE"
```

If DNS is on **Route 53**, capture the hosted zone ID and inject the record.
Pass `$CNAME_NAME` and `$CNAME_VALUE` as-is — no trimming required for apex or
subdomain.

```bash
# Capture hosted zone ID (Route 53 only)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)

# Inject the validation CNAME into Route 53
cat > /tmp/acm-validation.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${CNAME_NAME}",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [ { "Value": "${CNAME_VALUE}" } ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/acm-validation.json
```

If DNS is on **Cloudflare**, add the record manually in the Cloudflare dashboard
(DNS only, grey cloud). For a subdomain certificate, strip the apex domain suffix
from the Name field — see the provider table in the runbook above.

```bash
# Wait for ACM to detect the CNAME and issue the certificate
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION"

echo "Certificate issued."

# Confirm issued status
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION" \
  --query "Certificate.{Status:Status,NotAfter:NotAfter,DomainName:DomainName}" \
  --output table
```
