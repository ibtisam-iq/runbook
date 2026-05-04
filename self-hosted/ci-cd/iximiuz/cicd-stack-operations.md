# Self‑Hosted CI/CD Stack - Jenkins, SonarQube, Nexus Operations

This runbook captures the **post‑provisioning operational steps** that turn the SilverStack CI/CD Stack into a fully functional DevSecOps platform.

It assumes the infra is already up via the [**Setup - CI/CD Stack Orchestration**](setup-cicd-stack-orchestration.md) runbook and focuses on Jenkins, SonarQube, and Nexus configuration.

![](../../../assets/screenshots/cicd-stack-dev-machine-welcome.png)

---

## Prerequisites and Assumptions

Before starting:

- The CI/CD stack playground is running from `iximiuz/manifests/cicd-stack.yml` and all four nodes are reachable from the Dev Machine.
- Per‑service rootfs images (Jenkins, SonarQube, Nexus) have passed their local health checks - systemd services are active and `/health` endpoints return `200`.
- Cloudflare Tunnels are configured so the following domains resolve with valid SSL:
    - `https://jenkins.ibtisam-iq.com`
    - `https://sonar.ibtisam-iq.com`
    - `https://nexus.ibtisam-iq.com`

> Node mapping: `jenkins-server`, `sonarqube-server`, and `nexus-server` as defined in `cicd-stack.yml`.

---

## Phase 1 - Jenkins Post‑Setup

All Jenkins operations are performed on `jenkins-server` after initial login to the Jenkins UI.

### Step 1 - Install pipeline tools on the Jenkins OS

The Jenkins rootfs image includes a script `install-pipeline-tools` on `PATH` to install the CI/CD toolchain.

From an SSH session on `jenkins-server`:

```bash
sudo install-pipeline-tools
```

This installs the following tools system‑wide on the Jenkins server OS:

- Maven `3.9.15`
- Node.js `22 LTS` and npm
- Python `3.12`
- Docker `29.x`
- Trivy `0.69.3` (pinned safe version)
- AWS CLI v2
- `kubectl` `1.35`, Helm `4.1.4`
- Terraform `1.14.x`
- Ansible `core 2.20`

All tools are installed on the system `PATH`, so Jenkins can use them via shell steps without additional UI configuration.

### Step 2 - Install Jenkins plugins

This step is a **post-setup** operation. The script cannot run until Jenkins has been fully initialized - the setup wizard completed, an admin user created, and the Jenkins URL saved under **Manage Jenkins → System → Jenkins URL**.

```bash
sudo install-plugins
```

**Why it must run after setup, not before**

The script connects to Jenkins over HTTP/HTTPS using `jenkins-cli.jar`, which it downloads fresh from the running Jenkins instance on every run. This means Jenkins must be reachable, and a valid admin session must exist.

The initial admin password (written to `/var/lib/jenkins/.jenkins/secrets/initialAdminPassword`) is automatically removed by Jenkins as soon as the setup wizard is completed - so that password is intentionally not accepted here.

**How the script works**

1. **URL detection** - reads `jenkins.model.JenkinsLocationConfiguration.xml` to auto-detect the configured Jenkins URL. If no URL is found (e.g., Cloudflare tunnel not yet set up), it falls back to prompting for a URL manually (e.g., `http://localhost:8080`).
2. **Credentials** - prompts interactively for the admin username and password. The password is entered via a hidden prompt; it is never written to disk, never echoed to the terminal, and never passed as a command-line argument.
3. **Plugin installation** - invokes `jenkins-cli.jar` over WebSocket (`-webSocket` flag) to bypass reverse-proxy origin checks, then installs all plugins defined in the script.
4. **Safe restart** - triggers a `safe-restart` so all plugins become active without interrupting any running builds.

**Customization**

