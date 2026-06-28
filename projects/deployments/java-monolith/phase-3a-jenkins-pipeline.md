# Phase 3a: Jenkins CI Pipeline

With the application successfully containerized, the next phase is automating the build, scan, and publish lifecycle. I engineered a robust, declarative Jenkins pipeline running on a self-hosted CI/CD stack (Jenkins, SonarQube, and Sonatype Nexus). 

The [`Jenkinsfile`](https://github.com/ibtisam-iq/java-monolith-app/blob/main/Jenkinsfile) in this repository represents a mature, enterprise-grade DevSecOps pipeline consisting of **14 sequential stages**.

## The 14-Stage Architecture

The pipeline strictly enforces security and quality at every step, ensuring that only highly-tested, vulnerability-free code makes it to the deployment registries.

### Stage 1: Checkout
The pipeline pulls the source code directly from the triggering SCM event. This ensures that `GIT_COMMIT` and `GIT_BRANCH` variables perfectly match the specific commit being tested, which is critical for downstream OCI labeling.

### Stage 2: Trivy Filesystem Scan (Fail-Fast)
Before wasting compute time compiling Java code, Trivy scans the raw repository for hardcoded secrets, misconfigurations, and known CVEs in declared dependencies (`pom.xml`).
- **Pass A (Critical):** Any critical secret or misconfig instantly fails the pipeline (`exit-code 1`).
- **Pass B (Advisory):** High and Medium vulnerabilities are printed to the console but do not break the build.

### Stage 3: Dynamic Versioning
The pipeline avoids generic `v${BUILD_NUMBER}` tags. It computes a highly traceable artifact tag based on the `pom.xml` version, the short Git SHA, and the Jenkins build ID (e.g., `0.0.1-SNAPSHOT-ab3f12c-42`). This guarantees absolute traceability from a deployed container back to the exact line of code.

### Stage 4: Build & Test
The application is compiled and unit-tested using Maven. JaCoCo runs automatically during the test phase to generate coverage reports.

### Stage 5: SonarQube Analysis
Static application security testing (SAST) and code quality analysis are executed via the `sonar-maven-plugin`. The JaCoCo XML reports are consumed here to measure test coverage.

### Stage 6: Quality Gate
The pipeline halts and waits for the SonarQube webhook to return a pass/fail result. If the code debt exceeds the configured threshold (e.g., coverage drops below 80% or new vulnerabilities are detected), the pipeline aborts.

### Stage 7: Publish JAR to Nexus
The verified `SNAPSHOT` or `RELEASE` artifact is published to the self-hosted Sonatype Nexus Maven repository.

### Stage 8: Docker Build
The multi-stage `Dockerfile` is built. The dynamic image tag from Stage 3 is applied, and OCI-compliant labels (including `org.opencontainers.image.revision`) are injected so the container metadata permanently reflects the source commit.

### Stage 9: Trivy Image Scan (Hard Gate)
A second Trivy scan is performed on the fully built Docker container. This is a **hard security gate**. Any `CRITICAL` OS or library CVE detected inside the final image immediately fails the pipeline (`exit-code 1`), preventing vulnerable code from ever reaching a registry.

### Stages 10–13: Multi-Registry Publish
If all tests and security gates pass, and the pipeline is running on the `main` branch, the verified Docker image is pushed to four distinct registries to demonstrate multi-cloud artifact management:
- **Stage 10:** Docker Hub
- **Stage 11:** GitHub Container Registry (GHCR)
- **Stage 12:** Amazon Elastic Container Registry (ECR)
- **Stage 13:** Nexus Docker Registry

### Stage 14: GitOps CD Trigger
The final stage bridges Continuous Integration to Continuous Deployment. The pipeline clones the CD repository (`platform-engineering-systems`), updates the `image.env` file with the newly generated Docker tag, and commits the change back to GitHub. This commit automatically triggers the downstream deployment tools (ArgoCD/Flux).

---

## Architectural Optimizations & Decisions

During the development of this pipeline, I implemented several specific architectural optimizations to elevate it to production standards:

### 1. Removing the `tools {}` Block
In early iterations, the pipeline relied on Jenkins' UI-managed tools registry to inject Maven and JDK paths. I removed the `tools` block entirely. In a mature environment, dependencies like Maven, JDK 21, Docker, and Trivy are provisioned system-wide on the Jenkins host OS. Relying on the OS `PATH` makes the pipeline far more portable and aligns with Infrastructure-as-Code principles.

### 2. Maven-Driven SonarQube Integration
Previously, the pipeline executed SonarQube using the standalone scanner binary, requiring a brittle `SCANNER_HOME` path resolution. I eliminated the standalone binary and switched to the `sonar-maven-plugin`. Maven inherently understands the project structure, target classes, and JaCoCo coverage reports, making the analysis significantly more robust with zero manual path configuration.

### 3. Pipeline Behavior Controls
A production pipeline must behave predictably on a shared server. I introduced an explicit `options {}` block:
- **Concurrency Management:** `disableConcurrentBuilds(abortPrevious: true)` ensures that if two developers push simultaneously, the older build is immediately aborted, preventing race conditions during Docker pushes.
- **Artifact Rotation:** Discarding Trivy JSON reports after 5 builds prevents the Jenkins master disk from silently filling up over time.
