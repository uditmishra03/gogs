#!/bin/bash

# Script to switch between local and S3 backend for Terraform
# Usage: ./switch-backend.sh [local|s3]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

show_usage() {
    echo "Usage: $0 [local|s3]"
    echo ""
    echo "Options:"
    echo "  local  - Use local backend (state stored locally)"
    echo "  s3     - Use S3 backend (state stored in S3 bucket)"
    echo ""
    echo "Examples:"
    echo "  $0 local   # Switch to local backend"
    echo "  $0 s3      # Switch to S3 backend"
}

switch_to_local() {
    log "Switching to local backend..."
    
    # Backup current backend.tf
    if [ -f "backend.tf" ]; then
        cp backend.tf backend.tf.backup
        log "Backed up current backend.tf to backend.tf.backup"
    fi
    
    # Replace with local backend
    cp backend-local.tf backend.tf
    
    log "✅ Switched to local backend"
    info "State will be stored in: terraform.tfstate"
    info "Run 'terraform init -reconfigure' to apply the change"
}

switch_to_s3() {
    log "Switching to S3 backend..."
    
    # Check if S3 backend setup exists
    if [ ! -f "../setup-terraform-backend.sh" ]; then
        error "S3 backend setup script not found!"
        exit 1
    fi
    
    warn "Make sure you have created the S3 backend first!"
    echo "If you haven't, run: cd .. && ./setup-terraform-backend.sh"
    echo ""
    
    # Backup current backend.tf
    if [ -f "backend.tf" ]; then
        cp backend.tf backend.tf.backup
        log "Backed up current backend.tf to backend.tf.backup"
    fi
    
    # Check if S3 backend configuration exists
    if [ ! -f "backend.tf.s3" ]; then
        error "S3 backend configuration not found!"
        error "Please run the S3 backend setup script first: cd .. && ./setup-terraform-backend.sh"
        exit 1
    fi
    
    # Replace with S3 backend
    cp backend.tf.s3 backend.tf
    
    log "✅ Switched to S3 backend"
    info "State will be stored in S3 bucket"
    info "Run 'terraform init -reconfigure' to apply the change"
}

# Main script
cd "$(dirname "$0")/eks-prod" || exit 1

if [ $# -eq 0 ]; then
    echo "Current backend configuration:"
    echo "============================="
    if grep -q "backend \"local\"" backend.tf 2>/dev/null; then
        echo "✅ Currently using: LOCAL backend"
    elif grep -q "backend \"s3\"" backend.tf 2>/dev/null; then
        echo "✅ Currently using: S3 backend"
        grep -A 6 "backend \"s3\"" backend.tf | grep -E "(bucket|region|key)"
    else
        echo "❓ Backend configuration unclear"
    fi
    echo ""
    show_usage
    exit 0
fi

case "$1" in
    "local")
        switch_to_local
        ;;
    "s3")
        switch_to_s3
        ;;
    *)
        error "Invalid option: $1"
        show_usage
        exit 1
        ;;
esac

echo ""
echo "=============================================="
echo "🔄 BACKEND SWITCH COMPLETED"
echo "=============================================="
echo ""
echo "🚀 Next steps:"
echo "1. terraform init -reconfigure"
echo "2. terraform plan"
echo ""
echo "Note: Use -reconfigure to avoid being prompted about backend changes"
echo "=============================================="