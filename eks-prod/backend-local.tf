# Local backend configuration
# Use this for development/testing when you don't need shared state
# To activate: cp backend-local.tf backend.tf && terraform init -reconfigure

terraform {
  # Local backend - state will be stored locally
  backend "local" {
    path = "terraform.tfstate"
  }
}