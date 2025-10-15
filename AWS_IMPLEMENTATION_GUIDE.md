# Production-Grade Gogs Git Service on Amazon EKS
## Implementation Guide

### Table of Contents
1. [Problem Statement](#problem-statement)
2. [Architecture Overview](#architecture-overview)
3. [Infrastructure Components](#infrastructure-components)
4. [Prerequisites](#prerequisites)
5. [Implementation Steps](#implementation-steps)
6. [Security Considerations](#security-considerations)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
9. [Cost Optimization](#cost-optimization)
10. [Troubleshooting](#troubleshooting)

---

## Problem Statement

Build a production-grade, self-hosted Git service using **Gogs** on Amazon EKS, where:
- Terraform provisions the entire AWS infrastructure — VPC, IAM, and EKS cluster with node groups
- Helm deploys Gogs with a PostgreSQL backend, persistent storage via EBS, and Ingress for external access
- The setup must be fully reproducible, secure, and scalable, with minimal manual intervention
- Goal: Deliver an automated, version-controlled deployment pipeline that spins up a complete Git hosting platform inside AWS with one command each for infrastructure and application

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                           VPC (10.0.0.0/16)                     │    │
│  │                                                                 │    │
│  │    ┌──────────────────┐           ┌──────────────────┐          │    │
│  │    │  Public Subnet   │           │  Public Subnet   │          │    │
│  │    │  10.0.101.0/24   │           │  10.0.102.0/24   │          │    │
│  │    │      AZ-a        │           │      AZ-b        │          │    │
│  │    │                  │           │                  │          │    │
│  │    │ ┌─────────────┐  │           │ ┌─────────────┐  │          │    │
│  │    │ │   NAT GW    │  │           │ │    ALB      │  │          │    │
│  │    │ │             │  │           │ │ (Internet   │  │          │    │
│  │    │ └─────────────┘  │           │ │  Facing)    │  │          │    │
│  │    └──────────────────┘           │ └─────────────┘  │          │    │
│  │                                   └──────────────────┘          │    │
│  │                                                                 │    │
│  │    ┌──────────────────┐           ┌──────────────────┐          │    │
│  │    │ Private Subnet   │           │ Private Subnet   │          │    │
│  │    │  10.0.1.0/24     │           │  10.0.2.0/24     │          │    │
│  │    │      AZ-a        │           │      AZ-b        │          │    │
│  │    │                  │           │                  │          │    │
│  │    │┌────────────────┐│           │┌────────────────┐│          │    │
│  │    ││  EKS Nodes     ││           ││  EKS Nodes     ││          │    │
│  │    ││                ││           ││                ││          │    │
│  │    ││┌──────────────┐││           ││┌──────────────┐││          │    │
│  │    │││    Gogs      │││           │││    Gogs      │││          │    │
│  │    │││    Pod       │││           │││    Pod       │││          │    │
│  │    ││└──────────────┘││           ││└──────────────┘││          │    │
│  │    ││                ││           ││                ││          │    │
│  │    ││┌──────────────┐││           ││┌──────────────┐││          │    │
│  │    │││ PostgreSQL   │││           │││ PostgreSQL   │││          │    │
│  │    │││    Pod       │││           │││    Pod       │││          │    │
│  │    ││└──────────────┘││           ││└──────────────┘││          │    │
│  │    │└────────────────┘│           │└────────────────┘│          │    │
│  │    └──────────────────┘           └──────────────────┘          │    │
│  │                                                                 │    │
│  │                 ┌─────────────────────────────┐                 │    │
│  │                 │       EBS Volumes           │                 │    │
│  │                 │   (Persistent Storage)      │                 │    │
│  │                 │                             │                 │    │
│  │                 │  • Gogs Data (50Gi)         │                 │    │
│  │                 │  • PostgreSQL Data (20Gi)   │                 │    │
│  │                 │  • Backups & Logs           │                 │    │
│  │                 └─────────────────────────────┘                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  External Components:                                                   │
│  • Route 53 (DNS)                                                       │
│  • ACM (SSL Certificates)                                               │
│  • CloudWatch (Monitoring & Logs)                                       │
│  • AWS Backup (EBS Snapshots)                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow:
1. **Internet** → **Route 53** → **ALB** → **Ingress Controller** → **Gogs Service** → **Gogs Pods**
2. **Gogs Pods** ↔ **PostgreSQL Service** ↔ **PostgreSQL Pods**
3. **All Pods** → **EBS CSI Driver** → **EBS Volumes** (Persistent Storage)

### High Availability Design:
- **Multi-AZ deployment** across 2 availability zones
- **Auto-scaling** for both pods and EC2 nodes
- **Load balancing** with health checks
- **Persistent data** survives pod restarts
- **Automated backups** for disaster recovery

### Key Components:
- **VPC**: Multi-AZ setup with public/private subnets
- **EKS Cluster**: Managed Kubernetes service
- **Node Groups**: Auto-scaling EC2 instances
- **Application Load Balancer**: External access via Ingress
- **EBS CSI Driver**: Persistent storage for Gogs and PostgreSQL
- **IAM Roles**: Secure service-to-service communication

---

## Infrastructure Components

### 1. Networking (VPC)
- **CIDR**: 10.0.0.0/16
- **Public Subnets**: 10.0.101.0/24, 10.0.102.0/24 (for ALB, NAT Gateway)
- **Private Subnets**: 10.0.1.0/24, 10.0.2.0/24 (for EKS nodes)
- **NAT Gateway**: Single NAT for cost optimization
- **Internet Gateway**: Public internet access

### 2. EKS Cluster
- **Version**: Latest stable Kubernetes version
- **Node Groups**: Managed EC2 instances with auto-scaling
- **Instance Types**: t3.medium (adjustable based on workload)
- **Networking**: VPC CNI for pod networking

### 3. Storage
- **EBS CSI Driver**: For persistent volumes
- **Storage Classes**: gp3 for cost-effective performance
- **Backup**: EBS snapshots for disaster recovery

### 4. Security
- **IAM Roles**: Separate roles for cluster, nodes, and service accounts
- **Security Groups**: Restrictive rules for network access
- **Pod Security Standards**: Enforced security policies
- **Network Policies**: Traffic segmentation

---

## DevOps Infrastructure Setup

Before deploying the main Gogs infrastructure, you need to provision a DevOps/Management instance that will serve as your deployment control center.

### 1. DevOps EC2 Instance Requirements

#### Instance Specifications:
- **Instance Name**: `gogs-devops`
- **Instance Type**: `t3.medium` (2 vCPU, 4 GiB RAM)
- **Operating System**: Ubuntu 22.04 LTS
- **Storage**: 20 GiB gp3 EBS volume
- **Network**: Public subnet with internet access
- **Security Group**: Allow SSH (port 22) from your IP

#### Terraform Configuration for DevOps Instance:
```hcl
# devops-instance.tf
resource "aws_instance" "gogs_devops" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.medium"
  key_name      = var.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.devops_sg.id]
  subnet_id              = aws_subnet.public[0].id
  
  associate_public_ip_address = true
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }
  
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {}))
  
  tags = {
    Name        = "gogs-devops"
    Environment = "production"
    Purpose     = "DevOps Management Instance"
  }
}

resource "aws_security_group" "devops_sg" {
  name        = "gogs-devops-sg"
  description = "Security group for DevOps instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr] # Your IP address
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "gogs-devops-sg"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

#### User Data Script (user-data.sh):
```bash
#!/bin/bash
# Update system
apt-get update -y
apt-get upgrade -y

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Install required packages
apt-get install -y git curl wget unzip software-properties-common apt-transport-https ca-certificates gnupg

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_1.6.6_linux_amd64.zip

# Install kubectl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Create working directory
mkdir -p /home/ubuntu/gogs-deployment
chown ubuntu:ubuntu /home/ubuntu/gogs-deployment

# Clone the repository (optional - if repository is public)
# git clone https://github.com/uditmishra03/gogs.git /home/ubuntu/gogs-deployment/
```

### 2. IAM Role for DevOps Instance

#### IAM Role Configuration:
```hcl
# iam-devops.tf
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
}

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
          "cloudwatch:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "devops_profile" {
  name = "gogs-devops-profile"
  role = aws_iam_role.devops_role.name
}

# Attach the instance profile to the EC2 instance
resource "aws_instance" "gogs_devops" {
  # ... previous configuration ...
  iam_instance_profile = aws_iam_instance_profile.devops_profile.name
  # ... rest of configuration ...
}
```

### 3. Deployment Workflow

#### Step-by-Step Process:

1. **Provision DevOps Instance**:
   ```bash
   # Create a separate directory for DevOps infrastructure
   mkdir gogs-devops-setup
   cd gogs-devops-setup
   
   # Create Terraform files for DevOps instance
   # (devops-instance.tf, iam-devops.tf, variables.tf)
   
   terraform init
   terraform plan
   terraform apply
   ```

2. **Connect to DevOps Instance**:
   ```bash
   # Get the public IP from Terraform output
   ssh -i your-key.pem ubuntu@<DEVOPS_INSTANCE_PUBLIC_IP>
   ```

3. **Verify Tools Installation**:
   ```bash
   # On the DevOps instance, verify all tools are installed
   aws --version
   terraform --version
   kubectl version --client
   helm version
   docker --version
   ```

4. **Setup AWS Credentials**:
   ```bash
   # Configure AWS CLI (credentials are inherited from IAM role)
   aws configure list
   aws sts get-caller-identity
   ```

5. **Clone and Deploy**:
   ```bash
   # Clone your repository
   git clone https://github.com/uditmishra03/gogs.git
   cd gogs/eks-prod
   
   # Deploy infrastructure
   terraform init
   terraform plan
   terraform apply
   ```

### 4. DevOps Instance Outputs

Add these outputs to your DevOps Terraform configuration:

```hcl
# outputs.tf
output "devops_instance_public_ip" {
  description = "Public IP address of the DevOps instance"
  value       = aws_instance.gogs_devops.public_ip
}

output "devops_instance_id" {
  description = "ID of the DevOps instance"
  value       = aws_instance.gogs_devops.id
}

output "ssh_connection_command" {
  description = "SSH command to connect to DevOps instance"
  value       = "ssh -i your-key.pem ec2-user@${aws_instance.gogs_devops.public_ip}"
}
```

### 5. Security Considerations

- **Key Pair**: Ensure you have created an EC2 Key Pair before provisioning
- **IP Restriction**: Limit SSH access to your specific IP address
- **IAM Role**: Use IAM roles instead of hardcoded credentials
- **Encryption**: Enable EBS encryption for the root volume
- **Updates**: Keep the instance updated with latest security patches

### 6. Cost Considerations

- **Instance Type**: t3.medium is sufficient for most deployments
- **Shutdown**: Stop the instance when not in use to save costs
- **Spot Instances**: Consider using Spot instances for cost savings (non-production)
- **Monitoring**: Set up CloudWatch billing alerts

---

## Prerequisites

### Option 1: DevOps EC2 Instance (Recommended)
Use the `gogs-devops` EC2 instance provisioned in the previous section. This instance comes pre-configured with all required tools:

1. **AWS CLI** v2.x (pre-installed)
2. **Terraform** v1.6+ (pre-installed)
3. **kubectl** v1.28+ (pre-installed)
4. **Helm** v3.12+ (pre-installed)
5. **Docker** (pre-installed for development/testing)
6. **IAM Role** with required permissions (pre-configured)

**Connection Command**:
```bash
ssh -i your-key.pem ubuntu@<DEVOPS_INSTANCE_PUBLIC_IP>
```

### Option 2: Local Development Environment
If you prefer to run from your local machine:

1. **AWS CLI** v2.x configured with appropriate permissions
2. **Terraform** v1.5+ installed
3. **kubectl** v1.28+ installed
4. **Helm** v3.12+ installed
5. **Git** for repository management

### AWS Permissions Required
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "eks:*",
                "iam:*",
                "autoscaling:*",
                "elasticloadbalancing:*",
                "route53:*"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## Implementation Steps

### Phase 1: Infrastructure Provisioning

#### Step 1: Initialize Terraform
```bash
cd eks-prod
terraform init
```

#### Step 2: Configure Variables
Create `terraform.tfvars`:
```hcl
region = "us-east-1" # Adjust to your chosen region
cluster_name = "gogs-prod-cluster"
vpc_cidr = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
node_instance_type = "t3.medium"
node_desired_capacity = 2
node_max_capacity = 10
node_min_capacity = 1
```

#### Step 3: Plan and Apply Infrastructure
```bash
terraform plan
terraform apply
```

#### Step 4: Configure kubectl
```bash
aws eks update-kubeconfig --region us-east-1 --name gogs-prod-cluster
```

### Phase 2: EKS Add-ons Installation

#### Step 1: Install AWS Load Balancer Controller
```bash
# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=gogs-prod-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

#### Step 2: Install EBS CSI Driver
```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system
```

### Phase 3: Application Deployment

#### Step 1: Configure Helm Values
Update `helm-chart/values.yaml`:
```yaml
image:
  repository: gogs/gogs
  tag: "0.13.0"  # Use specific version for production
  pullPolicy: IfNotPresent

postgres:
  enabled: true
  image: postgres:15-alpine
  user: gogs
  password: "CHANGE_ME_SECURE_PASSWORD"
  database: gogs
  storage: 20Gi
  storageClassName: gp3

gogs:
  replicas: 2
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

service:
  type: ClusterIP
  webPort: 3000
  sshPort: 22

persistence:
  enabled: true
  size: 50Gi
  storageClassName: gp3

ingress:
  enabled: true
  className: alb
  hostname: git.yourdomain.com
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-redirect: '443'
  tls:
    enabled: true
    secretName: gogs-tls

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

#### Step 2: Create Namespace and Secrets
```bash
kubectl create namespace gogs

# Create database password secret
kubectl create secret generic postgres-secret \
  --from-literal=password='YOUR_SECURE_DB_PASSWORD' \
  -n gogs
```

#### Step 3: Deploy Gogs via Helm
```bash
cd helm-chart
helm install gogs . -n gogs -f values.yaml
```

### Phase 4: DNS and SSL Configuration

#### Step 1: Configure Route 53 (if using AWS DNS)
```bash
# Get ALB DNS name
kubectl get ingress -n gogs

# Create CNAME record pointing to ALB
aws route53 change-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "git.yourdomain.com",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "ALB_DNS_NAME"}]
    }
  }]
}'
```

#### Step 2: Install cert-manager for SSL
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

---

## Security Considerations

### 1. Network Security
```yaml
# NetworkPolicy example
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gogs-network-policy
  namespace: gogs
