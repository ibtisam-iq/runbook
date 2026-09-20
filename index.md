---
hide:
  - toc
  - navigation
---

<div class="nx-landing">

<!-- 2-Column Balanced Minimalist Hero -->
<section class="nx-hero">
  <div class="nx-hero__inner">
    <!-- Left Column: Copy, CTAs -->
    <div class="nx-hero__left">
      <div class="nx-hero__badge">
        <span class="nx-hero__badge-pulse"></span>
        <span class="nx-hero__badge-text">Production Runbooks</span>
        <span class="nx-hero__badge-sep">/</span>
        <span class="nx-hero__badge-author">Muhammad Ibtisam Iqbal</span>
        <span class="nx-hero__badge-cert">CKA · CKAD</span>
      </div>
      <h1 class="nx-hero__title">Production infrastructure, <span class="nx-accent">documented from the trenches.</span></h1>
      <p class="nx-hero__tagline">
        I don't chase buzzwords. I look for broken systems and redesign them until they become reliable, predictable, and calm under pressure. Step-by-step procedures, cloud migrations, and cluster configurations — documented upon live execution.
      </p>
      <div class="nx-hero__actions">
        <a href="#featured-projects" class="nx-btn nx-btn--primary">
          <span>Featured Case Studies</span>
          <span class="nx-btn__arrow">→</span>
        </a>
        <a href="bootstrap/" class="nx-btn nx-btn--ghost">Bootstrap Playbooks</a>
        <a href="https://github.com/ibtisam-iq/runbook" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">GitHub ↗</a>
      </div>
    </div>

    <!-- Right Column: macOS Developer Terminal Window -->
    <div class="nx-hero__right">
      <div class="nx-terminal">
        <div class="nx-terminal__header">
          <div class="nx-terminal__controls">
            <span class="nx-terminal__dot nx-terminal__dot--red"></span>
            <span class="nx-terminal__dot nx-terminal__dot--yellow"></span>
            <span class="nx-terminal__dot nx-terminal__dot--green"></span>
          </div>
          <div class="nx-terminal__tab">
            <span class="nx-terminal__tab-icon">⚡</span>
            <span class="nx-terminal__tab-title">runbook.sh</span>
            <span class="nx-terminal__tab-badge">active</span>
          </div>
          <div class="nx-terminal__meta">
            <span class="nx-terminal__pill">prod</span>
          </div>
        </div>
        <div class="nx-terminal__body">
          <div class="nx-terminal__row nx-terminal__row--cmd">
            <span class="nx-terminal__prompt">$</span>
            <span class="nx-terminal__cmd">runbook status --verified</span>
          </div>
          <div class="nx-terminal__row nx-terminal__row--out">
            <span class="nx-terminal__check">✓</span>
            <span class="nx-terminal__label">gitops/eks-boutique</span>
            <span class="nx-terminal__val">· ArgoCD, Gateway API, 10 microservices</span>
          </div>
          <div class="nx-terminal__row nx-terminal__row--out">
            <span class="nx-terminal__check">✓</span>
            <span class="nx-terminal__label">cloud/java-monolith</span>
            <span class="nx-terminal__val">· 4 compute targets (ASG ➔ ECS ➔ EKS)</span>
          </div>
          <div class="nx-terminal__row nx-terminal__row--out">
            <span class="nx-terminal__check">✓</span>
            <span class="nx-terminal__label">helmfile/retail-store</span>
            <span class="nx-terminal__val">· 3 targets (Bare-Metal ➔ Amazon EKS)</span>
          </div>
          <div class="nx-terminal__row nx-terminal__row--status">
            <span class="nx-terminal__tag">[ok]</span>
            <span class="nx-terminal__msg">3 production topologies validated &amp; repeatable.</span>
            <span class="nx-terminal__cursor"></span>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- Impact Metrics Ticker -->
