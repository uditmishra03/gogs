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

## Prerequisites

### Local Development Environment
1. **AWS CLI** v2.x configured with appropriate permissions
2. **Terraform** v1.5+ installed
3. **kubectl** v1.28+ installed
4. **Helm** v3.12+ installed
5. **AWS Load Balancer Controller** (will be installed via Helm)

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
region = "us-west-2"
cluster_name = "gogs-production"
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
aws eks update-kubeconfig --region us-west-2 --name gogs-production
```

### Phase 2: EKS Add-ons Installation

#### Step 1: Install AWS Load Balancer Controller
```bash
# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=gogs-production \
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
            "cluster_name": "gogs-production",
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
aws eks update-cluster-version --name gogs-production --version 1.28

# Update node groups
aws eks update-nodegroup-version --cluster-name gogs-production --nodegroup-name <nodegroup-name>
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