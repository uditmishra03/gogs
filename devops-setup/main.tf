# DevOps Infrastructure for Gogs Deployment
# This creates the management instance used to deploy the main Gogs infrastructure

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC for DevOps infrastructure
resource "aws_vpc" "devops_vpc" {
  cidr_block           = var.devops_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "gogs-devops-vpc"
    Environment = var.environment
    Purpose     = "DevOps Management Infrastructure"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "devops_igw" {
  vpc_id = aws_vpc.devops_vpc.id

  tags = {
    Name        = "gogs-devops-igw"
    Environment = var.environment
  }
}

# Public Subnet
resource "aws_subnet" "devops_public" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = var.devops_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "gogs-devops-public-subnet"
    Environment = var.environment
    Type        = "Public"
  }
}

# Route Table
resource "aws_route_table" "devops_public" {
  vpc_id = aws_vpc.devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devops_igw.id
  }

  tags = {
    Name        = "gogs-devops-public-rt"
    Environment = var.environment
  }
}

# Route Table Association
resource "aws_route_table_association" "devops_public" {
  subnet_id      = aws_subnet.devops_public.id
  route_table_id = aws_route_table.devops_public.id
}

# Security Group for DevOps Instance
resource "aws_security_group" "devops_sg" {
  name        = "gogs-devops-sg"
  description = "Security group for DevOps management instance"
  vpc_id      = aws_vpc.devops_vpc.id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "gogs-devops-sg"
    Environment = var.environment
  }
}

# IAM Role for DevOps Instance
resource "aws_iam_role" "devops_role" {
  name = "gogs-devops-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "gogs-devops-role"
    Environment = var.environment
  }
}

# IAM Policy for DevOps Instance
resource "aws_iam_role_policy" "devops_policy" {
  name = "gogs-devops-policy"
  role = aws_iam_role.devops_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "eks:*",
          "iam:*",
          "autoscaling:*",
          "elasticloadbalancing:*",
          "route53:*",
          "s3:*",
          "cloudformation:*",
          "logs:*",
          "cloudwatch:*",
          "backup:*",
          "rds:*",
          "ssm:*",
          "secretsmanager:*",
          "kms:*",
          "acm:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "devops_profile" {
  name = "gogs-devops-profile"
  role = aws_iam_role.devops_role.name

  tags = {
    Name        = "gogs-devops-profile"
    Environment = var.environment
  }
}

# DevOps EC2 Instance
resource "aws_instance" "gogs_devops" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.devops_instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids      = [aws_security_group.devops_sg.id]
  subnet_id                   = aws_subnet.devops_public.id
  iam_instance_profile        = aws_iam_instance_profile.devops_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.devops_instance_storage
    encrypted   = true

    tags = {
      Name        = "gogs-devops-root-volume"
      Environment = var.environment
    }
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    git_repo_url = var.git_repo_url
  }))

  tags = {
    Name        = "gogs-devops"
    Environment = var.environment
    Purpose     = "DevOps Management Instance"
    Owner       = var.owner
  }
}

# Elastic IP for DevOps Instance (optional but recommended)
resource "aws_eip" "devops_eip" {
  count    = var.create_elastic_ip ? 1 : 0
  instance = aws_instance.gogs_devops.id
  domain   = "vpc"

  tags = {
    Name        = "gogs-devops-eip"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.devops_igw]
}