#!/usr/bin/env bash
# Quick sanity check for core tooling on the gogs-devops host.

set -euo pipefail

check_tool() {
    local label=$1
    shift

    if ! command -v "$1" >/dev/null 2>&1; then
        printf '%-20s %s\n' "${label}:" "not installed"
        return
    fi

    local output
    output=$("$@" 2>&1 | head -n 1 | tr -d '\r')
    printf '%-20s %s\n' "${label}:" "${output}"
}

printf 'Toolchain versions (%s)\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf '====================================\n\n'

check_tool "AWS CLI" aws --version
check_tool "Terraform" terraform version
check_tool "kubectl" kubectl version --client --short
check_tool "Helm" helm version --short
check_tool "Docker" docker --version

echo