<div class="nx-metrics">
  <div class="nx-metric-item">
    <div class="nx-metric-item__idx">01 / PLATFORMS</div>
    <div class="nx-metric-item__num">4 Targets</div>
    <div class="nx-metric-item__label">EC2 Auto Scaling ➔ ECS Fargate ➔ Bare-Metal K8s ➔ Amazon EKS</div>
  </div>
  <div class="nx-metric-item">
    <div class="nx-metric-item__idx">02 / MICROSERVICES</div>
    <div class="nx-metric-item__num">5 Runtimes</div>
    <div class="nx-metric-item__label">Polyglot microservices stack with 5 databases orchestrated via Helmfile</div>
  </div>
  <div class="nx-metric-item">
    <div class="nx-metric-item__idx">03 / DEVSECOPS</div>
    <div class="nx-metric-item__num">14 Stages</div>
    <div class="nx-metric-item__label">Jenkins &amp; GitHub Actions CI with SonarQube quality gates &amp; Trivy scans</div>
  </div>
  <div class="nx-metric-item">
    <div class="nx-metric-item__idx">04 / DOMAINS</div>
    <div class="nx-metric-item__num">15+ Verified</div>
    <div class="nx-metric-item__label">HA Kubernetes, Gateway API, WireGuard Mesh, and full telemetry</div>
  </div>
</div>

<!-- Persona Router ("Choose Your Focus") -->
<div class="nx-section">
  <div class="nx-section__eyebrow">Tailored Navigation</div>
  <h2 class="nx-section__title">Choose Your Focus</h2>
  <p class="nx-section__lead">
    Whether you are an engineering leader evaluating technical capability, a fellow SRE looking for battle-tested configs, or a developer exploring infrastructure systems.
  </p>
</div>

<div class="nx-persona-grid">
  <!-- Recruiter Track -->
  <a href="#featured-projects" class="nx-persona-card nx-persona-card--recruiter">
    <div class="nx-persona-card__tag">💼 Recruiters &amp; Tech Leads</div>
    <div class="nx-persona-card__title">
      <span>Executive Case Studies</span>
      <span class="nx-persona-card__title-arrow">→</span>
    </div>
    <p class="nx-persona-card__desc">
      End-to-end cloud migrations, multi-stage DevSecOps pipelines, architecture diagrams, and verified production deployments.
    </p>
    <div class="nx-persona-card__chips">
      <span class="nx-persona-chip">#eks-gitops</span>
      <span class="nx-persona-chip">#4-target-migration</span>
      <span class="nx-persona-chip">#polyglot-helmfile</span>
    </div>
  </a>

  <!-- Peer SRE Track -->
  <a href="#war-stories" class="nx-persona-card nx-persona-card--peer">
    <div class="nx-persona-card__tag">🛠️ DevOps &amp; SRE Peers</div>
    <div class="nx-persona-card__title">
      <span>Field Notes &amp; Gotchas</span>
      <span class="nx-persona-card__title-arrow">→</span>
    </div>
    <p class="nx-persona-card__desc">
      Bare-metal Kubeadm HA, Envoy Gateway routing, WireGuard mesh overlays, and transparent post-mortem debugging logs.
    </p>
    <div class="nx-persona-card__chips">
      <span class="nx-persona-chip">#gateway-api</span>
      <span class="nx-persona-chip">#alb-health-probes</span>
      <span class="nx-persona-chip">#post-mortems</span>
    </div>
  </a>

  <!-- Learner Track -->
  <a href="#ecosystem" class="nx-persona-card nx-persona-card--learner">
    <div class="nx-persona-card__tag">📐 Engineers &amp; Architects</div>
    <div class="nx-persona-card__title">
      <span>The 4-Tier Ecosystem</span>
      <span class="nx-persona-card__title-arrow">→</span>
    </div>
    <p class="nx-persona-card__desc">
      How deep conceptual research in Nectar translates into operational runbooks, SilverStack automation scripts, and essays.
    </p>
    <div class="nx-persona-card__chips">
      <span class="nx-persona-chip">#nectar</span>
      <span class="nx-persona-chip">#silverstack</span>
      <span class="nx-persona-chip">#architecture-loop</span>
    </div>
  </a>
