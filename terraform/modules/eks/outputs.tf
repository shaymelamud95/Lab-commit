# =============================================================================
# EKS Cluster Outputs
# =============================================================================
output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

# =============================================================================
# OIDC Provider Outputs
# =============================================================================
output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# =============================================================================
# IAM Role Outputs
# =============================================================================
output "cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "worker_node_role_arn" {
  description = "Worker node IAM role ARN"
  value       = aws_iam_role.worker_node.arn
}

output "worker_node_instance_profile_arn" {
  description = "Worker node IAM instance profile ARN"
  value       = aws_iam_instance_profile.worker_node.arn
}

output "alb_controller_role_arn" {
  description = "ALB Controller IAM role ARN (for IRSA)"
  value       = aws_iam_role.alb_controller.arn
}

output "karpenter_controller_role_arn" {
  description = "Karpenter Controller IAM role ARN (for IRSA)"
  value       = aws_iam_role.karpenter_controller.arn
}

# =============================================================================
# Security Group Outputs
# =============================================================================
output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_security_group.eks_cluster.id
}

output "worker_nodes_security_group_id" {
  description = "Worker nodes security group ID"
  value       = aws_security_group.worker_nodes.id
}

# =============================================================================
# Self-Managed Worker Node Outputs
# =============================================================================
output "worker_asg_name" {
  description = "Auto Scaling Group name for worker nodes"
  value       = aws_autoscaling_group.workers.name
}

output "worker_asg_arn" {
  description = "Auto Scaling Group ARN for worker nodes"
  value       = aws_autoscaling_group.workers.arn
}

output "worker_launch_template_id" {
  description = "Launch template ID for worker nodes"
  value       = aws_launch_template.workers.id
}

output "worker_launch_template_latest_version" {
  description = "Latest version of the worker launch template"
  value       = aws_launch_template.workers.latest_version
}
