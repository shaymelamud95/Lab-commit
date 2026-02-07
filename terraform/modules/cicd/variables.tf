variable "project_name" {
  description = "Project name used for resource naming"
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

variable "ecr_frontend_repository_name" {
  description = "ECR repository name for frontend"
  type        = string
}

variable "ecr_backend_repository_name" {
  description = "ECR repository name for backend"
  type        = string
}
