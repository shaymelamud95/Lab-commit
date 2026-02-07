# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = "${var.project_name}-cluster"
}

# EKS Module (Self-Managed EC2 Worker Nodes)
module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  aws_region         = var.aws_region
  account_id         = data.aws_caller_identity.current.account_id
  cluster_name       = "${var.project_name}-cluster"
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  # Self-Managed EC2 Worker Node Configuration
  worker_instance_type    = var.worker_instance_type
  worker_instance_types   = var.worker_instance_types
  worker_desired_capacity = var.worker_desired_capacity
  worker_min_size         = var.worker_min_size
  worker_max_size         = var.worker_max_size
  worker_root_volume_size = var.worker_root_volume_size
  on_demand_base_capacity = var.on_demand_base_capacity
  on_demand_percentage    = var.on_demand_percentage

  alb_security_group_id = var.enable_alb_lookup && length(data.aws_lb.ingress_alb) > 0 ? tolist(data.aws_lb.ingress_alb[0].security_groups)[0] : ""
  depends_on            = [module.vpc]
}

# =============================================================================
# ALB Lookup - Find the ALB created by Kubernetes Ingress Controller
# =============================================================================
# This data source locates the AWS Application Load Balancer (ALB) created by the
# AWS Load Balancer Controller in EKS, using the cluster tag. Used for Route53
# alias record and for security group rules to allow ALB access to worker nodes.
data "aws_lb" "ingress_alb" {
  count = var.enable_alb_lookup ? 1 : 0
  tags = {
    "elbv2.k8s.aws/cluster" = "${var.project_name}-cluster"
  }
}

# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# =============================================================================
# Windows EC2 Module (for accessing private EKS cluster)
# =============================================================================
module "ec2" {
  source = "./modules/ec2"

  project_name            = var.project_name
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  subnet_id               = module.vpc.private_subnet_ids[0] # First private subnet
  cluster_name            = module.eks.cluster_name
  alb_controller_role_arn = module.eks.alb_controller_role_arn
  instance_type           = var.windows_instance_type
  root_volume_size        = var.windows_root_volume_size

  depends_on = [module.eks]
}

# =============================================================================
# RDS Module (MySQL database for backend)
# =============================================================================
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # Allow access from EKS worker nodes and Windows EC2
  allowed_security_group_ids = [
    module.eks.worker_nodes_security_group_id,
    module.ec2.security_group_id
  ]

  # Database configuration
  db_engine            = var.db_engine
  db_engine_version    = var.db_engine_version
  db_instance_class    = var.db_instance_class
  db_name              = var.db_name
  db_allocated_storage = var.db_allocated_storage

  depends_on = [module.vpc, module.eks, module.ec2]
}

# =============================================================================
# Route53 Private Hosted Zone (lab-commit-v1.internal)
# =============================================================================
module "route53" {
  source = "./modules/route53"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  private_zone_name = "lab-commit-v1.internal"
  record_name       = "lab-commit-task"

  # RDS internal CNAME (db.lab-commit-v1.internal)
  rds_endpoint = module.rds.db_instance_address

  # ALB lookup - set enable_alb_lookup=true after Helm deploys Ingress
  enable_alb_lookup = var.enable_alb_lookup
  cluster_name      = "${var.project_name}-cluster"

  depends_on = [module.vpc, module.rds]
}

# =============================================================================
# ECR Repositories (for Docker images)
# =============================================================================
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

# =============================================================================
# ACM Certificate (for HTTPS)
# =============================================================================
module "acm" {
  source = "./modules/acm"

  project_name = var.project_name
  domain_name  = "lab-commit-v1.internal"
}


#==============================================================================
# CI/CD Module (CodeCommit + CodePipeline)
#==============================================================================
module "cicd" {
  source = "./modules/cicd"

  project_name = var.project_name
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id

  ecr_frontend_repository_name = module.ecr.frontend_repository_name
  ecr_backend_repository_name  = module.ecr.backend_repository_name

  depends_on = [module.ecr]
}