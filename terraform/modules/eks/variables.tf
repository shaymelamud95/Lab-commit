variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB for ingress to worker nodes"
  type        = string
}

variable "enabled_cluster_log_types" {
  description = "List of cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# =============================================================================
# EKS Add-on Versions (use 'aws eks describe-addon-versions' to find latest)
# =============================================================================
variable "vpc_cni_version" {
  description = "VPC CNI add-on version"
  type        = string
  default     = "v1.21.1-eksbuild.3"
}

variable "coredns_version" {
  description = "CoreDNS add-on version"
  type        = string
  default     = "v1.11.4-eksbuild.28"
}

variable "kube_proxy_version" {
  description = "kube-proxy add-on version"
  type        = string
  default     = "v1.30.14-eksbuild.20"
}

# =============================================================================
# Self-Managed EC2 Worker Node Variables
# =============================================================================
variable "worker_instance_type" {
  description = "Default EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_types" {
  description = "List of instance types for mixed instances policy (cost optimization)"
  type        = list(string)
  default     = ["t3.medium", "t3.large", "t3a.medium", "t3a.large"]
}

variable "worker_desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "worker_max_size" {
  description = "Maximum number of worker nodes (Karpenter will manage scaling)"
  type        = number
  default     = 10
}

variable "worker_root_volume_size" {
  description = "Root volume size in GB for worker nodes"
  type        = number
  default     = 50
}

variable "on_demand_base_capacity" {
  description = "Number of on-demand instances as base capacity"
  type        = number
  default     = 1
}

variable "on_demand_percentage" {
  description = "Percentage of on-demand instances above base capacity (0-100)"
  type        = number
  default     = 50
}

variable "bootstrap_extra_args" {
  description = "Extra arguments for EKS bootstrap script"
  type        = string
  default     = ""
}

variable "kubelet_extra_args" {
  description = "Extra arguments for kubelet"
  type        = string
  default     = "--max-pods=110"
}
