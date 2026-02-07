output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# =============================================================================
# EKS Outputs
# =============================================================================
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "eks_alb_controller_role_arn" {
  description = "ALB Controller IAM role ARN"
  value       = module.eks.alb_controller_role_arn
}

output "eks_cluster_certificate_authority" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# =============================================================================
# Self-Managed Worker Node Outputs
# =============================================================================
output "worker_node_role_arn" {
  description = "Worker node IAM role ARN"
  value       = module.eks.worker_node_role_arn
}

output "worker_asg_name" {
  description = "Worker nodes Auto Scaling Group name"
  value       = module.eks.worker_asg_name
}

output "worker_nodes_security_group_id" {
  description = "Worker nodes security group ID"
  value       = module.eks.worker_nodes_security_group_id
}

output "karpenter_controller_role_arn" {
  description = "Karpenter Controller IAM role ARN (for future use)"
  value       = module.eks.karpenter_controller_role_arn
}

# =============================================================================
# Windows EC2 Outputs
# =============================================================================
output "windows_instance_id" {
  description = "Windows EC2 instance ID"
  value       = module.ec2.instance_id
}

output "windows_private_ip" {
  description = "Windows EC2 private IP"
  value       = module.ec2.instance_private_ip
}

output "windows_ssm_command" {
  description = "Command to connect to Windows EC2 via SSM"
  value       = module.ec2.ssm_connect_command
}

# =============================================================================
# RDS Outputs
# =============================================================================
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "RDS instance address (hostname only)"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

output "rds_secret_arn" {
  description = "ARN of Secrets Manager secret with DB credentials"
  value       = module.rds.db_secret_arn
}

# =============================================================================
# Route53 Outputs
# =============================================================================
output "route53_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = module.route53.zone_id
}

output "route53_zone_name" {
  description = "Route53 private hosted zone name"
  value       = module.route53.zone_name
}

output "route53_rds_fqdn" {
  description = "RDS internal FQDN (db.lab-commit-v1.internal)"
  value       = module.route53.rds_fqdn
}

# =============================================================================
# ECR Outputs
# =============================================================================
output "ecr_backend_repository_url" {
  description = "Backend ECR repository URL"
  value       = module.ecr.backend_repository_url
}

output "ecr_frontend_repository_url" {
  description = "Frontend ECR repository URL"
  value       = module.ecr.frontend_repository_url
}

output "ecr_registry_id" {
  description = "ECR Registry ID"
  value       = module.ecr.registry_id
}

# =============================================================================
# ACM Outputs
# =============================================================================
output "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  value       = module.acm.certificate_arn
}

output "acm_certificate_domain" {
  description = "ACM certificate domain"
  value       = module.acm.certificate_domain
}

#==============================================================================
# CI/CD Outputs
#==============================================================================
output "codecommit_repository_url" {
  description = "CodeCommit repository clone URL (HTTPS)"
  value       = module.cicd.codecommit_repository_url
}

output "codepipeline_name" {
  description = "CodePipeline name"
  value       = module.cicd.codepipeline_name
}

output "codepipeline_url" {
  description = "CodePipeline console URL"
  value       = module.cicd.codepipeline_url
}

output "argocd_role_arn" {
  description = "IAM role ARN for ArgoCD to access CodeCommit"
  value       = module.argocd_iam.role_arn
}


# ArgoCD IAM outputs
output "argocd_ssh_user_id" {
  description = "SSH User ID for ArgoCD CodeCommit access"
  value       = module.argocd_iam.ssh_user_id
}

output "argocd_ssh_key_secret_arn" {
  description = "Secrets Manager ARN for ArgoCD SSH private key"
  value       = module.argocd_iam.ssh_key_secret_arn
}

output "argocd_codecommit_ssh_url" {
  description = "CodeCommit SSH URL for ArgoCD"
  value       = module.argocd_iam.codecommit_ssh_url
}
