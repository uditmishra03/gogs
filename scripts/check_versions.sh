#!/usr/bin/env bash
echo
# Quick sanity check for core tooling on the gogs-devops host.

set -euo pipefail

printf 'Toolchain versions (%s)\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf '====================================\n\n'

aws --version | head -n 1
terraform version | head -n 1
kubectl version --client --short
helm version --short
docker --version | head -n 1

