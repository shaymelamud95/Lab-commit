variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the Windows EC2 instance"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for kubectl configuration"
  type        = string
}

variable "alb_controller_role_arn" {
  description = "IAM role ARN for ALB controller (IRSA)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Windows"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}
