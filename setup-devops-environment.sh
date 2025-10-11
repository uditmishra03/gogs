#!/bin/bash

# Gogs DevOps Environment Setup Script
# Run this script on your Ubuntu 22.04 LTS EC2 instance to install all prerequisites
# Usage: ./setup-devops-environment.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as ubuntu user."
   exit 1
fi

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    error "This script is designed for Ubuntu. Detected: $(cat /etc/os-release | grep PRETTY_NAME)"
    exit 1
fi

log "🚀 Starting Gogs DevOps Environment Setup..."
info "This script will install: AWS CLI, Terraform, kubectl, Helm, Docker, eksctl, k9s, and other tools"

# Create log directory
sudo mkdir -p /var/log/devops-setup
LOG_FILE="/var/log/devops-setup/setup-$(date +%Y%m%d-%H%M%S).log"
sudo touch $LOG_FILE
sudo chown ubuntu:ubuntu $LOG_FILE

# Redirect all output to log file as well
exec > >(tee -a $LOG_FILE)
exec 2>&1

log "Starting system update..."

# Update system
log "Updating package lists..."
sudo apt-get update -y

log "Upgrading system packages..."
sudo apt-get upgrade -y

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Install basic packages
log "Installing basic packages..."
sudo apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    jq \
    vim \
    htop \
    tree \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential \
    python3-pip

# Install AWS CLI v2
log "Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    log "✅ AWS CLI v2 installed successfully"
else
    info "AWS CLI already installed: $(aws --version)"
fi

# Install Terraform
log "Installing Terraform..."
if ! command -v terraform &> /dev/null; then
    TERRAFORM_VERSION="1.6.6"
    cd /tmp
    wget "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    sudo mv terraform /usr/local/bin/
    rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
    log "✅ Terraform installed successfully"
else
    info "Terraform already installed: $(terraform --version | head -n1)"
fi

# Install kubectl
log "Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    # Add Kubernetes APT repository
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    sudo apt-get install -y kubectl
    log "✅ kubectl installed successfully"
else
    info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || echo 'kubectl installed')"
fi

# Install Helm
log "Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log "✅ Helm installed successfully"
else
    info "Helm already installed: $(helm version --short)"
fi

# Install Docker
log "Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add user to docker group
    sudo usermod -aG docker ubuntu
    
    log "✅ Docker installed successfully"
    warn "You need to log out and log back in for Docker group membership to take effect"
else
    info "Docker already installed: $(docker --version)"
fi

# Install eksctl
log "Installing eksctl..."
if ! command -v eksctl &> /dev/null; then
    cd /tmp
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    log "✅ eksctl installed successfully"
else
    info "eksctl already installed: $(eksctl version)"
fi

# Install k9s
log "Installing k9s..."
if ! command -v k9s &> /dev/null; then
    cd /tmp
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    wget "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
    tar -xzf k9s_Linux_amd64.tar.gz
    sudo mv k9s /usr/local/bin/
    rm k9s_Linux_amd64.tar.gz
    log "✅ k9s installed successfully"
else
    info "k9s already installed: $(k9s version -s)"
fi

# Install kubectx and kubens
log "Installing kubectx and kubens..."
if [ ! -d "/opt/kubectx" ]; then
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
    sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
    log "✅ kubectx and kubens installed successfully"
else
    info "kubectx and kubens already installed"
fi

# Setup working directory
log "Setting up working directory..."
mkdir -p /home/ubuntu/gogs-deployment
cd /home/ubuntu/gogs-deployment

# Clone the Gogs repository
log "Cloning Gogs repository..."
if [ ! -d "/home/ubuntu/gogs-deployment/.git" ]; then
    git clone https://github.com/uditmishra03/gogs.git .
    log "✅ Repository cloned successfully"
else
    info "Repository already exists, pulling latest changes..."
    git pull origin main || warn "Failed to pull latest changes"
fi

# Create useful aliases and environment setup
log "Setting up environment aliases and functions..."
cat >> /home/ubuntu/.bashrc << 'EOF'

# ============================================
# Gogs DevOps Environment Setup
# ============================================
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
alias kgi='kubectl get ingress'
alias kgns='kubectl get namespaces'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdd='kubectl describe deployment'

# Terraform aliases
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfs='terraform show'
alias tfv='terraform validate'
alias tff='terraform fmt'

# AWS aliases
alias awswho='aws sts get-caller-identity'
alias awsregion='aws configure get region'

# Docker aliases
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dlog='docker logs'

# Custom functions
function klog() {
    if [ -z "$1" ]; then
        echo "Usage: klog <pod-name> [namespace]"
        return 1
    fi
    if [ -n "$2" ]; then
        kubectl logs -f "$1" -n "$2"
    else
        kubectl logs -f "$1"
    fi
}

function kexec() {
    if [ -z "$1" ]; then
        echo "Usage: kexec <pod-name> [namespace]"
        return 1
    fi
    if [ -n "$2" ]; then
        kubectl exec -it "$1" -n "$2" -- /bin/bash
    else
        kubectl exec -it "$1" -- /bin/bash
    fi
}

