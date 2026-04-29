#!/usr/bin/env bash
# Run from the root of your runbook repo
set -euo pipefail

# ─────────────────────────────────────────────
# Helper: create an index.md placeholder so the
# section renders in MkDocs (section-index plugin)
# ─────────────────────────────────────────────
make_index() {
  local dir="$1"
  local title
  title=$(basename "$dir" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  cat > "$dir/index.md" <<EOF
# $title

> 🚧 This section is a work in progress. Content will be added soon.

<!-- Add your runbook pages for **$title** here. -->
EOF
}

# ─────────────────────────────────────────────
# Helper: write a .pages file (awesome-nav)
# ─────────────────────────────────────────────
make_pages() {
  local dir="$1"
  local title
  title=$(basename "$dir" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  printf "title: %s\narrange:\n  - index.md\n  - ...\n" "$title" > "$dir/.pages"
}

# ─────────────────────────────────────────────
# 1. Remove all .gitkeep files
# ─────────────────────────────────────────────
echo "🧹  Removing .gitkeep files..."
find . -name ".gitkeep" -not -path "./.git/*" -delete

# ─────────────────────────────────────────────
# 2. Root .pages  (controls top-level nav tab order)
# ─────────────────────────────────────────────
echo "📄  Writing root .pages..."
cat > .pages <<'PAGES'
title: Home
arrange:
  - index.md
  - kubernetes
  - linux
  - containers
  - networking
  - cloud
  - delivery
  - iac
  - observability
  - security
  - self-hosted
  - storage
  - bootstrap
  - incident-response
  - macOS
  - windows
  - ...
PAGES

# ─────────────────────────────────────────────
# 3. All directories (depth 1 and 2)
# ─────────────────────────────────────────────
DIRS=(
  # depth-1
  bootstrap
  cloud
  containers
  delivery
  iac
  incident-response
  kubernetes
  linux
  macOS
  networking
  observability
  security
  self-hosted
  storage
  windows
  # depth-2  cloud
  cloud/aws
  cloud/azure
  cloud/gcp
  # depth-3  cloud/aws
  cloud/aws/compute
  cloud/aws/iam
  cloud/aws/managed-services
  cloud/aws/networking
  # depth-2  containers
  containers/image-building
  containers/registries
  containers/runtime-config
  containers/troubleshooting
  # depth-2  delivery
  delivery/artifact-management
  delivery/cd-deployments
  delivery/ci-pipelines
  delivery/gitops
  # depth-2  iac
  iac/modules
  iac/provisioning
  iac/state-management
  # depth-2  kubernetes
  kubernetes/autoscaling
  kubernetes/cluster-setup
  kubernetes/gitops
  kubernetes/networking
  kubernetes/security
  kubernetes/storage
  kubernetes/troubleshooting
  kubernetes/workloads
  # depth-2  linux
  linux/networking
  linux/security
  linux/storage
  linux/system-setup
  linux/troubleshooting
  # depth-2  networking
  networking/dns
  networking/firewalls
  networking/ingress-gateway
  networking/load-balancing
  networking/tls
  networking/vpn-tunnels
  # depth-2  observability
  observability/alerting
  observability/logging
  observability/metrics
  observability/tracing
  # depth-2  security
  security/certificates
  security/os-hardening
  security/rbac
  security/scanning
  security/secrets-management
  # depth-2  self-hosted
  self-hosted/ai-stack
  self-hosted/artifact-registry
  self-hosted/automation
  self-hosted/ci-cd
  self-hosted/code-quality
  self-hosted/collaboration
  self-hosted/mlops
  # depth-2  storage
  storage/backup-restore
  storage/block
  storage/databases
  storage/object
)

for dir in "${DIRS[@]}"; do
  echo "  📁  $dir"
  mkdir -p "$dir"
  make_index "$dir"
  make_pages "$dir"
done

echo ""
echo "✅  Done!"
echo "   • .gitkeep files removed"
echo "   • root .pages written"
echo "   • index.md + .pages created in ${#DIRS[@]} directories"