</div>

<!-- Featured Production Case Studies -->
<div id="featured-projects" class="nx-section">
  <div class="nx-section__eyebrow">Proof of Work</div>
  <h2 class="nx-section__title">Featured Production Case Studies</h2>
  <p class="nx-section__lead">
    Production-grade implementations engineered from scratch, tested under real failure scenarios, and documented upon execution.
  </p>
</div>

<div class="nx-showcase">
  <!-- Project 1: Microservices Demo EKS GitOps -->
  <div class="nx-showcase-card">
    <div class="nx-showcase-card__header">
      <div class="nx-showcase-card__meta-group">
        <span class="nx-showcase-card__domain-tag">Platform Engineering</span>
        <span class="nx-showcase-card__status">● Production Verified</span>
      </div>
      <div class="nx-showcase-card__tags">
        <span class="nx-tag">Terraform</span>
        <span class="nx-tag">Amazon EKS</span>
        <span class="nx-tag">ArgoCD</span>
        <span class="nx-tag">Gateway API</span>
        <span class="nx-tag">ExternalDNS</span>
        <span class="nx-tag">Prometheus</span>
        <span class="nx-tag">Elastic Stack</span>
      </div>
    </div>
    <h3 class="nx-showcase-card__title">Event-Driven GitOps: Polyglot Microservices on Amazon EKS</h3>
    <p class="nx-showcase-card__summary">
      Architected a production-grade GitOps platform on Amazon EKS for Google's 10-service Online Boutique. Engineered 3 automated CI pipelines with change detection, Trivy container security scanning, automated Helm packaging to GHCR, and zero-touch continuous delivery using ArgoCD Image Updater.
    </p>
    <div class="nx-showcase-card__highlights">
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Continuous Delivery</span>
        <span class="nx-highlight-item__v">Zero-touch ArgoCD Image Updater via GHCR</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Traffic Ingress</span>
        <span class="nx-highlight-item__v">Kubernetes Gateway API + Route 53 ExternalDNS</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Telemetry Stack</span>
        <span class="nx-highlight-item__v">Kube-Prometheus, Grafana, AlertManager &amp; Elastic</span>
      </div>
    </div>
    <div class="nx-showcase-card__actions">
      <a href="projects/deployments/microservices-demo/" class="nx-btn nx-btn--primary">
        <span>Explore Case Study</span>
        <span class="nx-btn__arrow">→</span>
      </a>
      <a href="https://github.com/ibtisam-iq/microservices-demo" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">CI Source Repo ↗</a>
      <a href="https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">GitOps Manifests ↗</a>
    </div>
  </div>

  <!-- Project 2: BankApp Java Monolith Cloud Migration -->
  <div class="nx-showcase-card">
    <div class="nx-showcase-card__header">
      <div class="nx-showcase-card__meta-group">
        <span class="nx-showcase-card__domain-tag">DevSecOps &amp; Cloud</span>
        <span class="nx-showcase-card__status">● Production Verified</span>
      </div>
      <div class="nx-showcase-card__tags">
        <span class="nx-tag">Java 21</span>
        <span class="nx-tag">Spring Boot 3.4</span>
        <span class="nx-tag">EC2 ASG</span>
        <span class="nx-tag">Amazon ECS Fargate</span>
        <span class="nx-tag">Amazon EKS</span>
        <span class="nx-tag">Jenkins</span>
        <span class="nx-tag">GitHub Actions</span>
        <span class="nx-tag">Trivy</span>
      </div>
    </div>
    <h3 class="nx-showcase-card__title">BankApp: Evolutionary Cloud Migration Across 4 Compute Targets</h3>
    <p class="nx-showcase-card__summary">
      Orchestrated an end-to-end DevSecOps strategy for a 3-tier Java Spring Boot banking monolith. Executed codebase modernization, multi-stage Docker containerization, 14-stage CI pipelines in Jenkins and GitHub Actions with SonarQube &amp; Trivy gates, and deployed the identical artifact across four increasingly scalable compute paradigms.
    </p>
    <div class="nx-showcase-card__highlights">
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Compute Targets</span>
        <span class="nx-highlight-item__v">EC2 Auto Scaling ➔ ECS Fargate ➔ Bare-Metal K8s ➔ EKS</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Security Gates</span>
        <span class="nx-highlight-item__v">Trivy layered scan (OS vs Lib) + SonarQube quality gate</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Artifact Stores</span>
        <span class="nx-highlight-item__v">Nexus Snapshot Repo, Amazon S3, ECR &amp; GHCR</span>
      </div>
    </div>
    <div class="nx-showcase-card__actions">
      <a href="projects/deployments/java-monolith/" class="nx-btn nx-btn--primary">
        <span>Explore Case Study</span>
        <span class="nx-btn__arrow">→</span>
      </a>
      <a href="https://github.com/ibtisam-iq/java-monolith-app" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">App Source Code ↗</a>
      <a href="https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/java-monolith" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">Deployment Overlay ↗</a>
    </div>
  </div>

  <!-- Project 3: Retail Store Polyglot Microservices Multi-Target Orchestration -->
  <div class="nx-showcase-card">
    <div class="nx-showcase-card__header">
      <div class="nx-showcase-card__meta-group">
        <span class="nx-showcase-card__domain-tag">Platform &amp; Orchestration</span>
        <span class="nx-showcase-card__status">● Production Verified</span>
      </div>
      <div class="nx-showcase-card__tags">
        <span class="nx-tag">Helmfile</span>
        <span class="nx-tag">Amazon EKS</span>
        <span class="nx-tag">ALB Ingress</span>
        <span class="nx-tag">EBS CSI gp3</span>
        <span class="nx-tag">DynamoDB</span>
        <span class="nx-tag">AWS SQS</span>
        <span class="nx-tag">Lambda</span>
      </div>
    </div>
    <h3 class="nx-showcase-card__title">Multi-Target Polyglot Microservices: Bare-Metal to Amazon EKS</h3>
    <p class="nx-showcase-card__summary">
      Engineered multi-environment declarative orchestration for AWS's retail store application (5 independent services, 5 runtimes, 5 databases). Decoupled upstream Helm charts via layered <code>values-*.yaml</code> overrides and automated 1-command deployments across ephemeral bare-metal, persistent bare-metal, and Amazon EKS.
    </p>
    <div class="nx-showcase-card__highlights">
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Declarative Tooling</span>
        <span class="nx-highlight-item__v">3 Helmfile targets with strict dependency ordering</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Cloud Integrations</span>
        <span class="nx-highlight-item__v">ALB Ingress, EBS CSI, DynamoDB, SQS, SNS &amp; Lambda</span>
      </div>
      <div class="nx-highlight-item">
        <span class="nx-highlight-item__k">Portability</span>
        <span class="nx-highlight-item__v">Severed cloud dependencies for zero-drift bare-metal runs</span>
      </div>
    </div>
    <div class="nx-showcase-card__actions">
      <a href="projects/deployments/retail-store-sample-app/" class="nx-btn nx-btn--primary">
        <span>Explore Case Study</span>
        <span class="nx-btn__arrow">→</span>
      </a>
      <a href="projects/deployments/retail-store-sample-app/microservices-deployment/" class="nx-btn nx-btn--ghost">Helmfile Specs ↗</a>
      <a href="https://github.com/ibtisam-iq/retail-store-sample-app" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">GitHub Source ↗</a>
    </div>
  </div>