function kport() {
    if [ -z "$2" ]; then
        echo "Usage: kport <local-port> <service-name:service-port> [namespace]"
        return 1
    fi
    if [ -n "$3" ]; then
        kubectl port-forward "svc/$2" "$1" -n "$3"
    else
        kubectl port-forward "svc/$2" "$1"
    fi
}

function switch-kube-context() {
    if [ -z "$1" ]; then
        kubectl config get-contexts
    else
        kubectl config use-context "$1"
    fi
}

function tf-workspace() {
    if [ -z "$1" ]; then
        terraform workspace list
    else
        terraform workspace select "$1" 2>/dev/null || terraform workspace new "$1"
    fi
}

# Welcome message function
function gogs-welcome() {
    echo ""
    echo "🚀 Gogs DevOps Environment Ready!"
    echo "📁 Working directory: ~/gogs-deployment"
    echo "🔧 Tools installed: AWS CLI, Terraform, kubectl, Helm, Docker, eksctl, k9s"
    echo ""
    echo "Quick commands:"
    echo "  awswho                       # Check AWS identity"
    echo "  k get nodes                  # List Kubernetes nodes"
    echo "  tf-workspace <name>          # Switch/create Terraform workspace"
    echo "  klog <pod>                   # Follow pod logs"
    echo "  kexec <pod>                  # Execute into pod"
    echo ""
    echo "Useful directories:"
    echo "  ~/gogs-deployment/eks-prod   # Main EKS infrastructure"
    echo "  ~/gogs-deployment/helm-chart # Gogs Helm chart"
    echo ""
}

# Auto-run welcome message on login
if [ -f ~/.gogs-setup-complete ]; then
    gogs-welcome
fi
EOF

# Create verification script
log "Creating verification script..."
cat > /home/ubuntu/verify-setup.sh << 'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Verifying Gogs DevOps Environment Setup..."
echo "=============================================="
echo ""

# Function to check command
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "✅ ${GREEN}$1${NC}: $($1 $2 2>/dev/null | head -n1)"
    else
        echo -e "❌ ${RED}$1 not found${NC}"
    fi
}

# Check all tools
check_command "aws" "--version"
check_command "terraform" "--version"
check_command "kubectl" "version --client --short"
check_command "helm" "version --short"
check_command "docker" "--version"
check_command "eksctl" "version"
check_command "k9s" "version -s"
check_command "kubectx" "--help | head -n1"
check_command "kubens" "--help | head -n1"

echo ""
echo "🔐 AWS Configuration:"
if aws sts get-caller-identity &> /dev/null; then
    echo -e "✅ ${GREEN}AWS credentials configured${NC}"
    aws sts get-caller-identity --output table
else
    echo -e "❌ ${RED}AWS credentials not configured${NC}"
    echo "Run: aws configure"
fi

echo ""
echo "🐳 Docker Status:"
if docker ps &> /dev/null; then
    echo -e "✅ ${GREEN}Docker is running and accessible${NC}"
else
    echo -e "⚠️  ${YELLOW}Docker not accessible (may need to log out/in for group membership)${NC}"
fi

echo ""
echo "📁 Repository Status:"
if [ -d "/home/ubuntu/gogs-deployment/.git" ]; then
    cd /home/ubuntu/gogs-deployment
    echo -e "✅ ${GREEN}Repository cloned${NC}"
    echo "Branch: $(git branch --show-current)"
    echo "Last commit: $(git log -1 --oneline)"
else
    echo -e "❌ ${RED}Repository not found${NC}"
fi

echo ""
echo "🎉 Setup verification complete!"
echo ""
echo "Next steps:"
echo "1. Configure AWS credentials: aws configure"
echo "2. Navigate to: cd ~/gogs-deployment/eks-prod"
echo "3. Copy and edit: cp terraform.tfvars.example terraform.tfvars"
echo "4. Deploy infrastructure: terraform init && terraform plan && terraform apply"
echo ""
EOF

chmod +x /home/ubuntu/verify-setup.sh

# Create SSH key directory with proper permissions
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Create setup completion marker
touch /home/ubuntu/.gogs-setup-complete

# Final verification
log "Running final verification..."
/home/ubuntu/verify-setup.sh

log "🎉 Gogs DevOps Environment Setup Complete!"
echo ""
echo "=============================================="
echo "📋 IMPORTANT NEXT STEPS:"
echo "=============================================="
echo ""
echo "1. 🔄 RESTART YOUR SESSION (to apply Docker group membership):"
echo "   exit"
echo "   ssh -i your-key.pem ubuntu@your-instance-ip"
echo ""
echo "2. 🔐 CONFIGURE AWS CREDENTIALS:"
echo "   aws configure"
echo "   # Enter your AWS Access Key ID, Secret Access Key, and region"
echo ""
echo "3. ✅ VERIFY EVERYTHING WORKS:"
echo "   ./verify-setup.sh"
echo ""
echo "4. 🚀 START DEPLOYING GOGS:"
echo "   cd ~/gogs-deployment/eks-prod"
echo "   cp terraform.tfvars.example terraform.tfvars"
echo "   # Edit terraform.tfvars with your specific values"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "=============================================="
echo "📝 Log file saved to: $LOG_FILE"
echo "🔧 Run 'gogs-welcome' anytime to see helpful commands"
echo "=============================================="