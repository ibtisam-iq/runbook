#!/bin/bash

set -euo pipefail

BASE_DIR="projects"

FOLDERS=(
  "infrastructure"
  "deployments"
  "ci-cd"
  "gitops"
  "observability"
  "security"
  "networking"
  "data-pipelines"
  "ml-pipelines"
  "ai-ops"
  "platform-engineering"
)

TITLES=(
  "Infrastructure"
  "Deployments"
  "CI/CD"
  "GitOps"
  "Observability"
  "Security"
  "Networking"
  "Data Pipelines"
  "ML Pipelines"
  "AIOps"
  "Platform Engineering"
)

for i in "${!FOLDERS[@]}"; do
  dir="$BASE_DIR/${FOLDERS[$i]}"
  mkdir -p "$dir"
  cat > "$dir/.nav.yml" <<EOF
title: "${TITLES[$i]}"
EOF
  echo "Created: $dir/.nav.yml"
done

echo ""
echo "Done. Folder structure created under '$BASE_DIR/'"
