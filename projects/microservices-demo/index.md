# Microservices Demo

## What This Is

A production-grade GitOps pipeline deploying Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) (10-service polyglot monorepo) on Amazon EKS. I forked the upstream repo, built a DevSecOps CI pipeline with GitHub Actions, packaged and published the Helm chart to my own GHCR, and deployed it via ArgoCD with Image Updater handling continuous delivery. The platform includes full observability (Prometheus, Grafana, ELK stack with Slack alerting) and autoscaling (HPA).

| Item | Value |
|------|-------|
| Source repo (CI) | [ibtisam-iq/microservices-demo](https://github.com/ibtisam-iq/microservices-demo) |
| CD repo | [ibtisam-iq/platform-engineering-systems](https://github.com/ibtisam-iq/platform-engineering-systems/tree/main/systems/microservices-demo) |
| Live app | `app.ibtisam.qzz.io` |
| ArgoCD | `argocd.ibtisam.qzz.io` |
| Terminal sessions | [terminal-session/](https://github.com/ibtisam-iq/microservices-demo/tree/main/terminal-session) |
| Screenshots | [assets/](https://github.com/ibtisam-iq/microservices-demo/tree/main/assets) |

---

## Architecture at a Glance

```
Developer pushes code to src/
    │
    ▼
GitHub Actions (CI)
    ├── Trivy filesystem + image scan
    ├── Docker build (BuildKit + GHA cache)
    └── Push 3 tags to GHCR (:sha-<40>, :sha-<7>, :latest)
          │
          ▼
ArgoCD Image Updater (on cluster)
    ├── Polls GHCR every 2 min
    ├── Detects new :latest digest
    └── Patches ArgoCD Application
          │
          ▼
ArgoCD syncs, pods roll
    ├── 10 microservices in boutique-app namespace
    ├── Gateway API HTTPRoute -> shared ALB -> app.ibtisam.qzz.io
    └── ExternalDNS auto-creates Route 53 records

Observability
    ├── Prometheus + Grafana + AlertManager (Slack)
    └── Elasticsearch + Filebeat + Kibana

5 subdomains, 1 ALB, 1 wildcard cert, 0 manual DNS records
```

---

## Phases

The project is documented across 6 phases. Each phase has its own runbook with step-by-step commands, decisions, bugs encountered, and terminal session recordings as evidence.

<div class="grid cards" markdown>

- **[:material-pipe: Phase 1: CI Pipeline and DevSecOps](ci.md)**
  GitHub Actions workflows, Trivy scanning, GHCR image and chart publish

- **[:material-aws: Phase 2: AWS Infrastructure](aws-infrastructure.md)**
  DNS, ACM certificate, VPC, EKS cluster, bastion host, self-managed nodes

- **[:material-puzzle: Phase 3: Cluster Add-ons and Gateway API](cluster-addons.md)**
  ALB Controller, EBS CSI, Gateway API, ExternalDNS

- **[:material-sync: Phase 4: GitOps with ArgoCD](gitops-argocd.md)**
  ArgoCD, Application manifest, Image Updater, CI-CD integration

- **[:material-chart-line: Phase 5: Observability Stack](observability.md)**
  kube-prometheus-stack, ELK stack, Slack alerting, HTTPRoutes

- **[:material-arrow-expand-horizontal: Phase 6: Autoscaling, Load Testing, and Final Verification](autoscaling.md)**
  Metrics Server, HPA, scaling validation, full cluster audit

</div>

---

## Key Decisions

Architectural and engineering decisions made across all 6 phases. Each links to the runbook where it is documented in detail with full rationale.

### Repository and Code Strategy

- **Never modify upstream files.** The fork stays pristine and syncable. All customization lives in files added alongside upstream. ([Phase 1](ci.md))
- **Two-repo separation.** CI repo owns code and pipelines. CD repo owns deployment intent. CI has zero knowledge of the cluster for code pushes. ([Phase 1](ci.md), [Phase 4](gitops-argocd.md))
- **All deployment manifests in CD repo, nothing in CI repo.** The source repo contains no Kubernetes resources, no values files, no Helm overrides. ([Phase 4](gitops-argocd.md))
- **Deleted 2 upstream workflows, kept 3.** `ci-main.yaml` and `ci-pr.yaml` were replaced with a monorepo-aware matrix pipeline. `helm-chart-ci.yaml` was kept for chart validation. ([Phase 1](ci.md))

### Image Tagging and Continuous Delivery

- **Image tagging evolved through 3 iterations.** Chart version tags (broken for CD), immutable SHA tags (noisy), and finally ArgoCD Image Updater with digest strategy. ([Phase 1](ci.md))
- **Chose Approach B (Image Updater) over SHA-based GitOps.** CI pushes images and stops. Image Updater watches GHCR and handles deployments. Eliminated `reusable-gitops.yaml` entirely and removed the `GIT_TOKEN` dependency for code pushes. ([Phase 1](ci.md))
- **Digest strategy, not newest-build.** BuildKit sets the image config's `created` timestamp to epoch (`1970-01-01`) for reproducible builds. `newest-build` cannot differentiate tags. `digest` tracks `:latest` tag's digest directly, no timestamps involved. ([Phase 4](gitops-argocd.md))
- **tag: "latest" in values, not empty string.** `tag: ""` falls back to Chart.AppVersion, but CI never pushes images with the chart version tag. Image Updater needs `:latest` to track. ([Phase 4](gitops-argocd.md))

### Helm Chart and Values

- **Chart packaged from upstream as-is.** No upstream files modified. The chart on GHCR ships with Google's defaults. EKS overrides live in the CD repo's `values-eks.yaml`. ([Phase 1](ci.md))
- **Patch-only values file.** Only 5 fields that differ from upstream: registry, tag, externalService, platform, loadGenerator. Everything else uses upstream defaults. ([Phase 4](gitops-argocd.md))
- **loadGenerator disabled.** Excluded from CI matrix (no image in GHCR). Setting `create: false` in values prevents `ImagePullBackOff`. ([Phase 4](gitops-argocd.md))
- **chart-release.yaml absorbs CD repo update.** `reusable-gitops.yaml` was deleted. Chart version writes moved into `chart-release.yaml`. Image tag writes eliminated entirely. ([Phase 1](ci.md))

### Networking and DNS

- **Gateway API instead of Ingress.** The Kubernetes project recommends Gateway and states the Ingress API has been frozen. ([Phase 3](cluster-addons.md))
- **Single shared ALB via Gateway API.** One Gateway, one ALB, 5 HTTPRoutes across namespaces. All subdomains served through one load balancer. ([Phase 3](cluster-addons.md))
- **Wildcard ACM certificate.** `*.ibtisam.qzz.io` covers all subdomains. No new certificate needed when a subdomain is added. ([Phase 2](aws-infrastructure.md))
- **Free domain from digitalplat.org.** No cost for the `qzz.io` domain used across the project. ([Phase 2](aws-infrastructure.md))
- **ExternalDNS with Gateway API sources.** Auto-creates Route 53 records from HTTPRoutes. Zero manual DNS records in the entire project. ([Phase 3](cluster-addons.md))
- **HTTPRoute defaults included in Git.** Gateway API controller injects `group`, `kind`, `weight`, and `matches` defaults post-creation. Including them in the manifest prevents ArgoCD OutOfSync drift. ([Phase 4](gitops-argocd.md))

### Platform Architecture

- **ArgoCD manages the app, not the platform.** Monitoring and logging stacks deployed via Helm, not ArgoCD. If ArgoCD breaks, observability tools remain operational for debugging. ([Phase 4](gitops-argocd.md), [Phase 5](observability.md))
- **gp3 as default StorageClass.** Cheaper and better baseline than gp2. Required for Elasticsearch PVCs. ([Phase 3](cluster-addons.md))
- **Self-managed nodes (managed blocked by SCP).** KodeKloud AWS Playground enforces SCPs that block managed node groups. Self-managed nodes via CloudFormation. ([Phase 2](aws-infrastructure.md))
- **Scaled ASG from 3 to 4 nodes.** 3 nodes could not fit the full stack (app + monitoring + logging). Kibana pod stuck Pending until the 4th node joined. ([Phase 5](observability.md))

### Security and Scanning

- **Trivy CRITICAL gate temporarily relaxed.** Designed as exit-code 1 (hard gate). Currently exit-code 0 because upstream base images carry known CRITICAL CVEs. Restore once patched. ([Phase 1](ci.md))
- **GIT_TOKEN scoped to CD repo only.** Fine-grained PAT with Contents: Read+Write on `platform-engineering-systems` only. Token never in process argv. ([Phase 1](ci.md))

---

## Terminal Sessions

Every phase was recorded. The terminal sessions capture the exact commands, outputs, and errors encountered.

| # | Session | Phase | Link |
|---|---------|-------|------|
| 01 | DNS and SSL Certificate Setup | 2 | [`01_dns_and_ssl_certificate_setup.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01_dns_and_ssl_certificate_setup.txt) |
| 01a | Cluster Provisioning with Terraform | 2 | [`01a_cluster_provisioning_with_terraform.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/01a_cluster_provisioning_with_terraform.txt) |
| 02 | Bastion Access, Tools, Self-Managed Nodes | 2 | [`02_bastion_access_tool_installation_and_self_managed_nodes.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/02_bastion_access_tool_installation_and_self_managed_nodes.txt) |
| 03 | Cluster Add-ons Installation | 3 | [`03_cluster_addons_installation.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/03_cluster_addons_installation.txt) |
| 04 | Application Deployment and CI Trigger | 4 | [`04_application_deployment_and_ci_trigger.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/04_application_deployment_and_ci_trigger.txt) |
| 05 | kube-prometheus-stack Monitoring | 5 | [`05_kube_prometheus_stack_monitoring.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/05_kube_prometheus_stack_monitoring.txt) |
| 06 | Elastic Stack Logging | 5 | [`06_elastic_stack_logging.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/06_elastic_stack_logging.txt) |
| 07 | Scaling Behavior and Reliability | 6 | [`07_observe_scaling_behavior_and_validate_reliability.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/07_observe_scaling_behavior_and_validate_reliability.txt) |
| 08 | Full Cluster Verification | 6 | [`08_verification_of_pods_services_and_resources.txt`](https://github.com/ibtisam-iq/microservices-demo/blob/main/terminal-session/08_verification_of_pods_services_and_resources.txt) |

---

## Screenshots

| # | Screenshot | Phase | Link |
|---|------------|-------|------|
| 01 | SilverStack Dev Machine | 2 | [`01_silverstack_dev_machine.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/01_silverstack_dev_machine.png) |
| 02 | EKS Cluster Self-Managed Nodes | 2 | [`02_aws_eks_cluster_compute_self_managed_nodes.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/02_aws_eks_cluster_compute_self_managed_nodes.png) |
| 03 | Online Boutique Web View | 4 | [`03_online_boutique_web_view.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/03_online_boutique_web_view.png) |
| 04 | ArgoCD App Tree (Image Updater Revision) | 4 | [`04_argo_app_tree_image_updater_frontend_revision.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/04_argo_app_tree_image_updater_frontend_revision.png) |
| 05 | Prometheus Target Health | 5 | [`05_prometheus_kube_prometheus_stack_target_health.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/05_prometheus_kube_prometheus_stack_target_health.png) |
| 06 | Grafana Pod Metrics Dashboard | 5 | [`06_grafana_boutique_app_pod_metrics_dashboard.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/06_grafana_boutique_app_pod_metrics_dashboard.png) |
| 07 | Kibana Logs Discover View | 5 | [`07_kibana_boutique_app_logs_discover_view.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/07_kibana_boutique_app_logs_discover_view.png) |
| 08 | ArgoCD HPA Scale-Out | 6 | [`08_argo_app_tree_hpa_frontend_scale_out.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/08_argo_app_tree_hpa_frontend_scale_out.png) |
| 09 | Route 53 ExternalDNS Records | 3 | [`09_route53_records_externaldns_reconciliation.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/09_route53_records_externaldns_reconciliation.png) |
| 10 | CloudFormation EKS Add-ons and Node Stacks | 2 | [`10_cloudformation_eks_addons_and_nodes_stacks.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/10_cloudformation_eks_addons_and_nodes_stacks.png) |
| 11 | ALB Listeners and Rules Overview | 3 | [`11_aws_alb_listeners_and_rules_overview.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/11_aws_alb_listeners_and_rules_overview.png) |
| 12 | ALB Resource Map Routing Targets | 3 | [`12_aws_alb_resource_map_routing_targets.png`](https://github.com/ibtisam-iq/microservices-demo/blob/main/assets/12_aws_alb_resource_map_routing_targets.png) |