spec:
  podSelector:
    matchLabels:
      app: gogs
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
```

### 2. Pod Security Standards
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gogs
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 3. IAM and RBAC
- Use IAM roles for service accounts (IRSA)
- Implement least privilege principle
- Regular access reviews and rotation

### 4. Data Encryption
- Enable EBS encryption at rest
- Use TLS 1.3 for all communications
- Encrypt database connections

---

## Monitoring and Logging

### 1. Install Monitoring Stack
```bash
# Install Prometheus and Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

### 2. CloudWatch Integration
```yaml
# CloudWatch agent for logs
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "cluster_name": "gogs-prod-cluster",
            "metrics_collection_interval": 60
          }
        }
      }
    }
```

### 3. Key Metrics to Monitor
- Pod CPU/Memory utilization
- Database connection count
- Storage utilization
- Network traffic
- Application response times

---

## Backup and Disaster Recovery

### 1. Database Backups
```bash
# Automated PostgreSQL backups using CronJob
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: gogs
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-backup
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - |
              pg_dump -h postgres-service -U gogs -d gogs > /backup/gogs-$(date +%Y%m%d).sql
              aws s3 cp /backup/gogs-$(date +%Y%m%d).sql s3://your-backup-bucket/
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
```

### 2. EBS Snapshot Strategy
```bash
# Automated EBS snapshots via AWS Backup
aws backup create-backup-plan --backup-plan '{
  "BackupPlanName": "gogs-backup-plan",
  "Rules": [{
    "RuleName": "daily-backup",
    "TargetBackupVault": "default",
    "ScheduleExpression": "cron(0 2 ? * * *)",
    "Lifecycle": {
      "DeleteAfterDays": 30
    }
  }]
}'
```

