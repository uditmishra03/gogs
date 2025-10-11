terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Local backend - state will be stored locally
  # Comment out this section if you want to use S3 backend
  backend "local" {
    path = "terraform.tfstate"
  }
}