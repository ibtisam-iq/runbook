# ACM: Request and Validate a Public TLS Certificate via DNS

!!! abstract ""
    **TLS certificate provisioning** — Requests a public certificate from ACM
    for an apex domain and its wildcard, injects the DNS validation CNAME record
    into Route 53, and waits for ACM to confirm ownership and issue the
    certificate. Once issued, ACM auto-renews the certificate before expiry
    without further intervention.

    **Prerequisite:** A Route 53 public hosted zone must exist for the domain
    and NS delegation must be active. See
    [Create a Public Hosted Zone](../route53/hosted-zone.md).

---

ACM validates domain ownership by checking for a specific CNAME record in the
domain's authoritative DNS. The CNAME name and value are unique per certificate
request and are provided by ACM after the request is submitted. Adding this
record to Route 53 is what triggers validation and certificate issuance.

---

## Set Variables

```bash
DOMAIN="ibtisam.qzz.io"
REGION="us-east-1"   # Use us-east-1 for CloudFront; any region works for ALB

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)
```

!!! warning "Region matters for CloudFront"
    CloudFront only accepts ACM certificates from `us-east-1`. For ALB or API
    Gateway, request the certificate in the same region as the service. Requesting
    in the wrong region means the certificate will not appear in the service's
    certificate dropdown and cannot be attached.

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

Copy the `Name` and `Value` fields. Both are long, randomised strings in the
format `_<hash>.<domain>.`.

```bash
# Assign them to variables for use in the next step
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

!!! note "One CNAME covers both apex and wildcard"
    ACM issues a single CNAME validation record that satisfies both
    `ibtisam.qzz.io` and `*.ibtisam.qzz.io`. Only one record needs to be added
    to Route 53.

---

## Add the Validation Record to Route 53

Inject the CNAME into the hosted zone.

```bash
cat > /tmp/acm-validation.json <<EOF
{
  "Changes": [
    {
      "Action": "CREATE",
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

!!! tip "Idempotent re-runs"
    If the command is run a second time, it fails with `InvalidChangeBatch`
    because the record already exists. Switch `CREATE` to `UPSERT` in the JSON
    to make subsequent runs safe.

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
total). In practice, issuance takes 2 to 5 minutes once NS delegation is
full propagated.

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
Route 53 remains in place permanently. ACM queries it 60 days before expiry to
renew the certificate without any manual step.

!!! warning "Do not delete the validation CNAME"
    Removing the validation CNAME from Route 53 breaks auto-renewal. The next
    renewal attempt will fail and the certificate will eventually expire. Leave
    the record in place for the lifetime of the certificate.

---

## Troubleshooting

**Certificate stays in `PENDING_VALIDATION` after 30 minutes**

Check whether NS delegation is complete.

```bash
dig NS "$DOMAIN" @8.8.8.8 +short
```

If Cloudflare nameservers are still returned, propagation has not finished.
ACM cannot find the CNAME because Route 53 is not yet authoritative.

Verify the CNAME record was actually added to Route 53.

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --query "ResourceRecordSets[?Type=='CNAME']" \
  --output table
```

Confirm the CNAME is resolvable from the public internet.

```bash
dig CNAME "$CNAME_NAME" @8.8.8.8 +short
```

**`describe-certificate` returns `null` for `ResourceRecord`**

ACM has not yet generated the validation record. Wait 15 to 30 seconds and
retry. This can happen when `describe-certificate` is called immediately after
`request-certificate`.

**`wait certificate-validated` exits with a non-zero code**

The waiter timed out (40 minutes elapsed). Check NS delegation and CNAME
presence using the steps above, then re-run the waiter.

```bash
aws acm wait certificate-validated \
  --certificate-arn "$CERT_ARN" \
  --region "$REGION"
```
