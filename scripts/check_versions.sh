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
    output=$("$@" 2>&1 | tr -d '\r')

    local first_line
    first_line=$(printf '%s\n' "${output}" | head -n 1)
    printf '%-20s %s\n' "${label}:" "${first_line}"

    local extra_lines
    extra_lines=$(printf '%s\n' "${output}" | tail -n +2)

    if [[ -n "${extra_lines}" ]]; then
        printf '%s\n' "${extra_lines}" | sed 's/^/                    /'
    fi
}

printf 'Toolchain versions (%s)\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf '====================================\n\n'

check_tool "AWS CLI" aws --version
check_tool "Terraform" terraform version
check_tool "kubectl" kubectl version --client --short
check_tool "Helm" helm version --short
check_tool "Docker" docker --version

echo