</div>

<!-- Field Notes: What Broke & How I Fixed It -->
<div id="war-stories" class="nx-section">
  <div class="nx-section__eyebrow">War Stories &amp; Post-Mortems</div>
  <h2 class="nx-section__title">What Broke &amp; How I Fixed It</h2>
  <p class="nx-section__lead">
    Production engineering is measured by how you diagnose and remediate failure. Here are actual debugging hurdles resolved during live system implementations.
  </p>
</div>

<div class="nx-war-stories">
  <!-- Story 1: Enterprise ALB Health Check & Redirect Failure -->
  <div class="nx-war-card">
    <div class="nx-war-card__head">
      <span class="nx-war-card__badge">SEV-1 · Ingress &amp; Probes</span>
      <span class="nx-war-card__resolved">Resolved ✓</span>
    </div>
    <div class="nx-war-card__title">ALB Health Check Cascade Failure on Spring Boot 302 Redirect</div>
    <div class="nx-war-card__block">
      <div class="nx-war-card__line nx-war-card__line--issue">
        <span class="nx-war-card__line-k">Root Cause / Symptom:</span>
        Deploying the BankApp monolith behind an AWS Application Load Balancer caused instances to enter a termination loop; Spring Security intercepted root <code>/</code> with a <code>302 Found</code> redirect to <code>/login</code>, which the default ALB health check flagged as unhealthy.
      </div>
      <div class="nx-war-card__line nx-war-card__line--fix">
        <span class="nx-war-card__line-k">Engineering Remediation:</span>
        Reconfigured Target Group matcher to accept <code>200,302</code>, deployed dedicated <code>/actuator/health</code> probes, and configured native <code>X-Forwarded-Proto</code> handling to eliminate HTTPS redirect loops.
      </div>
    </div>
    <a href="projects/deployments/java-monolith/phase-4-ec2-auto-scaling/#stage-4--troubleshooting" class="nx-war-card__link">
      View ALB post-mortem &amp; runbook →
    </a>
  </div>

  <!-- Story 2: Bare-Metal Gateway API Port Collisions -->
  <div class="nx-war-card">
    <div class="nx-war-card__head">
      <span class="nx-war-card__badge">SEV-2 · Traffic Ingress</span>
      <span class="nx-war-card__resolved">Resolved ✓</span>
    </div>
    <div class="nx-war-card__title">Gateway API Listener Port Conflicts</div>
    <div class="nx-war-card__block">
      <div class="nx-war-card__line nx-war-card__line--issue">
        <span class="nx-war-card__line-k">Root Cause / Symptom:</span>
        Deploying Envoy Gateway on bare-metal caused listener binding clashes with existing NodePort services and host port bindings.
      </div>
      <div class="nx-war-card__line nx-war-card__line--fix">
        <span class="nx-war-card__line-k">Engineering Remediation:</span>
        Decoupled L4 traffic via MetalLB Layer 2 ARP IP address pools, standardizing HTTPRoute attachment rules with explicit sectionName bindings.
      </div>
    </div>
    <a href="bootstrap/kubernetes/addons-bare-metal/deploy-gateway-api/deploy-envoy-gateway/" class="nx-war-card__link">
      View Gateway API runbook →
    </a>
  </div>

  <!-- Story 3: AWS EKS IAM Auth under SCPs -->
  <div class="nx-war-card">
    <div class="nx-war-card__head">
      <span class="nx-war-card__badge">SEV-1 · Cluster Bootstrap</span>
      <span class="nx-war-card__resolved">Resolved ✓</span>
    </div>
    <div class="nx-war-card__title">EKS Worker Nodes Stuck 'Unauthorized' on API Server</div>
    <div class="nx-war-card__block">
      <div class="nx-war-card__line nx-war-card__line--issue">
        <span class="nx-war-card__line-k">Root Cause / Symptom:</span>
        Nodes booted via launch templates failed API registration with <code>err="Unauthorized"</code> due to IAM <code>authenticationMode</code> mismatch between EKS access entries and sandbox SCP policies.
      </div>
      <div class="nx-war-card__line nx-war-card__line--fix">
        <span class="nx-war-card__line-k">Engineering Remediation:</span>
        Extracted InstanceProfileArn via IMDS (169.254.169.254), patched cluster to <code>API_AND_CONFIG_MAP</code>, and mapped the node role to <code>system:bootstrappers</code> &amp; <code>system:nodes</code>.
      </div>
    </div>
    <a href="iac/terraform/provisioning/eks-on-kodekloud-eksctl/#troubleshooting" class="nx-war-card__link">
      View EKS bootstrap runbook →
    </a>
  </div>
