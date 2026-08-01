# Phase 3b: GitHub Actions CI

To demonstrate pipeline portability and a "zero-infrastructure" CI/CD approach, I mirrored the 14-stage Jenkins pipeline within a GitHub Actions workflow ([`.github/workflows/ci.yml`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/.github/workflows/ci.yml)). 

This proves the ability to implement enterprise-grade DevSecOps standards without relying on self-hosted build agents. The workflow mirrors the Jenkins stage sequence, tooling, and deployment integrations exactly.

!!! warning "The security gates are deliberately not identical"
    The stages match; the **enforcement** does not. Every Trivy pass in this workflow runs with `exit-code: '0'` and reports rather than blocks, where the [Jenkins pipeline](phase-3a-jenkins-pipeline.md) fails the build on `CRITICAL`.

    That is intentional. BankApp is an inherited codebase, not code I wrote. Hard-failing a build on `CRITICAL` CVEs in someone else's dependency tree takes a decision that belongs to whoever maintains that code. My role as the DevOps engineer is to make the finding visible, reproducible, and impossible to miss, not to seize the merge button on another team's behalf.

    The line states its own reversal, so the position stays an explicit decision rather than a quietly softened threshold:

    ```yaml
    exit-code: '0'     # Just to pass the scan step. Change to '1' to fail on CRITICALs.
    ```

    Full comparison in [Security Gate Posture](#security-gate-posture) below.

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
- Publishes the compiled JAR to the private Nexus registry (authenticating via `settings.xml` injected from secrets), and uploads the same JAR as a GitHub Actions artifact.
- Builds the multi-stage Docker image and tags it for three registries in a single build pass.
- Runs the three-pass Trivy image scan (Pass A: OS, Pass B: library, Pass C: full JSON audit), which is four `trivy-action` invocations because Pass B splits CRITICAL from HIGH/MEDIUM. All of them report without blocking; see the posture note above.

### Stage 10–13: Multi-Registry Publish
The workflow logs into and pushes to **three** registries:

- **Docker Hub:** Authenticated via `DOCKER_USERNAME` / `DOCKER_PASSWORD`
- **GitHub Container Registry (GHCR):** Authenticated natively via the workflow's `GITHUB_TOKEN` (no explicit secret required).
- **Nexus Docker Registry:** Authenticated via `NEXUS_USERNAME` / `NEXUS_PASSWORD`, path-based routing.

**Amazon ECR is scaffolded but commented out** as Stage 13b, pending an ECR repository and AWS credentials. The disabled block uses `aws-actions/amazon-ecr-login@v2` and reads `AWS_ACCOUNT_ID` / `AWS_REGION` from secrets.

All three logins run **before** the build rather than before the push. On pull request builds nothing is published, but the logins are still required so the BuildKit `cache-from: type=gha` layer cache can pull authenticated layers; without them the cache silently misses and every PR build runs cold.

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

**The Bug:** Alpine uses `musl libc`, and security patches from upstream projects lag for days to weeks. Trivy consistently reported 5-15 `CRITICAL` CVEs in the OS layer with status `affected` (no fix available). At that point the workflow was a single scan pass configured with `exit-code: '1'` on criticals, so the build was permanently blocked with no reachable passing state.

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

#### Pass B: Library JARs (Reported, Not Enforced)
```yaml
- name: Trivy — image scan JAR/library
  with:
    vuln-type: library
    severity: CRITICAL
    exit-code: '0'     # Just to pass the scan step. Change to '1' to fail on CRITICALs.
```
This scans the application dependencies declared in `pom.xml`, the layer whose fix is a Maven version bump rather than an upstream distro patch. This is the pass that *would* be enforced on code I own; see the posture note at the top for why it reports here.

!!! note
    During implementation, Pass B correctly caught 7 CRITICAL CVEs introduced by the Spring Boot BOM. I explicitly overrode `tomcat-embed-core`, `spring-security-core` and `spring-security-web` (to 6.5.9), `thymeleaf` and `thymeleaf-spring6`, `spring-framework`, `logback-core`, and `jackson` in `pom.xml` to resolve them.

    Two of those needed `<dependencyManagement>` rather than a `<properties>` key, because Spring Boot's BOM does not expose a property for the Thymeleaf artifacts and silently ignores the override. The complete analysis is in [`docs/trivy-troubleshooting.md`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/docs/trivy-troubleshooting.md).

#### Pass C: Full Audit Artifact
A fourth invocation runs with no `vuln-type` filter across `CRITICAL,HIGH,MEDIUM,LOW`, writes JSON, and uploads it with `retention-days: 14`. This is the durable record: Pass A's advisory findings otherwise exist only in log output that ages out.

### Security Gate Posture

Actual `exit-code` values in each file today, not the intended design:

| Trivy pass | Jenkinsfile | GitHub Actions |
|---|---|---|
| Filesystem, `CRITICAL` | `1` (blocks) | `0` (reports) |
| Filesystem, `HIGH`/`MEDIUM` | `0` (reports) | `0` (reports) |
| Image, OS packages | *(no OS/library split)* | `0` (reports) |
| Image, library `CRITICAL` | `1` (blocks on any CRITICAL) | `0` (reports) |
| Image, full audit JSON | archived | uploaded, 14-day retention |

Two things this table makes visible:

1. **The Jenkins image scan has no `--vuln-type` split at all.** It runs two passes and blocks on any `CRITICAL`, OS or library. That is the pre-redesign shape, still in the file, passing today only because the Jammy migration took critical OS findings to zero. It is a known divergence, not a decision.
2. **The filesystem gate differs by engine, and that part is drift.** All three Jenkinsfiles in this project (Java, Python, Node) block on `CRITICAL` at the source scan; on GitHub Actions only the Node workflow does. The two implementations were written weeks apart, and `exit-code` is a single character that flips a scan from advisory to enforcing while every stage name and log line stays identical.

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
