# Route 53

Runbooks for managing DNS through Amazon Route 53, operated entirely via the
AWS CLI. This covers hosted zone creation, NS delegation to an external
registrar, and DNS record management.

---

## Runbooks

- [**Create a Public Hosted Zone**](01-hosted-zone.md) — Create a hosted zone, retrieve AWS nameservers, and delegate DNS from an external registrar
- [**Manage DNS Records**](02-dns-records.md) — Create and update A, CNAME, and ALIAS records via `change-resource-record-sets`