</div>

<!-- The 4-Tier Engineering Ecosystem -->
<div id="ecosystem" class="nx-section">
  <div class="nx-section__eyebrow">Engineering System</div>
  <h2 class="nx-section__title">The 4-Tier Knowledge Pipeline</h2>
  <p class="nx-section__lead">
    How research translates into operational field notes, reusable infrastructure artifacts, and distilled technical essays.
  </p>
</div>

<div class="nx-ecosystem-grid">
  <!-- Pillar 1 -->
  <a href="https://nectar.ibtisam-iq.com" target="_blank" rel="noopener" class="nx-ecosystem-card">
    <div class="nx-ecosystem-card__step-row">
      <span class="nx-ecosystem-card__step">01 / 04 · Grounding</span>
    </div>
    <div class="nx-ecosystem-card__title">
      <span>Nectar</span>
      <span>↗</span>
    </div>
    <p class="nx-ecosystem-card__desc">
      Personal engineering knowledge base. Theoretical foundations, conceptual models, and architectural reference notes.
    </p>
    <div class="nx-ecosystem-card__host">nectar.ibtisam-iq.com</div>
  </a>

  <!-- Pillar 2 (Current) -->
  <div class="nx-ecosystem-card nx-ecosystem-card--current">
    <div class="nx-ecosystem-card__step-row">
      <span class="nx-ecosystem-card__step">02 / 04 · Execution</span>
      <span class="nx-ecosystem-card__badge-live">● Active Site</span>
    </div>
    <div class="nx-ecosystem-card__title">
      <span>Runbook</span>
      <span>✓</span>
    </div>
    <p class="nx-ecosystem-card__desc">
      Documented steps from real infrastructure work — exact commands run, problems encountered, and how they were fixed.
    </p>
    <div class="nx-ecosystem-card__host">runbook.ibtisam-iq.com</div>
  </div>

  <!-- Pillar 3 -->
  <a href="https://github.com/ibtisam-iq/silver-stack" target="_blank" rel="noopener" class="nx-ecosystem-card">
    <div class="nx-ecosystem-card__step-row">
      <span class="nx-ecosystem-card__step">03 / 04 · Automation</span>
    </div>
    <div class="nx-ecosystem-card__title">
      <span>SilverStack</span>
      <span>↗</span>
    </div>
    <p class="nx-ecosystem-card__desc">
      Reusable infrastructure artifacts — Bash automation scripts, Kubernetes manifests, and pre-built Docker rootfs images.
    </p>
    <div class="nx-ecosystem-card__host">github.com/ibtisam-iq/silver-stack</div>
  </a>

  <!-- Pillar 4 -->
  <a href="https://blog.ibtisam-iq.com" target="_blank" rel="noopener" class="nx-ecosystem-card">
    <div class="nx-ecosystem-card__step-row">
      <span class="nx-ecosystem-card__step">04 / 04 · Synthesis</span>
    </div>
    <div class="nx-ecosystem-card__title">
      <span>Blog</span>
      <span>↗</span>
    </div>
    <p class="nx-ecosystem-card__desc">
      Distilled technical write-ups and essays — reflections on building systems, architectural trade-offs, and lessons learned.
    </p>
    <div class="nx-ecosystem-card__host">blog.ibtisam-iq.com</div>
  </a>
