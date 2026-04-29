#!/usr/bin/env bash
# run from the root of your runbook repo
# This script creates the directory structure.

set -euo pipefail

dirs=(
  linux/system-setup
  linux/networking
  linux/storage
  linux/security
  linux/troubleshooting

  containers/image-building
  containers/registries
  containers/runtime-config
  containers/troubleshooting

  kubernetes/cluster-setup
  kubernetes/networking
  kubernetes/storage
  kubernetes/security
  kubernetes/workloads
  kubernetes/autoscaling
  kubernetes/gitops
  kubernetes/troubleshooting

  networking/dns
  networking/tls
  networking/load-balancing
  networking/ingress-gateway
  networking/vpn-tunnels
  networking/firewalls

  storage/block
  storage/object
  storage/databases
  storage/backup-restore

  delivery/ci-pipelines
  delivery/cd-deployments
  delivery/artifact-management
  delivery/gitops

  security/secrets-management
  security/scanning
  security/rbac
  security/os-hardening
  security/certificates

  observability/metrics
  observability/logging
  observability/tracing
  observability/alerting

  cloud/aws/iam
  cloud/aws/networking
  cloud/aws/compute
  cloud/aws/managed-services
  cloud/gcp
  cloud/azure

  iac/provisioning
  iac/state-management
  iac/modules

  self-hosted/ci-cd
  self-hosted/artifact-registry
  self-hosted/code-quality
  self-hosted/ai-stack
  self-hosted/automation
  self-hosted/collaboration
  self-hosted/mlops

  incident-response
  windows
  macOS
  scripts

  assets/diagrams
  assets/screenshots
  assets/icons
)

for dir in "${dirs[@]}"; do
  mkdir -p "$dir"
  touch "$dir/.gitkeep"
done

echo "✅ Runbook structure created — $(echo "${dirs[@]}" | wc -w) directories ready."
