# S3 backend configuration  
# Use this for production when you need shared state and locking
# Requires S3 bucket and DynamoDB table to be created first

terraform {
  backend "s3" {
    # Updated bucket name (manually created)
    bucket         = "gogs-terraform-14101025"
    key            = "eks/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

