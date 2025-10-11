# Quick Setup Guide for Existing EC2 Instance

Since you've already launched your Ubuntu EC2 instance manually, follow these steps to install all the required tools for Gogs deployment.

## Prerequisites

- Ubuntu 22.04 LTS EC2 instance (already launched)
- SSH access to the instance
- Internet connectivity from the instance

## Installation Steps

### Step 1: Connect to Your Instance
```bash
ssh -i your-key.pem ubuntu@your-instance-public-ip
```

### Step 2: Download the Setup Script
```bash
# Download the setup script
wget https://raw.githubusercontent.com/uditmishra03/gogs/main/setup-devops-environment.sh

# Or if you have the repository locally, copy it:
# scp -i your-key.pem setup-devops-environment.sh ubuntu@your-instance-ip:~/
```

### Step 3: Make the Script Executable and Run It
```bash
chmod +x setup-devops-environment.sh
./setup-devops-environment.sh
```

The script will automatically:
- Update your Ubuntu system
- Install AWS CLI v2
- Install Terraform v1.6.6
- Install kubectl (latest stable)
- Install Helm v3
- Install Docker CE
- Install eksctl
- Install k9s (Kubernetes CLI UI)
- Install kubectx/kubens
- Clone the Gogs repository
- Set up useful aliases and functions
- Create a verification script

### Step 4: Restart Your SSH Session
After the script completes, log out and log back in to apply Docker group membership:
```bash
exit
ssh -i your-key.pem ubuntu@your-instance-public-ip
```

### Step 5: Configure AWS Credentials
```bash
aws configure
```
Enter your:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-west-2`)
- Default output format (e.g., `json`)

### Step 6: Verify Everything Works
```bash
./verify-setup.sh
```

This will check all installed tools and AWS configuration.

## What Gets Installed

### Core Tools
- **AWS CLI v2**: Latest version for AWS service interaction
- **Terraform v1.6.6**: Infrastructure as Code
- **kubectl**: Kubernetes command-line tool
- **Helm v3**: Kubernetes package manager
- **Docker CE**: Container platform
- **eksctl**: EKS cluster management tool
- **k9s**: Kubernetes CLI UI
- **kubectx/kubens**: Kubernetes context and namespace switching

### Additional Utilities
- **git**: Version control
- **jq**: JSON processor
- **vim**: Text editor
- **htop**: Process viewer
- **tree**: Directory tree viewer
- **curl/wget**: Download tools

### Useful Aliases Added
```bash
# Kubernetes shortcuts
k='kubectl'
kgp='kubectl get pods'
kgs='kubectl get services'
kgd='kubectl get deployments'

# Terraform shortcuts
tfi='terraform init'
tfp='terraform plan'
tfa='terraform apply'

# AWS shortcuts
awswho='aws sts get-caller-identity'
```

### Custom Functions Added
```bash
klog <pod-name>              # Follow pod logs
kexec <pod-name>             # Execute into pod
kport <local-port> <svc:port> # Port forward to service
switch-kube-context <context> # Switch kubectl context
gogs-welcome                 # Show welcome message
```

## Next Steps

After successful setup:

1. **Navigate to the infrastructure directory**:
   ```bash
   cd ~/gogs-deployment/eks-prod
   ```

2. **Configure Terraform variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars  # Edit with your specific values
   ```

3. **Deploy the EKS infrastructure**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Deploy the Gogs application**:
   ```bash
   cd ~/gogs-deployment/helm-chart
   helm install gogs . -n gogs --create-namespace -f values.yaml
   ```

## Troubleshooting

### If Docker commands fail:
```bash
# Check if you're in the docker group
groups $USER

# If not, add yourself and restart session
sudo usermod -aG docker ubuntu
exit
# SSH back in
```

### If AWS commands fail:
```bash
# Check AWS configuration
aws configure list
aws sts get-caller-identity
```

### If kubectl fails to connect:
```bash
# Update kubeconfig after EKS cluster is created
aws eks update-kubeconfig --region your-region --name your-cluster-name
```

### Script Logs
All installation logs are saved to `/var/log/devops-setup/setup-TIMESTAMP.log` for debugging.

## Support

- Check the main [AWS Implementation Guide](AWS_IMPLEMENTATION_GUIDE.md) for complete deployment instructions
- Use the `verify-setup.sh` script to diagnose issues
- Review installation logs if any tools fail to install

## Security Notes

- The script installs tools system-wide but runs as the ubuntu user
- Docker group membership is added for the ubuntu user
- All downloads are from official sources
- GPG keys are verified where applicable