### 3. Disaster Recovery Procedures
1. **RTO (Recovery Time Objective)**: 4 hours
2. **RPO (Recovery Point Objective)**: 24 hours
3. **Multi-region deployment** for critical workloads
4. **Regular disaster recovery testing**

---

## Cost Optimization

### 1. Right-sizing Recommendations
- Use **t3.medium** instances for initial deployment
- Enable **cluster autoscaler** for dynamic scaling
- Implement **Vertical Pod Autoscaler (VPA)**

### 2. Storage Optimization
```yaml
# Use gp3 storage class for better price/performance
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-optimized
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
allowVolumeExpansion: true
```

### 3. Reserved Instances
- Purchase 1-year Reserved Instances for predictable workloads
- Use Savings Plans for flexibility

### 4. Cost Monitoring
```bash
# Install AWS Cost Controller
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Pod Scheduling Issues
```bash
# Check node capacity
kubectl describe nodes

# Check pod status
kubectl get pods -n gogs -o wide

# Check events
kubectl get events -n gogs --sort-by='.lastTimestamp'
```

#### 2. Persistent Volume Issues
```bash
# Check PVC status
kubectl get pvc -n gogs

# Check storage class
kubectl get storageclass

# Describe PVC for events
kubectl describe pvc <pvc-name> -n gogs
```

#### 3. Ingress Issues
```bash
# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress status
kubectl describe ingress -n gogs

