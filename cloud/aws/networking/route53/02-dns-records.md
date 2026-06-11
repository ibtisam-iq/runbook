# Route 53: Manage DNS Records

!!! abstract ""
    **DNS record management via CLI** — Creates and updates A, CNAME, and ALIAS
    records in an existing Route 53 hosted zone using
    `change-resource-record-sets`. Run this after the hosted zone is active and
    NS delegation is confirmed.

    **Prerequisite:** A hosted zone must exist and `$HOSTED_ZONE_ID` must be set.
    See [Create a Public Hosted Zone](01-hosted-zone.md).

---

All record mutations in Route 53 go through a single API call:
`change-resource-record-sets`. The call accepts a JSON change batch that
specifies the action (`CREATE`, `UPSERT`, or `DELETE`), the record type, and
the record values. `UPSERT` is used throughout this runbook: it creates the
record if it does not exist and updates it if it does.

---

## Set Variables

```bash
DOMAIN="ibtisam.qzz.io"

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)
```

---

## A Record

Point the apex domain to a static IP address (EC2 instance or NAT gateway).

```bash
cat > /tmp/a-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          { "Value": "<EC2_PUBLIC_IP>" }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/a-record.json
```

Replace `<EC2_PUBLIC_IP>` with the actual IPv4 address.

!!! note "TTL on A records"
    A TTL of 300 seconds (5 minutes) works well during initial setup when
    the IP address may change. Increase to 3600 after the setup stabilises.

---

## ALIAS Record

Point the apex domain or a subdomain to an AWS resource (ALB, CloudFront, or
API Gateway). ALIAS records are free, support the zone apex, and return
updated IPs automatically when the target endpoint changes.

```bash
cat > /tmp/alias-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<ALB_HOSTED_ZONE_ID>",
          "DNSName": "<ALB_DNS_NAME>",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/alias-record.json
```

Replace `<ALB_HOSTED_ZONE_ID>` and `<ALB_DNS_NAME>` with the values from the
load balancer.

```bash
# Retrieve ALB details
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName!=null].[LoadBalancerName,DNSName,CanonicalHostedZoneId]" \
  --output table
```

!!! info "ALB hosted zone IDs are region-specific"
    The `CanonicalHostedZoneId` returned for the ALB is not the same as the
    Route 53 hosted zone ID. Each AWS region has a fixed hosted zone ID for
    ALBs. The `describe-load-balancers` output provides the correct value
    directly.

---

## CNAME Record

Point a subdomain to an external hostname. CNAME records cannot be used at
the zone apex.

```bash
cat > /tmp/cname-record.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.${DOMAIN}",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          { "Value": "<TARGET_HOSTNAME>" }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/cname-record.json
```

Replace `<TARGET_HOSTNAME>` with the destination hostname (e.g., a CloudFront
distribution domain or an external service endpoint).

!!! warning "CNAME at the apex"
    Creating a CNAME for the bare apex (`ibtisam.qzz.io`) is not valid DNS.
    Use an ALIAS record instead when pointing the apex to an AWS resource, or
    an A record when pointing it to a static IP.

---

## Verify Record Creation

List all records in the zone to confirm the changes were applied.

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --output table
```

Query the specific record from a public resolver.

```bash
# Check A or ALIAS record
dig A "$DOMAIN" @8.8.8.8 +short

# Check CNAME record
dig CNAME "www.${DOMAIN}" @8.8.8.8 +short
```

---

## Troubleshooting

**Change returns `InvalidChangeBatch`**
The JSON structure in the change batch is malformed, or the `Name` field
includes a trailing dot that Route 53 is rejecting in this context. Validate
the JSON before submitting.

```bash
cat /tmp/a-record.json | python3 -m json.tool
```

**Record created but `dig` returns nothing**
NS propagation may still be in progress. Confirm the zone is authoritative
first by checking `dig NS $DOMAIN +short` before querying for individual
records.

**ALIAS record returns `InvalidInput` for the hosted zone ID**
The ALB `CanonicalHostedZoneId` was likely confused with the Route 53 hosted
zone ID. These are different values. Use `describe-load-balancers` to retrieve
the correct ALB hosted zone ID.
