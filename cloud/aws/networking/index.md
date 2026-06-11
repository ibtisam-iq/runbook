# AWS Networking

Runbooks for AWS networking services operated directly through the AWS CLI.
This section covers Route 53 for DNS management and ACM for TLS certificate
provisioning and validation.

---

## What This Section Covers

I document here the DNS and certificate workflows I ran across real projects.
Both Route 53 and ACM were operated entirely through the CLI, with no console
interaction beyond initial credential setup.

Each runbook captures the exact sequence of commands, the variables used, and
the failure modes encountered before the setup reached a stable state.

---

## Sections

- [**Route 53**](route53/index.md) — Hosted zone creation, NS delegation, and DNS record management
- [**ACM**](acm/index.md) — Public certificate request and DNS validation
