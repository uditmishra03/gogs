#!/bin/bash

# Script to create S3 backend for Terraform state
# This creates the S3 bucket and DynamoDB table needed for Terraform remote state

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

# Configuration
BUCKET_NAME="gogs-terraform-$(date +%s)"  # Add timestamp to make it unique
REGION="us-west-2"  # Change this to your preferred region
DYNAMODB_TABLE="terraform-locks"

log "🚀 Setting up Terraform S3 backend..."

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Get current AWS account and region info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CURRENT_REGION=$(aws configure get region)

info "AWS Account: $ACCOUNT_ID"
info "Current Region: $CURRENT_REGION"
info "Will create bucket in region: $REGION"

# Create S3 bucket
log "Creating S3 bucket: $BUCKET_NAME"
if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
fi

# Enable versioning
log "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Enable server-side encryption
log "Enabling server-side encryption on S3 bucket..."
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

# Block public access
log "Blocking public access on S3 bucket..."
aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
log "Creating DynamoDB table for state locking: $DYNAMODB_TABLE"
aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "$REGION" || warn "DynamoDB table might already exist"

# Wait for DynamoDB table to be created
log "Waiting for DynamoDB table to be active..."
aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"

# Update backend.tf with the new bucket name and region
log "Updating backend.tf configuration..."
cat > ../eks-prod/backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "eks/prod/terraform.tfstate"
    region         = "$REGION"
    encrypt        = true
    dynamodb_table = "$DYNAMODB_TABLE"
  }
}
EOF

log "✅ S3 backend setup completed successfully!"
echo ""
echo "=============================================="
echo "📋 BACKEND CONFIGURATION CREATED:"
echo "=============================================="
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "Region: $REGION"
echo "State Key: eks/prod/terraform.tfstate"
echo ""
echo "✅ backend.tf has been updated with the new configuration"
echo ""
echo "🚀 Next steps:"
echo "1. cd ../eks-prod"
echo "2. terraform init"
echo "3. terraform plan"
echo ""
echo "=============================================="