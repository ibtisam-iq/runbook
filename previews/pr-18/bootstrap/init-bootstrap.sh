#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_title() {
  case "$1" in
    container-runtime)    echo "Container Runtime" ;;
    language-runtimes)    echo "Language Runtimes" ;;
    system-foundation)    echo "System Foundation" ;;
    networking-tools)     echo "Networking Tools" ;;
    storage-tools)        echo "Storage Tools" ;;
    debugging-profiling)  echo "Debugging & Profiling" ;;
    iac)                  echo "Infrastructure as Code" ;;
    security-tools)       echo "Security Tools" ;;
    observability-tools)  echo "Observability Tools" ;;
    cloud-clis)           echo "Cloud CLIs" ;;
    database-clis)        echo "Database CLIs" ;;
    devops-clis)          echo "DevOps CLIs" ;;
    shell-environment)    echo "Shell Environment" ;;
    ai-ml-clis)           echo "AI & ML CLIs" ;;
    documentation-tools)  echo "Documentation Tools" ;;
    arkade)               echo "Arkade" ;;
    components)           echo "Components" ;;
  esac
}

for folder in \
  container-runtime \
  language-runtimes \
  system-foundation \
  networking-tools \
  storage-tools \
  debugging-profiling \
  iac \
  security-tools \
  observability-tools \
  cloud-clis \
  database-clis \
  devops-clis \
  shell-environment \
  ai-ml-clis \
  documentation-tools \
  arkade \
  components; do

  dir="$BOOTSTRAP_DIR/$folder"
  mkdir -p "$dir"
  title="$(get_title "$folder")"

  cat > "$dir/.nav.yml" <<NAVEOF
title: ${title}
nav:
  - index.md
NAVEOF

  cat > "$dir/index.md" <<MDEOF
# ${title}

> 🚧 This section is a work in progress. Content will be added soon.

<!-- Add your runbook pages for **${title}** here. -->
MDEOF

  echo "✅  Created: $folder/"
done

echo ""
echo "🎉 All bootstrap folders initialized successfully."
