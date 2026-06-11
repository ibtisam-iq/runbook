# Route 53: Create a Public Hosted Zone

!!! abstract ""
    **AWS DNS delegation** — Creates a public hosted zone in Route 53 for an
    externally registered domain, retrieves the AWS nameservers, and delegates
    authority from the registrar. Run this before creating any DNS records or
    requesting ACM certificates for the domain.

    **Prerequisite:** AWS CLI configured with credentials that have
    `route53:CreateHostedZone` and `route53:GetHostedZone` permissions.

---

A public hosted zone tells Route 53 which DNS records to serve for a domain.
The zone itself does not make Route 53 authoritative. Authority is transferred
only after the registrar's nameserver entries are replaced with the four AWS
nameservers assigned to the zone.

---

## Set the Domain Variable

Set the domain name once and reference it throughout the workflow.

```bash
DOMAIN="ibtisam.qzz.io"
```

!!! note "Subdomain as a zone"
    A hosted zone can be created for a subdomain (`ibtisam.qzz.io`) without
    owning the parent zone in Route 53. The registrar delegation still works the
    same way: point the subdomain's NS records at the AWS nameservers.

---

## Create the Hosted Zone

Create the public hosted zone. The `--caller-reference` must be unique per
request; using the current Unix timestamp is sufficient.

```bash
aws route53 create-hosted-zone \
  --name "$DOMAIN" \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config Comment="Public hosted zone for ${DOMAIN}",PrivateZone=false
```

The response includes the zone ID, the four NS records, and the SOA record.
Capture the zone ID from the output.

`ResourceRecordSetCount: 2` confirms the NS and SOA records are created
automatically. `ChangeInfo.Status: PENDING` is normal — Route 53 propagates
the zone internally within seconds.

Capture the zone ID from the output.

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"
```

!!! warning "Trailing dot in Name field"
    Route 53 appends a trailing dot to all zone names (`ibtisam.qzz.io.`). The
    JMESPath query above includes it. Omitting the trailing dot causes the query
    to return empty.

---

## Retrieve the Assigned Nameservers

Fetch the four NS records AWS assigned to the zone.

```bash
aws route53 get-hosted-zone \
  --id "$HOSTED_ZONE_ID" \
  --query "DelegationSet.NameServers" \
  --output table
```

Copy all four. All four are required at the registrar — omitting any one of
them can cause intermittent resolution failures.

---

## Delegate from the Registrar

Log in to the domain registrar ([DigitalPlat](https://domain.digitalplat.org/) in this case) and navigate to the nameserver management page for the domain.

**Step 1.** Remove all existing nameserver entries. For `ibtisam.qzz.io` this
meant removing the two Cloudflare nameservers:

```
bowen.ns.cloudflare.com
addilyn.ns.cloudflare.com
```

**Step 2.** Add the four AWS nameservers retrieved in the previous step.

**Step 3.** Save the changes. DigitalPlat applies nameserver updates within a
few minutes on the registrar side, but global DNS propagation takes up to 48
hours depending on upstream TTLs.

!!! warning "ACM validation depends on this step"
    Do not proceed to certificate request until NS delegation is confirmed.
    ACM DNS validation queries the authoritative nameservers for the domain.
    If Cloudflare is still authoritative, the CNAME record added to Route 53
    will not be found and the certificate will remain in `PENDING_VALIDATION`
    indefinitely.

---

## Verify Propagation

NS propagation is uneven. Different resolvers returned different answers
during the propagation window. Query Google's resolver (`8.8.8.8`) as the
primary check — it typically picks up changes faster than local ISP resolvers.

```bash
dig NS "$DOMAIN" @8.8.8.8 +short
```

When `8.8.8.8` returns AWS nameservers, propagation is complete from a
practical standpoint.

The local resolver may still return Cloudflare during this window — this is
expected and does not indicate a problem.

```bash
# Local resolver — may still return old NS during propagation
dig NS "$DOMAIN" +short
```

```
addilyn.ns.cloudflare.com.
bowen.ns.cloudflare.com.
```

```bash
# Full answer including non-authoritative flag
nslookup -type=NS "$DOMAIN"
```

```
Server:         148.113.47.48
Address:        148.113.47.48#53

Non-authoritative answer:
ibtisam.qzz.io  nameserver = addilyn.ns.cloudflare.com.
ibtisam.qzz.io  nameserver = bowen.ns.cloudflare.com.

Authoritative answers can be found from:
```

!!! tip "Propagation check tools"
    Use [dnschecker.org](https://dnschecker.org) or
    [whatsmydns.net](https://whatsmydns.net) to see propagation status across
    multiple geographic locations simultaneously.

!!! info "Why `8.8.8.8` returns AWS before the local resolver does"
    Google's resolver has a very short negative TTL cache. Local ISP resolvers
    and any resolver at a hosting provider cache the old NS records for longer.
    The `dig @8.8.8.8` check is the most reliable early indicator of propagation.

---

## Confirm the Zone is Active

Once NS records propagate, list the records in the zone to confirm Route 53
is serving the SOA and NS entries.

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --output table
```

Two records — `NS` (TTL 172800) and `SOA` (TTL 900) — confirm the zone is
healthy. Both are created automatically at zone creation time.

---

## Troubleshooting

**`dig` still returns Cloudflare nameservers**
NS propagation has not completed. Wait and recheck. If 24 hours have passed,
verify the nameserver entries at the registrar were saved correctly.

**`list-hosted-zones` returns an empty string for the zone ID**
The JMESPath query requires a trailing dot in the domain name. Confirm the
`Name` field in the list output matches `${DOMAIN}.` exactly.

**Multiple hosted zones exist for the same domain**
This happens when `create-hosted-zone` is called more than once with different
`--caller-reference` values. Identify the correct zone by creation date and
delete the duplicates.

```bash
aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].[Id,Config.Comment]" \
  --output table
```

```bash
aws route53 delete-hosted-zone --id "<DUPLICATE_ZONE_ID>"
```

---

## Quick Reference

Copy and run this block end-to-end on a machine with AWS CLI configured.
Replace `ibtisam.qzz.io` with the actual domain before running.

```bash
# Set domain
DOMAIN="ibtisam.qzz.io"

# Create the public hosted zone
aws route53 create-hosted-zone \
  --name "$DOMAIN" \
  --caller-reference "$(date +%s)" \
  --hosted-zone-config Comment="Public hosted zone for ${DOMAIN}",PrivateZone=false

# Capture the hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"

# Retrieve the four AWS nameservers to add at the registrar
aws route53 get-hosted-zone \
  --id "$HOSTED_ZONE_ID" \
  --query "DelegationSet.NameServers" \
  --output table
```

After updating nameservers at the registrar, run the verification block.

```bash
# Check propagation via Google's public resolver (fastest indicator)
dig NS "$DOMAIN" @8.8.8.8 +short

# Check via local resolver (may still show old NS during propagation window)
dig NS "$DOMAIN" +short

# Confirm Route 53 is serving NS and SOA records
aws route53 list-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --output table
```
