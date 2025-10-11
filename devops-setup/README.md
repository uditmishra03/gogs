# Gogs DevOps Infrastructure Setup

This directory contains Terraform configuration to provision a DevOps management instance that will be used to deploy the main Gogs infrastructure on EKS.

## Overview

The DevOps instance (`gogs-devops`) serves as a centralized management server with all necessary tools pre-installed for deploying and managing the Gogs Git service on Amazon EKS.

## What Gets Provisioned

### Infrastructure
- **VPC**: Dedicated VPC for DevOps infrastructure (10.100.0.0/16)
- **EC2 Instance**: t3.medium Ubuntu 22.04 LTS instance with all deployment tools
- **Security Group**: SSH access restricted to your IP
- **IAM Role**: Full permissions for AWS resource management
- **Elastic IP**: Static public IP (optional)

### Pre-installed Tools
- **AWS CLI v2**: AWS service interaction
- **Terraform v1.6+**: Infrastructure as Code
- **kubectl v1.28+**: Kubernetes management
- **Helm v3.12+**: Kubernetes package management
- **Docker**: Container management
- **eksctl**: EKS cluster management
- **k9s**: Kubernetes CLI UI
- **kubectx/kubens**: Kubernetes context switching

## Quick Start

### Prerequisites
1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured locally
3. **EC2 Key Pair** created in your target region

### Step 1: Configure Variables
```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

**Important**: Update these required values:
- `admin_ip_cidr`: Your public IP address (find at https://whatismyipaddress.com/)
- `key_pair_name`: Your AWS EC2 Key Pair name

### Step 2: Deploy DevOps Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Step 3: Connect to DevOps Instance
```bash
# Get connection command from output
terraform output ssh_connection_command

# Connect via SSH
ssh -i your-key.pem ubuntu@<DEVOPS_INSTANCE_IP>
```

### Step 4: Verify Setup
```bash
# On the DevOps instance, run verification
./verify-setup.sh

# Check AWS access
aws sts get-caller-identity
```

### Step 5: Deploy Gogs Infrastructure
```bash
# Navigate to the main infrastructure
cd ~/gogs-deployment/eks-prod

# Configure and deploy
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## File Structure

```
devops-setup/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── user-data.sh              # Instance initialization script
├── terraform.tfvars.example  # Example configuration
└── README.md                 # This file
```

## Configuration Options

### Instance Types
- **t3.medium** (default): 2 vCPU, 4 GB RAM - suitable for most deployments
- **t3.large**: 2 vCPU, 8 GB RAM - for larger deployments
- **t3.xlarge**: 4 vCPU, 16 GB RAM - for enterprise deployments

### Networking
- Default VPC CIDR: `10.100.0.0/16`
- Default Subnet CIDR: `10.100.1.0/24`
- Customizable in `terraform.tfvars`

### Security
- SSH access restricted to your IP only
- IAM role with comprehensive AWS permissions
- EBS encryption enabled
- Security group with minimal required access

## Cost Considerations

### Estimated Monthly Costs (us-west-2)
- **t3.medium**: ~$30-35/month
- **Elastic IP**: ~$3.65/month (when not attached to running instance)
- **EBS Storage (20GB)**: ~$2/month

### Cost Optimization Tips
1. **Stop when not in use**: Stop the instance during off-hours
2. **Right-size**: Start with t3.medium, scale up if needed
3. **Spot instances**: Consider for non-production environments
4. **Set billing alerts**: Monitor unexpected costs

## Outputs

After deployment, you'll get:
- **Public IP**: For SSH access
- **SSH Command**: Ready-to-use connection command
- **Instance ID**: For AWS console reference
- **Next Steps**: Helpful guidance for deployment

## Troubleshooting

### Common Issues

1. **SSH Connection Refused**
   ```bash
   # Check security group allows your IP
   aws ec2 describe-security-groups --group-ids <sg-id>
   
   # Verify your current IP
   curl https://checkip.amazonaws.com/
   ```

2. **Instance Not Ready**
   ```bash
   # Check instance status
   aws ec2 describe-instances --instance-ids <instance-id>
   
   # View user-data logs
   ssh -i key.pem ubuntu@<ip> "sudo tail -f /var/log/user-data.log"
   ```

3. **Tools Not Installed**
   ```bash
   # Check user-data execution
   sudo cat /var/log/cloud-init-output.log
   
   # Re-run setup script
   sudo /var/lib/cloud/instance/user-data.txt
   ```

### Useful Commands

```bash
# Check instance status
terraform show aws_instance.gogs_devops

# Get instance public IP
terraform output devops_instance_public_ip

# Refresh state
terraform refresh

# Destroy infrastructure
terraform destroy
```

## Security Best Practices

1. **IP Restriction**: Always restrict SSH to your specific IP
2. **Key Management**: Keep EC2 key pairs secure
3. **Regular Updates**: Keep the instance updated with security patches
4. **Monitoring**: Enable CloudWatch monitoring
5. **Backup**: Regular snapshots of the instance

## Next Steps

After the DevOps instance is ready:

1. **Connect** to the instance
2. **Verify** all tools are working
3. **Clone** the Gogs repository
4. **Configure** the main infrastructure variables
5. **Deploy** the EKS cluster and Gogs application

For detailed deployment instructions, see the main [AWS Implementation Guide](../AWS_IMPLEMENTATION_GUIDE.md).

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs
3. Verify your Terraform configuration
4. Ensure your AWS permissions are correct

## Clean Up

To remove all resources:
```bash
terraform destroy
```

**Warning**: This will permanently delete the DevOps instance and all associated resources.