</div>

<!-- Section Header: Operational Domains -->
<div class="nx-section">
  <div class="nx-section__eyebrow">Infrastructure Directory</div>
  <h2 class="nx-section__title">Operational Domains</h2>
  <p class="nx-section__lead">
    Systematic reference documentation organized across core infrastructure disciplines.
  </p>
</div>

<!-- 6-Card Minimalist Grid -->
<div class="nx-grid">
  <a href="observability/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">📊</span>
      <span class="nx-card__badge">Telemetry</span>
    </div>
    <div class="nx-card__title">Observability &amp; Telemetry</div>
    <p class="nx-card__desc">Prometheus, Grafana, AlertManager &amp; distributed tracing</p>
  </a>

  <a href="bootstrap/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">📦</span>
      <span class="nx-card__badge">Bootstrap</span>
    </div>
    <div class="nx-card__title">Bootstrap &amp; Bare-Metal</div>
    <p class="nx-card__desc">Multi-node Kubeadm clusters &amp; automated host provisioning</p>
  </a>

  <a href="kubernetes/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">☸️</span>
      <span class="nx-card__badge">Orchestration</span>
    </div>
    <div class="nx-card__title">Kubernetes &amp; Workloads</div>
    <p class="nx-card__desc">Gateway API, MetalLB, Ingress &amp; container runtime configurations</p>
  </a>

  <a href="cloud/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">☁️</span>
      <span class="nx-card__badge">Cloud</span>
    </div>
    <div class="nx-card__title">Cloud &amp; Infrastructure</div>
    <p class="nx-card__desc">Amazon EKS, VPC topologies &amp; declarative Terraform IaC</p>
  </a>

  <a href="networking/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">🌐</span>
      <span class="nx-card__badge">Network</span>
    </div>
    <div class="nx-card__title">Networking &amp; Traffic</div>
    <p class="nx-card__desc">WireGuard mesh overlays, Cloudflare routing &amp; internal DNS</p>
  </a>

  <a href="delivery/" class="nx-card">
    <div class="nx-card__head">
      <span class="nx-card__icon">🛡️</span>
      <span class="nx-card__badge">Operations</span>
    </div>
    <div class="nx-card__title">Delivery &amp; Security</div>
    <p class="nx-card__desc">GitOps deployment pipelines, telemetry &amp; host hardening</p>
  </a>
