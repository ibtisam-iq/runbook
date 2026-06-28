# Phase 3b: GitHub Actions CI

To demonstrate pipeline portability and a "zero-infrastructure" CI/CD approach, I mirrored the 14-stage Jenkins pipeline within a GitHub Actions workflow ([`.github/workflows/ci.yml`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.github/workflows/ci.yml)). 

This proves the ability to implement enterprise-grade DevSecOps standards without relying on self-hosted build agents. The workflow is functionally identical to the Jenkins architecture, maintaining the exact same strict security gates, quality checks, and deployment integrations.

## The 14-Stage Mirror Architecture

The GitHub Actions workflow executes the identical 14 stages as Jenkins, mapped directly to GitHub Actions syntax:

### Stage 1–3: Checkout, Scan & Versioning
- Uses `actions/checkout@v4` with `fetch-depth: 0` to preserve Git blame for SonarQube.
- Executes `aquasecurity/trivy-action` across the repository to scan for hardcoded secrets and misconfigurations.
- Dynamically extracts the `<version>` from `pom.xml` using `mvn help:evaluate` and computes the exact same `pomVersion-gitSha-buildNumber` tag used in Jenkins.

### Stage 4–6: Build, Test & Quality Gate
- Uses `actions/setup-java@v4` with the `temurin` distribution (Java 21) and enables native Maven dependency caching.
- Executes the `sonar-maven-plugin` using the `SONAR_HOST_URL` and `SONAR_TOKEN` injected via GitHub Secrets.
- Because SonarQube runs on the self-hosted network, GitHub Actions leverages a publicly exposed webhook to wait for the Quality Gate status, successfully bridging the SaaS runner to the private Sonar instance.

### Stage 7–9: Artifacts, Build & Image Scan
- Publishes the compiled JAR to the private Nexus registry (authenticating via `settings.xml` injected from secrets).
- Builds the multi-stage Docker image and tags it for four distinct registries.
- Runs the hard-gate Trivy image scan. Any critical vulnerabilities immediately fail the workflow (`exit-code 1`).

### Stage 10–13: Multi-Registry Publish
The workflow logs into and pushes to four different registries:
- **Docker Hub:** Authenticated via `DOCKER_USERNAME` / `DOCKER_PASSWORD`
- **GitHub Container Registry (GHCR):** Authenticated natively via the workflow's `GITHUB_TOKEN` (no explicit secret required).
- **Amazon ECR:** Authenticated via `aws-actions/configure-aws-credentials`.
- **Nexus Docker Registry:** Authenticated via `NEXUS_USERNAME` / `NEXUS_PASSWORD`.

### Stage 14: GitOps CD Trigger
The final stage bridges GitHub Actions to Continuous Deployment. The workflow leverages a `GIT_TOKEN` with repository scopes to check out the external `platform-engineering-systems` CD repository, inject the new image tag into `systems/java-monolith/image.env`, and commit the changes to trigger ArgoCD.

---

## Architectural Challenges & Troubleshooting

Translating the logic to GitHub Actions exposed several unique architectural challenges that required explicit engineering compared to Jenkins.

### Workflow Concurrency Controls

In Jenkins, I disabled concurrent builds. In GitHub Actions, I implemented a more nuanced concurrency control scoped specifically to Pull Requests:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```
**The Rationale:** Canceling in-progress runs on `main` is dangerous. If a second push lands while the first run is mid-registry-push, the first run is aborted, potentially leaving a corrupt or missing `:latest` tag in the registries. PR builds have no write side-effects, so cancellation is safe and desirable there to save compute minutes.

### Challenge 1: Trivy and the Alpine Base Image

Initially, the pipeline failed on the Trivy image scan. The runtime image was based on `eclipse-temurin:21-jre-alpine`. 

**The Bug:** Alpine uses `musl libc`, and security patches from upstream projects lag for days to weeks. Trivy consistently reported 5-15 `CRITICAL` CVEs in the OS layer with status `affected` (no fix available). Because the pipeline is configured to `exit-code: '1'` on criticals, the build was permanently blocked.

**The Fix:** I migrated the runtime stage to `eclipse-temurin:21-jre-jammy` (Ubuntu 22.04 LTS). Canonical patches `glibc` vulnerabilities within hours, resulting in zero critical OS-level CVEs and allowing the pipeline to pass.

### Challenge 2: The Multi-Pass Scan Architecture

A Docker image contains two completely different layers of software with different ownership. I redesigned the Trivy scan into three distinct passes to reflect this:

#### Pass A: OS Packages (Warn Only)
```yaml
- name: Trivy — image scan OS packages
  with:
    vuln-type: os
    severity: CRITICAL,HIGH
    exit-code: '0'
```
Failing the build on OS CVEs blocks the pipeline on issues outside developer control. This pass reports vulnerabilities but never fails.

#### Pass B: Library JARs (Fail on Critical)
```yaml
- name: Trivy — image scan JAR/library
  with:
    vuln-type: library
    severity: CRITICAL
    exit-code: '1'
```
This scans the application dependencies declared in `pom.xml`. Any CRITICAL CVE here fails the build immediately because the developer owns the fix (bumping the Maven version).

!!! note
    During implementation, Pass B correctly caught 7 CRITICAL CVEs introduced by the Spring Boot BOM. I had to explicitly override versions for `tomcat-embed-core`, `spring-security-web` (to 6.5.9), and `thymeleaf` in `pom.xml` to resolve them. The complete override analysis is documented in `docs/trivy-troubleshooting.md`.

### Challenge 3: SonarQube and Deprecated APIs

During a routine pipeline run following the Spring Security 6.5.9 upgrade, the SonarQube Quality Gate failed, blocking artifact creation.

**The Bug:** SonarQube flagged rule `java:S5738` (*"@Deprecated code marked for removal should never be used"*) on the following line in `SecurityConfig.java`:
```java
.logoutRequestMatcher(new AntPathRequestMatcher("/logout"))
```
Because the Quality Gate allows 0 new issues on new code, the pipeline aborted.

**The Fix:** The code was not functionally broken, but `AntPathRequestMatcher` was flagged `forRemoval=true` in Spring Security 6.x. I refactored the class to use the officially supported API:
```java
.logoutUrl("/logout")
```
This internally handles the path matching, resolved the SonarQube maintainability risk, and returned the pipeline to a green state.
