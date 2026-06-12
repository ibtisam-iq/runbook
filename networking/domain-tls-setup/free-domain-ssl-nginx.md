# Free Domain, Let's Encrypt SSL, and Nginx HTTPS on EC2

!!! abstract ""
    **End-to-end HTTPS with a free domain** — Registers a free subdomain on
    [freedomain.one](https://freedomain.one) (backed by dnsexit.com), issues a
    wildcard Let's Encrypt certificate via DNS-01 challenge through their
    panel, installs the certificate bundle on Nginx running on an AWS EC2
    Ubuntu instance, and serves the domain over HTTPS.

    This runbook was written while working on the
    [Route 53 hosted zone runbook](../../cloud/aws/networking/route53/create-hosted-zone.md).
    While writing the registrar delegation section there, an autocomplete
    suggestion surfaced [freedomain.one](https://freedomain.one) as a free
    domain option. The domain `ibtisam.work.gd` was registered there and the
    full workflow below was completed the same session.

    **Prerequisites:**

    - An EC2 instance running Ubuntu with Nginx installed and accessible on
      port 80 via a public IP.
    - Inbound rules for TCP 80 and TCP 443 open in the EC2 security group.
    - A browser to complete the freedomain.one registration panel steps.

---

## How freedomain.one Works

freedom.one (operated by dnsexit.com) provides free subdomains under several
public TLDs. The service is 100% free, has no ads, supports custom nameservers,
Dynamic DNS, and issues Let's Encrypt certificates through a built-in panel.

Available TLDs at registration time:

| TLD | Best fit |
|---|---|
| `work.gd` | General lab or workspace use |
| `publicvm.com` | Public VM or demo host |
| `run.place` | Generic deployment or service |
| `2bd.net` | Short, brandable |
| `linkpc.net` | Machine-linking or remote access |
| `jo3.org` | Short personal identifier |

`work.gd` was chosen because it reads as a general namespace for projects and
works cleanly as a subdomain base for multiple test services.

---

## Part 1 — Register the Domain

### Choose and Claim the Name

1. Open [freedomain.one](https://freedomain.one).
2. Type the desired name in the search box and select the TLD from the dropdown.
3. Click **Check Availability**.
4. When the domain shows **Available**, click **Claim This Name**.

`ibtisam.work.gd` was chosen. It is short, personal, and works as a reusable
namespace for multiple subdomains (`demo.ibtisam.work.gd`, `api.ibtisam.work.gd`,
etc.).

!!! tip "Naming for a lab or test hub"
    Pick a name that works as a namespace, not as a single-app label. A personal
    name or a generic lab word (`devlab`, `stacklab`) avoids having to register
    a new domain every time a new project is added.

### Complete the Registration Form

The sign-up form shows the following fields:

| Field | Value used |
|---|---|
| Domain name | `ibtisam.work.gd` |
| Registration Term | 1 Year |
| Expiration Date | 2027-06-12 (free renew after 2027-05-12) |
| Total | $0.00 |
| IP for the domain | EC2 public IP (`54.157.3.213`) |
| Is Dynamic IP? | Unchecked |

!!! info "Dynamic IP explained"
    Dynamic DNS (DDNS) automatically updates the A record when the public IP
    changes. Leave this unchecked when pointing at a stable VPS or EC2
    instance with a fixed Elastic IP. Enable it only when hosting from a
    residential connection where the ISP assigns a changing IP.

!!! note "Free renewal policy"
    The domain is free indefinitely. Renewal must happen within the 30-day
    window before expiry and can only be extended by 1 year at a time.

Click **Submit**.

---

## Part 2 — Add the A Record

After registration, the DNS panel under **A / AAAA / Host** shows:

| Host / A Record | IP Address | TTL |
|---|---|---|
| `ibtisam.work.gd.` | `54.157.3.213` | 08:00 |

This was set at registration time via the IP field. If the IP needs to change
later, edit the record from the **Domain Panel** tab.

---

## Part 3 — Issue the Let's Encrypt SSL Certificate

### Trigger Certificate Issuance

1. In the dnsexit panel, navigate to the domain and open the **SSL** section.
2. Click the button to generate a wildcard certificate for `ibtisam.work.gd`
   and `*.ibtisam.work.gd`.

The panel runs `acme.sh` internally with a DNS-01 challenge. It adds a
`_acme-challenge.ibtisam.work.gd` TXT record automatically, then polls for
propagation before completing the Let's Encrypt handshake.

### Troubleshoot: Stuck ACME Loop

The issuance page showed a repeating loop:

```
....TXT Wait....CHECK _acme-challenge.ibtisam.work.gd on 31.14.40.88 ...
....TXT Wait....CHECK _acme-challenge.ibtisam.work.gd on 31.14.40.88 ...
```

After 10+ minutes, the loop had not resolved. Running a TXT lookup showed
the cause:

```bash
dig TXT _acme-challenge.ibtisam.work.gd +short
```

```
"GEi08gtvIvocJJd08hqwALssGho-uRlXeSSb4zny91c"
"L7sukDDSnSxGRdzKnxY59bTV91r_4H6_iKlHVexqPnM"
```

!!! warning "Duplicate TXT records cause ACME to loop"
    Two `_acme-challenge` TXT records were present from two separate issuance
    attempts. The ACME validator polled a resolver that returned both values
    and could not match the current expected token. The loop never exits in
    this state.

**Fix:**

1. Open the DNS panel for `ibtisam.work.gd` and navigate to the **TXT** tab.
2. Delete all existing `_acme-challenge.ibtisam.work.gd` TXT records.
3. Re-trigger certificate issuance from the SSL section.
4. After a minute, confirm only one TXT record is present:

```bash
dig TXT _acme-challenge.ibtisam.work.gd +short
```

A single token value confirms the panel added the record cleanly. Issuance
completed after propagation settled.

### Understand the Certificate Bundle

Once issued, the SSL panel exposes four sections:

| Section | What it is | Used on server |
|---|---|---|
| **SSL Cert** | Leaf certificate (public key + domain info) | Yes, as `cert.pem` |
| **SSL Intermediate CA** | Intermediate chain from Let's Encrypt | Yes, as `chain.pem` |
| **SSL Private Key** | Private key matching the cert | Yes, as `privkey.pem` |
| **Domain CSR** | Certificate Signing Request used at issuance | No, reference only |

!!! danger "Protect the private key"
    The SSL Private Key must never be committed to version control, logged,
    or shared. Anyone with the key can impersonate the domain using that
    certificate.

The cert covers:

- `ibtisam.work.gd`
- `*.ibtisam.work.gd` (wildcard)

Valid for 90 days from `2026-06-12` to `2026-09-10`. Renew via the panel
within the 30-day window before expiry.

---

## Part 4 — Install the Certificate on Nginx

All commands run on the EC2 instance (`ubuntu@ip-172-31-46-143`).

### Create the Certificate Directory

```bash
sudo mkdir -p /etc/nginx/ssl/ibtisam.work.gd
sudo chmod 700 /etc/nginx/ssl/ibtisam.work.gd
```

### Write the Certificate Files

Open each file in an editor, paste the corresponding PEM block from the
dnsexit panel, and save.

```bash
sudo vim /etc/nginx/ssl/ibtisam.work.gd/cert.pem         # paste SSL Cert block
sudo vim /etc/nginx/ssl/ibtisam.work.gd/chain.pem        # paste SSL Intermediate CA block
sudo vim /etc/nginx/ssl/ibtisam.work.gd/privkey.pem      # paste SSL Private Key block
sudo chmod 600 /etc/nginx/ssl/ibtisam.work.gd/privkey.pem
```

In vim: press `i` to enter insert mode, paste the PEM content, press `Esc`,
then type `:wq` and press `Enter`.

!!! note "Each PEM block must include the header and footer lines"
    The content must start with `-----BEGIN ...-----` and end with
    `-----END ...-----`. Truncated or partial blocks will cause Nginx to
    fail to load the certificate.

### Build the Full Chain

Nginx expects a single file containing the leaf certificate followed by the
intermediate chain.

```bash
sudo bash -c 'cat /etc/nginx/ssl/ibtisam.work.gd/cert.pem \
  /etc/nginx/ssl/ibtisam.work.gd/chain.pem \
  > /etc/nginx/ssl/ibtisam.work.gd/fullchain.pem'
```

### Configure Nginx

Create a new site config:

```bash
sudo vim /etc/nginx/sites-available/ibtisam.work.gd
```

```nginx
server {
    listen 80;
    server_name ibtisam.work.gd;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name ibtisam.work.gd;

    ssl_certificate     /etc/nginx/ssl/ibtisam.work.gd/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/ibtisam.work.gd/privkey.pem;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

!!! note "http2 directive deprecation"
    On Nginx 1.25+ the inline `listen 443 ssl http2` form is deprecated. Use
    the standalone `http2` directive instead, or simply omit it. The config
    above omits it to avoid the warning during `nginx -t`.

Enable the site and test:

```bash
sudo ln -s /etc/nginx/sites-available/ibtisam.work.gd \
           /etc/nginx/sites-enabled/ibtisam.work.gd
sudo nginx -t
sudo systemctl reload nginx
```

### Fix 403 Forbidden

After reloading, `curl https://ibtisam.work.gd` returned `HTTP/2 403`. The
cause was a missing `index.html` — Nginx found `index.nginx-debian.html` but
not the `index.html` the config listed.

**Fix:** create an `index.html` at the root:

```bash
echo 'Hello from ibtisam.work.gd over HTTPS' | sudo tee /var/www/html/index.html
sudo chown www-data:www-data /var/www/html/index.html
sudo chmod 644 /var/www/html/index.html
sudo systemctl reload nginx
```

!!! tip "Always check the index directive against what is on disk"
    Ubuntu's default Nginx install ships `index.nginx-debian.html`, not
    `index.html`. Either add `index.nginx-debian.html` to the `index`
    directive, or create `index.html` explicitly.

---

## Part 5 — Verify

```bash
curl -v https://ibtisam.work.gd
```

Expected output (key lines):

```
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519MLKEM768 / RSASSA-PSS
* ALPN: server accepted h2
*   subject: CN=ibtisam.work.gd
*   issuer: C=US; O=Let's Encrypt; CN=YR2
*   subjectAltName: "ibtisam.work.gd" matches cert's "ibtisam.work.gd"
* SSL certificate verified via OpenSSL.
< HTTP/2 200
Hello from ibtisam.work.gd over HTTPS
```

`HTTP/2 200` with the body confirms DNS, TLS, and Nginx are all working.

---

## Subdomain Naming Scheme

With a wildcard cert covering `*.ibtisam.work.gd`, add A records for each
subdomain pointing at the same EC2 IP, then add a corresponding Nginx server
block.

| Subdomain | Purpose |
|---|---|
| `demo.ibtisam.work.gd` | Frontend demo app |
| `api.ibtisam.work.gd` | Backend API service |
| `lab.ibtisam.work.gd` | Experimental workloads |
| `docs.ibtisam.work.gd` | Documentation site |
| `app1.ibtisam.work.gd` | Sample project 1 |

Each subdomain needs its own `server {}` block in Nginx (or a wildcard catch-all
block) but reuses the same `fullchain.pem` and `privkey.pem`.

---

## Troubleshooting

**`ERR_CONNECTION_REFUSED` on HTTPS**  
Nginx is not listening on port 443, or the EC2 security group is blocking
inbound TCP 443. Confirm with `sudo ss -tlnp | grep 443` and check the
inbound rules in the AWS console.

**`HTTP/2 403` after a correct Nginx config**  
Nginx served the request but could not find a matching index file in the
configured `root`. Verify the file named in the `index` directive exists
on disk and is readable by `www-data`.

**ACME issuance loop that never exits**  
Check for duplicate `_acme-challenge` TXT records with
`dig TXT _acme-challenge.<domain> +short`. More than one token means a
previous issuance attempt left a stale record. Delete all TXT records for
`_acme-challenge` in the DNS panel and re-trigger issuance.

**`nginx -t` warns about `listen ... http2`**  
The `http2` inline form is deprecated in Nginx 1.25+. Move to the standalone
`http2` directive or remove it. The warning does not prevent Nginx from
starting or serving HTTPS.

---

## Quick Reference

```bash
# Verify DNS resolution
dig A ibtisam.work.gd +short

# Verify TXT challenge record (during issuance debugging)
dig TXT _acme-challenge.ibtisam.work.gd +short

# Test HTTPS end-to-end
curl -v https://ibtisam.work.gd

# Test Nginx config syntax
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Check what is listening on 443
sudo ss -tlnp | grep 443

# Inspect the installed certificate
openssl x509 -in /etc/nginx/ssl/ibtisam.work.gd/fullchain.pem -noout -text | \
  grep -E 'Subject:|Issuer:|Not After|DNS:'
```
