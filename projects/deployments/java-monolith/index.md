# BankApp: Evolutionary Cloud Migration of a Java 3-Tier Monolith [EC2 Auto Scaling, ECS Fargate, Amazon EKS, Gateway API, Amazon RDS]

## Overview

I engineered a comprehensive, end-to-end DevSecOps strategy for a **3-tier, monolithic** [Java Spring Boot Banking Application](https://github.com/ibtisam-iq/java-monolith-app). While packaged and deployed as a single monolithic artifact, the application strictly adheres to a 3-tier architectural pattern (Presentation, Business logic, and Data access layers).

Instead of treating deployment as a static event, I architected this project as a **vertical cloud migration journey**. After executing a complete codebase modernization and multi-stage Docker containerization, I automated the lifecycle via 14-stage CI pipelines in Jenkins and GitHub Actions. I then orchestrated the exact same Spring Boot 3.4 artifact across four increasingly scalable compute paradigms:

1. **AWS EC2 Auto Scaling:** Provisioning the legacy baseline via virtual machines and UserData bootstrap scripts.
2. **Amazon ECS Fargate:** Refactoring the compute layer into serverless containers while maintaining the ALB networking boundary.
3. **Bare-Metal Kubernetes:** Validating the Kustomize overlay architecture and ingress decoupled through the Gateway API.
4. **Amazon EKS:** Achieving massive scale by decoupling application state to Amazon RDS and scaling horizontally via the HPA.

| Item | Value |
|------|-------|
| **Documentation (Runbook)** | [ibtisam-iq/runbook](https://github.com/ibtisam-iq/runbook) |
| **Source repo (CI)** | [ibtisam-iq/java-monolith-app](https://github.com/ibtisam-iq/java-monolith-app) |
| **CD repo** | [ibtisam-iq/platform-engineering-systems/systems/java-monolith](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith) |
| **Live App** | `https://bankapp.ibtisam-iq.com` |
| **Core Stack** | Java 21 LTS, Spring Boot 3.4.5, Spring Security, Hibernate, MySQL 8.4 |
| **CI / Security** | Jenkins (Declarative), GitHub Actions, Trivy (3-Pass Scan), SonarQube |
| **Artifact Registries**| Nexus, Amazon S3, Amazon ECR, Docker Hub, GHCR |
| **Platform / IaC** | Terraform, Kustomize, AWS CLI, Bash Bootstrap |
| **Infrastructure** | EC2 ASG, ECS Fargate, Kubernetes (kubeadm & EKS), Gateway API (ALB & Nginx), RDS, EBS `gp3` |

---

## Architecture at a Glance

This project is not a single deployment. It is an evolutionary journey demonstrating how to take a single codebase and orchestrate it across four distinct infrastructure paradigms.

```text
[ Application Source Code (Spring Boot 3.4.5 & Java 21) ]
             │
             ▼
[ DevSecOps CI Pipelines (Jenkins & GitHub Actions) ]
   ├── Code Quality: SonarQube & JaCoCo Coverage
   ├── Security: Trivy (3-Pass Scan: FS, OS Packages, Library JARs)
   └── Build: Multi-Stage Docker & Maven compilation
             │
             ▼
[ Immutable Artifact Registries ]
   ├── Maven (.jar) ──► Nexus Snapshot Repo ──► Amazon S3 (Artifact Store)
   └── Container ─────► Amazon ECR / Docker Hub / GHCR
             │
             ▼
[ Platform Engineering (CD) - Four Evolutionary Targets ]

  1. AWS EC2 Auto Scaling (Virtual Machines)
     ├── Infrastructure: VPC, IGW, NAT, Bastion (via AWS CLI)
     ├── Compute: EC2 ASG with Launch Templates
     ├── Bootstrapping: UserData pulls .jar from S3 via IAM Instance Profile
     └── Network: ALB ➔ sg-app (8000) ➔ sg-rds (3306)

  2. Amazon ECS Fargate (Serverless Containers)
     ├── Compute: Serverless Task Definitions
     ├── Bootstrapping: Pulls Image from ECR via ecsTaskExecutionRole
     ├── Observability: awslogs driver streaming to CloudWatch
     └── Network: ALB ➔ sg-ecs (8000) ➔ sg-rds (3306)

  3. Bare-Metal Kubernetes (Local/On-Prem Cluster)
     ├── Paradigm: Kustomize Overlays (base + bare-metal)
     ├── Storage: local-path HostPath PVCs for persistent testing
     ├── Network: Nginx Gateway API Fabric with cert-manager (HTTP-01)
     └── State: In-cluster MySQL StatefulSet

  4. Amazon EKS (Production Managed Kubernetes)
     ├── Paradigm: Kustomize Overlays (base + eks)
     ├── Scale: HorizontalPodAutoscaler (HPA) & Metrics Server
     ├── Network: AWS Load Balancer Controller (Gateway API) with ACM TLS
     └── State: ConfigMap patching decoupling state to Amazon RDS (MySQL 8.4)
```

---

## The Platform Engineering Differentiator

A critical factor that differentiates this project from 99.9% of standard portfolio deployments is **where and how** the work was executed. I do not rely on generic SaaS platforms like Vercel or pollute my local MacBook environment with dozens of tools. Instead, I spent months engineering my own reusable, self-hosted platform environments. 

Whenever I approach a deployment, I utilize the platforms I built from scratch:

### 1. The Custom Dev Machine
Rather than installing endless CLIs and tools on my local machine, I engineered a dedicated **SilverStack Dev Machine** hosted on [Iximiuz Labs](https://labs.iximiuz.com/playgrounds/SilverStack-dev-machine-e672bcf7). This environment comes pre-loaded with every specific tool, binary, and configuration required for my DevSecOps workflows.

### 2. Self-Hosted CI/CD Stack
The entire Jenkins pipeline, SonarQube analysis, and Nexus artifact registry are not managed services. I built and provisioned my own **[Self-Hosted CI/CD Stack](https://labs.iximiuz.com/playgrounds/SilverStack-CICD-Stack-1766a8a1)**. These tools are exposed via my custom domains (e.g., [`jenkins.ibtisam-iq.com`](https://jenkins.ibtisam-iq.com)) and are fully managed by me.

### 3. Bare-Metal Kubernetes Provisioning
For Phase 6 (Bare-Metal Kubernetes), I utilized the Iximiuz platform to simulate bare-metal servers. However, I did not use a pre-packaged cluster. I provisioned the cluster entirely from scratch using my own custom `kubeadm` scripts, documented in my **[Cluster Bootstrap Runbook](https://runbook.ibtisam-iq.com/bootstrap/kubernetes/cluster-kubeadm/)**.

### 4. AWS Provisioning vs. Strict SCP Restrictions
To deploy the AWS infrastructure (EC2 ASG, ECS, and EKS), I utilized a KodeKloud AWS subscription rather than a personal account. KodeKloud labs enforce aggressive Service Control Policies (SCPs) that outright block the creation of standard EKS Managed Node Groups via Terraform. 

To overcome this, I engineered a highly customized Terraform configuration that provisions the EKS Control Plane and attaches **Self-Managed Nodes** via custom CloudFormation stacks, completely bypassing the SCP restrictions. The logic and code to achieve this is documented in my **[EKS on KodeKloud Terraform Runbook](https://runbook.ibtisam-iq.com/iac/terraform/provisioning/eks-on-kodekloud-terraform/)**.

---

## Codebase Modernization & Database Mastery

Before engineering the pipelines or cloud infrastructure, I executed a rigorous modernization phase. I upgraded the legacy application to Spring Boot 3.4.5 and Java 21, fixed invalid `groupId`s, replaced deprecated database drivers, and injected native container health probes (`/actuator/health`) directly into the application logic to satisfy Kubernetes deployment requirements.

A critical aspect of this modernization was **Database & Environment Standardization**. I replaced all hardcoded credentials and engineered a dynamic configuration boundary. This required navigating edge cases such as correctly wrapping the `SPRING_DATASOURCE_URL` in double quotes within `.env` files to prevent shell truncation of the `&` operator. By standardizing the environment, I mastered environment-specific database resolution, seamlessly transitioning the application connection from a native bare-metal installation (`localhost`), to Docker Compose internal DNS (`db`), and finally to decoupled cloud endpoints (Amazon RDS) without altering a single line of application code.

---

## Phases

The project is thoroughly documented across 8 sequential documents. Each document contains deep, code-verified technical analysis, explaining not just *what* was done, but *why* it was designed that way.

<div class="grid cards" markdown>

- **[:material-code-json: Phase 0: Codebase Modernization](phase-0-codebase-modernization.md)**
  Spring Boot 3.4.x upgrade, Java 21, BOM-managed MySQL connectors, Actuator integration, and critical ALB application bug fixes.

- **[:material-check-all: Phase 1: Local Validation](phase-1-local-validation.md)**
  Environment variable abstraction (`.env`), dual-database testing strategies (H2 vs MySQL), and solving shell truncation bugs.

- **[:material-docker: Phase 2: Docker Containerization](phase-2-docker-containerization.md)**
  Multi-stage caching optimizations, non-root execution (`groupadd`/`useradd`), JVM container-awareness (`-XX:+UseContainerSupport`), and cold-start health check tuning.

- **[:material-pipe: Phase 3a: Jenkins CI Pipeline](phase-3a-jenkins-pipeline.md)**
  14-stage declarative pipeline, eliminating Jenkins UI `tools`, Maven-driven SonarQube analysis, and dynamic Git SHA versioning.

- **[:material-github: Phase 3b: GitHub Actions CI](phase-3b-github-actions.md)**
  Concurrency controls, Alpine-to-Jammy Trivy migrations, three-pass scan architecture (OS vs Library layer), and SonarQube API deprecation fixes.

- **[:material-server-network: Phase 4: AWS EC2 Auto Scaling](phase-4-ec2-auto-scaling.md)**
  AWS CLI VPC provisioning, strict Security Group chaining, IAM Instance Profiles, and dynamic S3 artifact retrieval via User Data scripts.

- **[:material-aws: Phase 5: Amazon ECS Fargate](phase-5-ecs-fargate.md)**
  Serverless abstractions, Task Definitions vs Launch Templates, `ecsTaskExecutionRole` ECR pulls, and `awslogs` CloudWatch integration.

- **[:material-kubernetes: Phase 6: Kubernetes Deployments](phase-6-kubernetes-deployments.md)**
  Kustomize DRY directory structures, Gateway API decoupled routing (Nginx and ALB), dynamic Storage Class patching, and Horizontal Pod Autoscaling (HPA) across both Bare-Metal and Amazon EKS.

</div>

---

## Rigorous Engineering: Key Decisions by Phase

This project represents months of dedicated engineering. Rather than simply deploying code, I systematically solved complex infrastructure and application problems at every layer. Below are the key architectural decisions made in each phase:

### Phase 0: Codebase Modernization
- **BOM-Managed Dependencies:** Upgraded to Spring Boot 3.4.x and Java 21, delegating MySQL driver versioning to the Spring Boot Bill of Materials (BOM) to eliminate deprecation debt.
- **Cloud-Native Endpoints:** Injected `spring-boot-starter-actuator` to expose `/actuator/health`, an absolute prerequisite for subsequent Docker `HEALTHCHECK` instructions and Kubernetes liveness probes.
- **ALB Edge-Case Fixes:** Resolved an infinite HTTPS login loop by injecting `server.forward-headers-strategy=native` and `cookie.secure=true` to force Spring to trust the AWS ALB's SSL termination. Also fixed a critical ASG health-check failure by explicitly bypassing Spring Security's `.anyRequest().authenticated()` filter for the actuator endpoint.

### Phase 1: Local Validation
- **Twelve-Factor Configuration:** Abstracted hardcoded credentials into a standardized `.env` architecture, ensuring the exact same artifact is portable across bare-metal, Docker, and Kubernetes without recompilation.
- **Dual-Database Testing:** Added the `H2` in-memory database as a `runtime` dependency, creating a zero-infrastructure local testing path for developers while maintaining the native MySQL path for production parity validation.
- **Shell Truncation Mitigation:** Discovered and documented a silent connection failure caused by bash evaluating the `&` character in the JDBC URL as a background process operator, resolving it with strict double-quote wrapping.

### Phase 2: Docker Containerization
- **Multi-Stage Layer Caching:** Architected a Dockerfile with a Maven builder stage and a JRE runtime stage, drastically reducing the final image footprint and attack surface.
- **CIS Benchmark Compliance:** Hardened the runtime container by creating a dedicated `groupadd` and `useradd` non-root user, preventing privilege escalation vulnerabilities flagged by Trivy.
- **JVM Container Awareness:** Tuned the runtime with `-XX:+UseContainerSupport` so the JVM respects cgroup resource limits, preventing Kubernetes OOM (Out of Memory) kills.
- **Cold-Start Health Checks:** Configured a dynamic Docker `HEALTHCHECK` with a 30-second `start_period` to precisely accommodate Spring Boot's JVM cold-start duration.

### Phase 3a: Jenkins CI Pipeline
- **System-Wide Path Executions:** Eliminated brittle Jenkins UI `tools` configurations in favor of system-wide executable paths, ensuring the 14-stage declarative pipeline executes identically across different runner infrastructures.
- **Strict Quality Gates:** Integrated SonarQube directly via the `sonar-maven-plugin`, configuring the pipeline to explicitly halt if code coverage or vulnerability thresholds are breached.
- **Immutable Artifact Tagging:** Implemented dynamic Docker tags using a combination of the Maven POM version, Git SHA, and Jenkins Build ID to guarantee absolute traceability in Nexus and ECR registries.

### Phase 3b: GitHub Actions CI
- **Base Image OS Mitigation:** Handled CRITICAL OS-level CVEs by abandoning the unpatched Alpine base image in favor of `eclipse-temurin:21-jre-jammy`, securing the runtime foundation.
- **Three-Pass Scan Architecture:** Segmented Trivy scanning into three distinct passes: a filesystem config scan, an OS package scan (Warn Only), and a library dependency scan (Fail on Critical). This prevents pipeline failures on vendor OS issues while aggressively gating application-level vulnerabilities.
- **SonarQube API Refactoring:** Proactively updated deprecated Spring Security APIs (`AntPathRequestMatcher`) in the application code to resolve SonarQube `java:S5738` deprecation warnings and keep the pipeline green.

### Phase 4: AWS EC2 Auto Scaling
- **Imperative Infrastructure Mastery:** Provisioned the complete VPC networking stack (Subnets, Internet Gateways, NAT Gateways) imperatively via the AWS CLI to deeply understand the underlying cloud infrastructure.
- **Strict Security Group Chaining:** Enforced a zero-trust network boundary by chaining Security Groups (`sg-alb` → `sg-app` → `sg-rds`), ensuring backend instances and databases are completely isolated from public access.
- **Dynamic Artifact Retrieval:** Eliminated static AWS credentials on EC2 instances by leveraging IAM Instance Profiles (`AmazonS3ReadOnlyAccess`). Automated deployment via Launch Templates and `UserData` bootstrap scripts that pull the `.jar` directly from S3.

### Phase 5: Amazon ECS Fargate
- **Serverless Paradigm Shift:** Migrated compute from EC2 virtual machines to serverless containers, shifting deployment mechanics from Launch Templates to ECS Task Definitions and from Auto Scaling Groups to ECS Services.
- **IAM Execution Abstraction:** Replaced EC2 S3 access profiles with the `ecsTaskExecutionRole`, granting the Fargate engine precise permissions to authenticate to Amazon ECR and pull the Docker image.
- **Headless Observability:** Integrated the `awslogs` driver directly into the Task Definition to stream container stdout to Amazon CloudWatch, achieving centralized logging for instances without SSH access.

### Phase 6: Kubernetes Deployments
- **DRY Kustomize Architecture:** Designed a platform-agnostic DevSecOps strategy using Kustomize overlays (`base`, `bare-metal`, `eks`) to eliminate YAML duplication across diverse deployment environments.
- **Storage Class Decoupling:** Dynamically patched the database PersistentVolumeClaim (PVC) with the `local-path` Storage Class in the `bare-metal` overlay, and AWS EBS `gp3` in the EKS overlay.
- **Decoupled Gateway API Routing:** Future-proofed ingress by utilizing the Gateway API over traditional Ingress. Implemented the Nginx Gateway Fabric exclusively in the `bare-metal` overlay, dynamically resolving HTTP-01 challenges via `cert-manager`.
- **AWS Native Gateway Integration:** In the EKS overlay, replaced the internal Nginx proxy with the AWS Load Balancer Controller, dynamically provisioning an external ALB via the Gateway manifest mapped to a custom Route 53 domain.
- **TLS Edge Termination & Reusability:** Injected an ACM ARN directly into the Gateway `LoadBalancerConfiguration` via Kustomize patches, reusing the Route 53 hosted zone and ACM certificates originally provisioned in Phase 4.
- **Production State Decoupling:** Replaced the in-cluster MySQL StatefulSet in the EKS overlay by patching the `bankapp-config` ConfigMap to route the application's connection pool directly to an Amazon RDS instance.
- **Elastic Scale Boundaries:** Exclusively deployed a Horizontal Pod Autoscaler (HPA) in the EKS overlay, relying on the EKS Metrics Server to elastically scale the deployment from 2 to 5 replicas while keeping the bare-metal environment lightweight.