# Verify ALB in AWS Console
aws elbv2 describe-load-balancers
```

#### 4. Database Connection Issues
```bash
# Check PostgreSQL pod logs
kubectl logs -n gogs <postgres-pod-name>

# Test database connectivity
kubectl exec -it <gogs-pod> -n gogs -- psql -h postgres-service -U gogs -d gogs
```

### Useful Commands

```bash
# Get cluster information
kubectl cluster-info

# Check all resources in gogs namespace
kubectl get all -n gogs

# Port forward for local access
kubectl port-forward svc/gogs-service 3000:3000 -n gogs

# Get pod logs
kubectl logs -f deployment/gogs -n gogs

# Execute commands in pod
kubectl exec -it <pod-name> -n gogs -- /bin/sh

# Scale deployment
kubectl scale deployment gogs --replicas=3 -n gogs
```

---

## Maintenance and Updates

### 1. Regular Updates
- **Monthly**: Update Helm charts and container images
- **Quarterly**: Update EKS cluster version
- **As needed**: Security patches and bug fixes

### 2. Update Procedure
```bash
# Update Helm chart
helm repo update
helm upgrade gogs . -n gogs -f values.yaml

# Update EKS cluster
aws eks update-cluster-version --name gogs-prod-cluster --version 1.31 # example target version

# Update node groups
aws eks update-nodegroup-version --cluster-name gogs-prod-cluster --nodegroup-name <nodegroup-name>
```

### 3. Rollback Strategy
```bash
# Rollback Helm release
helm rollback gogs <revision-number> -n gogs

# Check rollback status
helm history gogs -n gogs
```

---

## Conclusion

This implementation provides a production-ready, self-hosted Git service using Gogs on Amazon EKS with the following key benefits:

1. **Fully Automated**: Infrastructure as Code with Terraform
2. **Scalable**: Auto-scaling pods and nodes based on demand
3. **Secure**: Multi-layered security with IAM, RBAC, and network policies
4. **Resilient**: Multi-AZ deployment with automated backups
5. **Cost-Effective**: Optimized resource allocation and usage

The deployment follows AWS Well-Architected Framework principles and provides a solid foundation for hosting Git repositories in a corporate environment.

### Next Steps
1. Customize the configuration for your specific requirements
2. Set up monitoring and alerting
3. Implement CI/CD pipelines for application updates
4. Configure backup and disaster recovery procedures
5. Conduct security assessments and penetration testing

For any issues or questions, refer to the troubleshooting section or consult the official documentation for each component.