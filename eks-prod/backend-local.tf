# Local backend configuration (EXAMPLE)
# Rename or copy this file to backend.tf (after removing existing backend.tf)
# then run: terraform init -reconfigure
# Only one terraform { backend ... } block can exist in the directory.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}