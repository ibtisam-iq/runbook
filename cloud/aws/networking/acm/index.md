# ACM

Runbooks for provisioning public TLS certificates through AWS Certificate
Manager, operated entirely via the AWS CLI. ACM certificates are used with
ALB, CloudFront, API Gateway, and any other AWS service that terminates TLS.

---

## What This Section Covers

I document here the certificate request and DNS validation workflow I ran
across real projects. ACM auto-renews DNS-validated certificates, making DNS
validation the preferred method for any certificate that must stay valid
beyond 90 days without manual intervention.

---

## Runbooks

- [**Request and Validate a Public TLS Certificate via DNS**](certificate-dns-validation.md) — Request a certificate for apex and wildcard, inject the CNAME validation record into Route 53, and wait for issuance