</div>

<!-- Author Identity & Contact Callout Banner -->
<div class="nx-contact-banner">
  <div class="nx-contact-banner__left">
    <div class="nx-contact-banner__eyebrow">
      <span class="nx-hero__badge-pulse"></span>
      <span>Engineering Collaboration</span>
    </div>
    <h3 class="nx-contact-banner__title">Let's build reliable, calm systems.</h3>
    <p class="nx-contact-banner__desc">
      Engineered by <strong>Muhammad Ibtisam Iqbal</strong> (CKA &amp; CKAD Certified). Based in Islamabad, Pakistan. Available for platform engineering, cloud migration, and SRE infrastructure discussions.
    </p>
  </div>
  <div class="nx-contact-banner__actions">
    <a href="https://linkedin.com/in/ibtisam-iq" target="_blank" rel="noopener" class="nx-btn nx-btn--primary">Connect on LinkedIn</a>
    <a href="https://ibtisam-iq.com" target="_blank" rel="noopener" class="nx-btn nx-btn--ghost">ibtisam-iq.com ↗</a>
  </div>
</div>

<!-- Consolidated Minimalist Footer Bar -->
<div class="nx-footer-bar">
  <div class="nx-footer-bar__rule">
    “Documented upon execution to ensure repeatable deployments, operational auditability, and reliable recovery.”
  </div>
  <div class="nx-footer-bar__meta">
    <span>Muhammad Ibtisam Iqbal</span>
    <span class="nx-footer-bar__cert">CKA · CKAD</span>
    <span class="nx-footer-bar__sep">/</span>
    <span>Islamabad, Pakistan</span>
  </div>
</div>

</div>
