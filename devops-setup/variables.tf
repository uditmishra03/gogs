# Variables for DevOps Infrastructure

variable "region" {
  description = "AWS region for DevOps infrastructure"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "devops-team"
}

variable "devops_vpc_cidr" {
  description = "CIDR block for the DevOps VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "devops_public_subnet_cidr" {
  description = "CIDR block for the DevOps public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "admin_ip_cidr" {
  description = "CIDR block for admin IP access (your IP address)"
  type        = string
  # Default to a placeholder - MUST be changed to your actual IP
  default     = "0.0.0.0/32"
  
  validation {
    condition     = can(cidrhost(var.admin_ip_cidr, 0))
    error_message = "The admin_ip_cidr must be a valid CIDR block (e.g., 203.0.113.1/32 for a single IP)."
  }
}

variable "key_pair_name" {
  description = "Name of the AWS Key Pair for SSH access"
  type        = string
  # No default - must be provided
}

variable "devops_instance_type" {
  description = "EC2 instance type for DevOps instance"
  type        = string
  default     = "t3.medium"
}

variable "devops_instance_storage" {
  description = "Root volume size for DevOps instance (in GB)"
  type        = number
  default     = 20
}

variable "git_repo_url" {
  description = "Git repository URL for the Gogs project"
  type        = string
  default     = "https://github.com/uditmishra03/gogs.git"
}

variable "create_elastic_ip" {
  description = "Whether to create an Elastic IP for the DevOps instance"
  type        = bool
  default     = true
}