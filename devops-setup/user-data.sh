#!/bin/bash

# User Data Script for Gogs DevOps Instance (Ubuntu 22.04 LTS)
# This script sets up all required tools for deploying Gogs on EKS

echo "Starting DevOps instance setup..." >> /var/log/user-data.log

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update -y
apt-get upgrade -y

# Install basic packages
apt-get install -y git curl wget unzip jq vim htop tree software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# Create log directory
mkdir -p /var/log/devops-setup

# Install AWS CLI v2
echo "Installing AWS CLI v2..." >> /var/log/user-data.log
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Terraform
echo "Installing Terraform..." >> /var/log/user-data.log
TERRAFORM_VERSION="1.6.6"
wget https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_$${TERRAFORM_VERSION}_linux_amd64.zip

# Install kubectl
echo "Installing kubectl..." >> /var/log/user-data.log
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubectl

# Install Helm
echo "Installing Helm..." >> /var/log/user-data.log
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Docker
echo "Installing Docker..." >> /var/log/user-data.log
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Install additional useful tools
echo "Installing additional tools..." >> /var/log/user-data.log

# Install eksctl (AWS EKS CLI)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin

# Install k9s (Kubernetes CLI UI)
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
wget https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/k9s_Linux_amd64.tar.gz
tar -xzf k9s_Linux_amd64.tar.gz
mv k9s /usr/local/bin/
rm k9s_Linux_amd64.tar.gz

# Install kubectx and kubens
git clone https://github.com/ahmetb/kubectx /opt/kubectx
ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Setup working directory
echo "Setting up working directory..." >> /var/log/user-data.log
mkdir -p /home/ubuntu/gogs-deployment
chown -R ubuntu:ubuntu /home/ubuntu/gogs-deployment

# Clone the repository if URL is provided
%{ if git_repo_url != "" }
echo "Cloning repository..." >> /var/log/user-data.log
su - ubuntu -c "cd /home/ubuntu/gogs-deployment && git clone ${git_repo_url} ."
%{ endif }

# Create useful aliases and environment setup
echo "Setting up environment..." >> /var/log/user-data.log
cat >> /home/ubuntu/.bashrc << 'EOF'

# Gogs DevOps Environment Setup
export KUBECONFIG=~/.kube/config
export PATH=$PATH:/usr/local/bin

# Useful aliases
alias k='kubectl'
alias tf='terraform'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Kubernetes aliases
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'

# Terraform aliases
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfs='terraform show'

# AWS aliases
alias awswho='aws sts get-caller-identity'

# Custom functions
function klog() {
    kubectl logs -f $1
}

function kexec() {
    kubectl exec -it $1 -- /bin/bash
}

function switch-kube-context() {
    kubectl config use-context $1
}

# Welcome message
echo ""
echo "🚀 Gogs DevOps Environment Ready!"
echo "📁 Working directory: ~/gogs-deployment"
echo "🔧 Tools installed: AWS CLI, Terraform, kubectl, Helm, Docker, eksctl, k9s"
echo ""
echo "Quick start:"
echo "  cd ~/gogs-deployment"
echo "  aws sts get-caller-identity  # Verify AWS access"
echo "  terraform --version          # Verify Terraform"
echo "  kubectl version --client     # Verify kubectl"
echo ""
EOF

# Set proper ownership
chown ubuntu:ubuntu /home/ubuntu/.bashrc

# Create a setup verification script
cat > /home/ubuntu/verify-setup.sh << 'EOF'
#!/bin/bash
echo "🔍 Verifying DevOps environment setup..."
echo ""

# Check AWS CLI
echo "✅ AWS CLI Version:"
aws --version
echo ""

# Check AWS credentials/permissions
echo "✅ AWS Identity:"
aws sts get-caller-identity
echo ""

# Check Terraform
echo "✅ Terraform Version:"
terraform --version
echo ""

# Check kubectl
echo "✅ kubectl Version:"
kubectl version --client
echo ""

# Check Helm
echo "✅ Helm Version:"
helm version --short
echo ""

# Check Docker
echo "✅ Docker Version:"
docker --version
echo ""

# Check eksctl
echo "✅ eksctl Version:"
eksctl version
echo ""

# Check k9s
echo "✅ k9s Version:"
k9s version
echo ""

echo "🎉 All tools are ready for Gogs deployment!"
echo ""
echo "Next steps:"
echo "1. cd ~/gogs-deployment/eks-prod"
echo "2. cp terraform.tfvars.example terraform.tfvars"
echo "3. Edit terraform.tfvars with your configuration"
echo "4. terraform init && terraform plan && terraform apply"
EOF

chmod +x /home/ubuntu/verify-setup.sh
chown ubuntu:ubuntu /home/ubuntu/verify-setup.sh

# Create SSH key directory with proper permissions
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh

# Log completion
echo "DevOps instance setup completed successfully!" >> /var/log/user-data.log
echo "Setup completed at: $(date)" >> /var/log/user-data.log

# Send completion signal
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource DevOpsInstance --region ${AWS::Region} 2>/dev/null || true

echo "🚀 Gogs DevOps Environment Setup Complete!" >> /var/log/user-data.log