The plugin list inside `/usr/local/bin/install-plugins` is organized by functional category inside the script. To skip a plugin, comment out its line with `#`. To add one, append its [official plugin ID](https://plugins.jenkins.io) in the relevant section.

This step is optional if a fully manual UI-based installation is preferred, but the script is the recommended path for consistency across environments.

---

## Phase 2 - Jenkins Initial Configuration

### Step 3 - Unlock the built‑in node

By default Jenkins restricts the built‑in node. Enable it to run jobs:

1. In Jenkins UI: `Manage Jenkins → Nodes → Built-In Node → Configure`
2. Set:  `Number of executors: 2`


### Step 4 - Set Jenkins URL

Ensure Jenkins uses the public URL (required for SonarQube webhooks and other callbacks):

1. In Jenkins UI: `Manage Jenkins → System → Jenkins URL`
2. Set:  `https://jenkins.ibtisam-iq.com`

---

## Phase 3 - Credentials

All credentials are created under:

```text
Manage Jenkins → Credentials → System →
  Global credentials (unrestricted) → Add Credentials
```

### Credential 1 - SonarQube token

Create a dedicated CI user in SonarQube first:

1. In SonarQube UI:  `Administration → Security → Users → Create User`
    - Login: `jenkins-ci`
    - Name:  `Jenkins CI`
    - Password: strong password

2. As `jenkins-ci`, generate a token:

   ```text
   My Account → Security → Generate Token
   Name:  jenkins-token
   Type:  User Token
   ```

3. Add to Jenkins as a **Secret text** credential:

   ```text
   Kind:    Secret text
   Secret:  squ_xxxxxxxxxxxxxxxxxxxxxxxxxxxx   ← SonarQube token
   ID:      sonarqube-token
   ```

### Credential 2 - GitHub

Use a GitHub Personal Access Token (PAT) as the password:

1. In GitHub: `Settings → Developer settings → Personal access tokens → Tokens (classic)`
    - Scopes: `repo`, `read:org`, `workflow`.

2. Add in Jenkins as **Username with password**:

   ```text
   Kind:     Username with password
   Username: ibtisam-iq
   Password: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx   ← PAT
   ID:       github-creds
   ```

### Credential 3 - Docker Hub

Use a Docker Hub access token (not your main account password):

1. In Docker Hub: `Account Settings → Security → New Access Token`
    - Name: `jenkins-ci`
    - Scopes: Read, Write.

2. Add in Jenkins:

   ```text
   Kind:     Username with password
   Username: mibtisam
   Password: dckr_pat_xxxxxxxxxxxxxxxxxxxx
   ID:       docker-creds
   ```

### Credential 4 - Nexus

Create a dedicated CI user in Nexus:

1. In Nexus UI: `Security → Users → Create local user`
    - User ID: `jenkins-ci`
    - Password: strong password
    - Roles: `nx-admin` + `nx-anonymous`.

2. Add in Jenkins:

   ```text
   Kind:     Username with password
   Username: jenkins-ci
   Password: <nexus password>
   ID:       nexus-creds
   ```

### Credential 5 - GHCR

Create a PAT with `write:packages`:

1. In GitHub: create a PAT with `write:packages` scope.
2. Add in Jenkins:

   ```text
   Kind:     Username with password
   Username: ibtisam-iq
   Password: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ID:       ghcr-creds
   ```

> Reuse `github-creds` if its PAT already has `write:packages`.

---

## Phase 4 - Tool Configuration

### Step 5 - Register SonarQube Scanner in Jenkins

The only tool that requires explicit Jenkins UI configuration is the SonarQube Scanner (other tools are on the OS PATH).

1. In Jenkins: `Manage Jenkins → Tools → SonarQube Scanner installations → Add SonarQube Scanner`
2. Configure:

   ```text
   Name:                 sonar-scanner
   Install automatically: ✓
   Version:              SonarQube Scanner (latest)
   ```

Maven, Docker, kubectl, Helm, Terraform, Ansible, AWS CLI, etc. do **not** need entries here because they are regular binaries discovered via PATH.

---

## Phase 5 - Jenkins ↔ SonarQube Integration

### Step 6 - Add SonarQube server in Jenkins

Link Jenkins to the SonarQube instance using the previously created token:

1. In Jenkins: `Manage Jenkins → System → SonarQube servers → Add SonarQube`
2. Configure:

   ```text
   Name:               sonar-server
   Server URL:         https://sonar.ibtisam-iq.com
   Server auth token:  sonarqube-token   ← Secret text credential ID
   ```

Pipelines can now call `withSonarQubeEnv('sonar-server')` to inject scanner configuration.

### Step 7 - Configure SonarQube webhook

SonarQube must notify Jenkins when analysis completes so `waitForQualityGate` works.

1. In SonarQube UI:  `Administration → Configuration → Webhooks → Create`
2. Configure:

   ```text
   Name:   Jenkins
   URL:    https://jenkins.ibtisam-iq.com/sonarqube-webhook/
   Secret: (optional shared secret for HMAC validation)
   ```

Every analysis now triggers a POST to Jenkins at `/sonarqube-webhook/`.

> **Note:** The trailing slash at the end of the webhook URL is **mandatory**. Omitting it will cause SonarQube to fail posting the analysis result back to Jenkins, and `waitForQualityGate` will hang indefinitely.

---

## Phase 6 - Nexus Maven Settings

### Step 8 - Configure `settings.xml` via Config File Provider

Use the **Config File Provider** plugin to supply Maven with Nexus credentials without hardcoding them in source.

1. In Jenkins: `Manage Jenkins → Managed files → Add a new Config → Global Maven settings.xml`
2. Set ID:

   ```text
   ID: maven-settings
   ```

3. Use a complete `settings.xml` document:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
          https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <servers>
    <server>
      <id>maven-releases</id>
      <username>jenkins-ci</username>
      <password>nexus-password</password>
    </server>
    <server>
      <id>maven-snapshots</id>
      <username>jenkins-ci</username>
      <password>nexus-password</password>
    </server>
  </servers>
</settings>
```

4. In Jenkins pipelines, reference it via:

```groovy
withMaven(globalMavenSettingsConfig: 'maven-settings') {
  // mvn deploy ...
}
```

#### Common pitfalls

**Issue 1 - Missing XML document wrapper**

A bare `<servers>...</servers>` block without the XML preamble and `<settings>` root element is invalid; Maven will ignore it and artifact deployment will fail with 401 Unauthorized.

Wrong:

```xml
<servers>
  <server>...</server>
</servers>
```

Correct: full `settings` document as above.

**Issue 2 - Not escaping special characters in password**

Passwords containing `&`, `<`, `>`, `"` or `'` must be XML‑escaped or Maven will fail to parse `settings.xml`.

| Character | Escaped |
| --- | --- |
| `&` | `&amp;` |
| `<` | `&lt;` |
| `>` | `&gt;` |
| `"` | `&quot;` |
| `'` | `&apos;` |

Example:

```xml
<password>P@ss&amp;Word!</password>
```

---

## Phase 7 - Nexus Docker Registry

### Step 9 - Create Docker (hosted) repository

Create a Docker hosted repository in Nexus for container images.

In Nexus UI:

1. `Settings → Repository → Repositories → Create repository → docker (hosted)`
2. Configure:

   ```text
   Name:   docker-hosted
   Online: ✓
   ```

Because Nexus is behind Cloudflare Tunnel and fronted by Nginx, use **Path based routing** instead of dedicated ports:

- Under *Repository Connectors*:

  ```text
  ● Path based routing   ← selected
  HTTP:  (unchecked)
  HTTPS: (unchecked)
  ```

Docker clients then use the repository name in the URL path:

```bash
# Push
docker push nexus.ibtisam-iq.com/docker-hosted/java-monolith:1.0.0

# Pull
docker pull nexus.ibtisam-iq.com/docker-hosted/java-monolith:1.0.0
```

### Step 10 - Enable Docker Bearer Token Realm

Docker authentication requires the Bearer Token realm.

In Nexus UI:

1. `Security → Realms`
2. Move **Docker Bearer Token Realm** from *Available* to *Active*.
3. Save.

Without this, `docker login nexus.ibtisam-iq.com` will fail with 401 even with correct credentials.

---

## Phase 8 - Final Stack Readiness Checklist

After completing the steps above, the stack should be fully operational.

| What | Status |
| --- | --- |
| Jenkins running with SSL | `https://jenkins.ibtisam-iq.com` reachable |
| SonarQube running with SSL | `https://sonar.ibtisam-iq.com` reachable |
| Nexus running with SSL | `https://nexus.ibtisam-iq.com` reachable |
| 10 pipeline tools on Jenkins PATH | `mvn`, `node`, `docker`, `trivy`, `kubectl`, `helm`, `terraform`, `ansible`, `aws` available |
| Jenkins plugin bundle | Installed via `sudo install-plugins` |
| Credentials | `sonarqube-token`, `github-creds`, `docker-creds`, `nexus-creds`, `ghcr-creds` present |
| SonarQube Scanner | `sonar-scanner` configured in Jenkins Tools |
| SonarQube server | `sonar-server` configured in Jenkins |
| SonarQube webhook | Points to `/sonarqube-webhook/` on Jenkins |
| Nexus Maven settings | `maven-settings` Config File present and valid |
| Nexus Docker repository | `docker-hosted` created (path-based routing) |
| Docker Bearer Token Realm | Enabled in Nexus |

At this point, run pipelines to:

- Build projects with Maven/Node/Python.
- Run SonarQube analysis and enforce quality gates.
- Publish artifacts to Nexus (Maven + Docker).
- Optionally push container images to GHCR using `ghcr-creds`.

---

## Related Documentation

- [**Setup - CI/CD Stack Orchestration**](self-hosted-cicd-stack-operations.md) - infra/topology, manifests, Dev Machine behavior.
- [**Rootfs - Ubuntu 24.04 base**](../../../containers/iximiuz/rootfs/setup-ubuntu-24-04-rootfs-base-image.md) - foundational image shared by all nodes.
- [**Rootfs - Jenkins Server**](../../../containers/iximiuz/rootfs/setup-jenkins-rootfs-image.md) - Jenkins LTS rootfs build and local testing.
- [**Rootfs - SonarQube Server**](../../../containers/iximiuz/rootfs/setup-sonarqube-rootfs.md) - SonarQube + PostgreSQL rootfs build and healthchecks.
- [**Rootfs - Nexus Server**](../../../containers/iximiuz/rootfs/setup-nexus-rootfs-image.md) - Nexus rootfs build and validation.
