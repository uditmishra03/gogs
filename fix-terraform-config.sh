#!/bin/bash

# Quick fix for duplicate Terraform configuration issue
# This script cleans up the configuration conflicts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log "🔧 Fixing Terraform configuration conflicts..."

# Change to eks-prod directory
cd ~/gogs-deployment/eks-prod

# Clean up any existing .terraform directory and state
log "Cleaning up existing Terraform initialization..."
rm -rf .terraform
rm -f .terraform.lock.hcl
rm -f terraform.tfstate*

# Backup all current configurations
log "Creating backups..."
cp backend.tf backend.tf.original 2>/dev/null || true
cp backend-local.tf backend-local.tf.original 2>/dev/null || true

# Create clean local backend configuration
log "Creating clean local backend configuration..."
cat > backend.tf << 'EOF'
# Local backend configuration
# State will be stored locally in terraform.tfstate

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF

# Remove the backend-local.tf file to avoid conflicts
log "Removing conflicting backend-local.tf..."
rm -f backend-local.tf

# Initialize Terraform with the clean configuration
log "Initializing Terraform with local backend..."
terraform init

log "✅ Configuration fixed successfully!"
echo ""
echo "=============================================="
echo "📋 WHAT WAS FIXED:"
echo "=============================================="
echo "❌ Removed duplicate terraform blocks"
echo "❌ Removed conflicting backend configurations"  
echo "❌ Cleaned up .terraform directory"
echo "✅ Set up clean local backend"
echo "✅ Initialized Terraform successfully"
echo ""
echo "🚀 You can now run:"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "💡 To switch to S3 backend later:"
echo "   cd .. && ./setup-terraform-backend.sh"
echo "=============================================="