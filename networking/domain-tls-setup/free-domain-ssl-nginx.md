# Free Domain, Let's Encrypt SSL, and Nginx HTTPS

**End-to-end HTTPS with a free domain** — Register a free subdomain on
[freedomain.one](https://freedomain.one) (backed by dnsexit.com), issue a
wildcard Let's Encrypt certificate via their DNS-01 challenge panel,
point the domain at a server with a public IP, and serve the
domain over HTTPS with Nginx.

**Discovery**

I was writing the [Route 53 hosted zone runbook](../../cloud/aws/networking/route53/create-hosted-zone.md) and, while drafting the registrar delegation section in Antigravity (my IDE), the autocomplete suggested `freedomain.one` inline. I opened the site, verified it was real, signed up, registered `ibtisam.work.gd` at no cost, and ran the full operation as documented below. Thanks to [freedomain.one](https://freedomain.one) and [dnsexit.com](https://dnsexit.com) for the free service.

**Prerequisites:**

- A server with a static public IP and Nginx installed.
- Inbound rules for TCP 80 and TCP 443 open on the server's firewall or security group.
- A browser to complete the freedomain.one panel steps.

---

## What freedomain.one Provides

[freedomain.one](https://freedomain.one) (operated by dnsexit.com) provides
free subdomains under several public TLDs, with no ads, no cost, and built-in
support for Dynamic DNS and Let's Encrypt certificate issuance.

Available TLDs at registration time:

| TLD | Fit |
|---|---|
| `work.gd` | General lab or workspace use |
| `publicvm.com` | Public VM or demo host |
| `run.place` | Generic deployment or service |
| `2bd.net` | Short, brandable |
| `linkpc.net` | Machine-linking or remote access |
| `jo3.org` | Short personal identifier |

I chose `work.gd` as the TLD and registered `ibtisam.work.gd`.

---

## Step 1 — Register the Domain

Sign up at [freedomain.one](https://freedomain.one). During registration,
enter the desired subdomain name, select the TLD, and check availability.
When the domain shows **Available**, claim it.

The registration form shows:

| Field | Value |
|---|---|
| Domain name | `ibtisam.work.gd` |
| Registration Term | 1 Year |
| Expiration Date | 2027-06-12 (free renew after 2027-05-12) |
| Total | $0.00 |
| IP for the domain | 39.49.208.173 |
| Is Dynamic IP? | Unchecked |

!!! info "Dynamic IP"
    DDNS automatically updates the A record when the public IP changes.
    Leave this unchecked when pointing at a server with a fixed IP. Enable
    it only when hosting from a connection where the ISP assigns a changing IP.

!!! note "Free renewal policy"
    Renewal is free but must happen within the 30-day window before expiry.
    It can only be extended by 1 year at a time.

Click **Submit**. The domain is now registered and a DNS A record is created
pointing at the IP entered in the form.

---

## Step 2 — Issue the Let's Encrypt SSL Certificate

With the domain registered, I opened the **Services** panel for
`ibtisam.work.gd` and requested a free wildcard certificate. It is free.

1. Navigate to the **Domain Panel** in the DNS control panel.
2. Scroll down to `SSL Digital Certificate (free)` and click **sign up** button to issue a wildcard certificate for `ibtisam.work.gd` and `*.ibtisam.work.gd`.

The panel runs `acme.sh` internally with a DNS-01 challenge. It adds
`_acme-challenge.ibtisam.work.gd` TXT records automatically, then polls
for propagation before completing the Let's Encrypt handshake.

### ACME Loop Did Not Complete on First Attempt

The issuance page showed a repeating loop and did not complete:

```
....TXT Wait....CHECK _acme-challenge.ibtisam.work.gd on 31.14.40.88 ...
....TXT Wait....CHECK _acme-challenge.ibtisam.work.gd on 31.14.40.88 ...
```

Running a TXT lookup showed two records were present:

```bash
dig TXT _acme-challenge.ibtisam.work.gd +short
```

```
"GEi08gtvIvocJJd08hqwALssGho-uRlXeSSb4zny91c"
"L7sukDDSnSxGRdzKnxY59bTV91r_4H6_iKlHVexqPnM"
```

!!! note "Two TXT records is normal for a wildcard certificate"
    A wildcard cert covering both `ibtisam.work.gd` and `*.ibtisam.work.gd`
    requires two separate ACME challenges, so two `_acme-challenge` TXT
    records are expected. The loop appeared to be a timing or propagation
    delay on the first attempt, not a duplication error.

**Fix:** deleted both TXT records from the DNS panel, re-triggered issuance,
and waited for propagation. The second attempt completed successfully.

### Certificate Bundle

Once issued, the SSL panel exposes four sections:

| Section | What it is | Used on server |
|---|---|---|
| **SSL Cert** | Leaf certificate (public key + domain info) | Yes, as `cert.pem` |
| **SSL Intermediate CA** | Intermediate chain from Let's Encrypt | Yes, as `chain.pem` |
| **SSL Private Key** | Private key matching the cert | Yes, as `privkey.pem` |
| **Domain CSR** | Certificate Signing Request used at issuance | No, reference only |

The bundle can also be downloaded as a zip from the panel.

!!! danger "Protect the private key"
    The SSL Private Key must never be committed to version control, logged,
    or shared. Anyone with the key can impersonate the domain.

The certificate covers `ibtisam.work.gd` and `*.ibtisam.work.gd`.
Valid for 90 days from `2026-06-12` to `2026-09-10`. Renew via the panel
within the 30-day window before expiry.

---

## Step 3 — Launch the Server and Point the A Record

I launched an EC2 instance (Ubuntu, Nginx installed), noted its public IP
(`54.157.3.213`), and updated the A record in the dnsexit DNS panel:

| Host / A Record | IP Address | TTL |
|---|---|---|
| `ibtisam.work.gd.` | `54.157.3.213` | 08:00 |

### Confirm HTTP Works Before Enabling HTTPS

Before touching TLS, I verified the domain resolved and Nginx was reachable
over plain HTTP:

```bash
dig A ibtisam.work.gd +short
# returned 54.157.3.213

curl -I http://ibtisam.work.gd
# returned HTTP/1.1 200 OK with the default Nginx page
```

Both the server IP and the domain served the default Nginx page over HTTP.
A record propagation was confirmed working.

---

## Step 4 — Install the Certificate on Nginx

With HTTP confirmed working, the objective was to enable HTTPS. I SSH'd into
the server and ran the following.

### Create the Certificate Directory

```bash
sudo mkdir -p /etc/nginx/ssl/ibtisam.work.gd
sudo chmod 700 /etc/nginx/ssl/ibtisam.work.gd
```

### Write the Certificate Files

Open each file in vim, paste the corresponding PEM block from the dnsexit
panel, and save.

```bash
sudo vim /etc/nginx/ssl/ibtisam.work.gd/cert.pem         # paste SSL Cert block
sudo vim /etc/nginx/ssl/ibtisam.work.gd/chain.pem        # paste SSL Intermediate CA block
sudo vim /etc/nginx/ssl/ibtisam.work.gd/privkey.pem      # paste SSL Private Key block
sudo chmod 600 /etc/nginx/ssl/ibtisam.work.gd/privkey.pem
```

!!! note "PEM headers and footers are required"
    Each file must start with `-----BEGIN ...-----` and end with
    `-----END ...-----`. Partial blocks cause Nginx to fail at startup.

### Build the Full Chain

Nginx expects a single file with the leaf certificate followed by the
intermediate chain.

```bash
sudo bash -c 'cat /etc/nginx/ssl/ibtisam.work.gd/cert.pem \
  /etc/nginx/ssl/ibtisam.work.gd/chain.pem \
  > /etc/nginx/ssl/ibtisam.work.gd/fullchain.pem'
```

### Configure Nginx for HTTPS

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
    On Nginx 1.25+ the inline `listen 443 ssl http2` form is deprecated.
    Omit it or use the standalone `http2` directive to avoid the warning
    during `nginx -t`.

Enable the site and reload:

```bash
sudo ln -s /etc/nginx/sites-available/ibtisam.work.gd \
           /etc/nginx/sites-enabled/ibtisam.work.gd
sudo nginx -t
sudo systemctl reload nginx
```

### Fix 403 Forbidden

After reloading, `curl https://ibtisam.work.gd` returned `HTTP/2 403`.
No listener was blocking port 443 — Nginx was listening, but could not find
the index file. The config listed `index.html`, but Ubuntu's default Nginx
install ships only `index.nginx-debian.html`.

```bash
ls /var/www/html
# index.nginx-debian.html   <-- this exists, index.html does not
```

Fix: create `index.html` explicitly.

```bash
echo 'Hello from ibtisam.work.gd over HTTPS' | sudo tee /var/www/html/index.html
sudo chown www-data:www-data /var/www/html/index.html
sudo chmod 644 /var/www/html/index.html
sudo systemctl reload nginx
```

---

## Step 5 — Verify HTTPS End-to-End

```bash
curl -v https://ibtisam.work.gd
```

Key lines from the output confirming everything worked:

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

`HTTP/2 200` with the response body confirms DNS, TLS, and Nginx are all
working correctly.

---

## Troubleshooting

**`ERR_CONNECTION_REFUSED` on HTTPS**
Nginx is not listening on 443, or the firewall/security group blocks inbound
TCP 443. Confirm with `sudo ss -tlnp | grep 443` and check inbound rules.

**`HTTP/2 403` after a correct Nginx config**
Nginx served the request but could not find the index file. Verify the file
named in the `index` directive exists on disk and is readable by `www-data`.

**ACME loop does not complete**
Delete all `_acme-challenge` TXT records from the DNS panel and re-trigger
issuance. The first attempt may have stalled on propagation timing.

**`nginx -t` warns about `listen ... http2`**
The inline `http2` form is deprecated in Nginx 1.25+. Remove it or move to
the standalone `http2` directive. The warning does not block HTTPS from working.

---

## Quick Reference

```bash
# Verify A record propagation
dig A ibtisam.work.gd +short

# Check ACME challenge TXT records
dig TXT _acme-challenge.ibtisam.work.gd +short

# Test full HTTPS stack
curl -v https://ibtisam.work.gd

# Test Nginx config syntax
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Check what is listening on 443
sudo ss -tlnp | grep 443

# Inspect the installed certificate
sudo openssl x509 -in /etc/nginx/ssl/ibtisam.work.gd/fullchain.pem -noout -text | \
  grep -E 'Subject:|Issuer:|Not After|DNS:'
```
