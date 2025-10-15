data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "./modules/vpc"
  region  = var.region
  cluster_name = var.cluster_name
}

module "iam" {
  source        = "./modules/iam"
  cluster_name  = var.cluster_name
}

module "eks" {
  source          = "./modules/eks"
  cluster_name    = var.cluster_name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  node_role_arn   = module.iam.node_role_arn
  region          = var.region
}

# Optional: grant cluster admin access via EKS Access Entry if admin_principal_arn provided
resource "aws_eks_access_entry" "admin" {
  count         = length(var.admin_principal_arn) > 0 ? 1 : 0
  cluster_name  = var.cluster_name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_cluster" {
  count        = length(var.admin_principal_arn) > 0 ? 1 : 0
  cluster_name = var.cluster_name
  principal_arn = var.admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.admin]
}

