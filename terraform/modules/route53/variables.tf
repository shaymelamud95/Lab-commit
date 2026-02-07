variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for private hosted zone"
  type        = string
}

variable "private_zone_name" {
  description = "Name for the private hosted zone"
  type        = string
  default     = "lab-commit-v1.internal"
}

variable "record_name" {
  description = "DNS record name for main application (e.g., lab-commit-task)"
  type        = string
  default     = "lab-commit-task"
}

# RDS endpoint (without port)
variable "rds_endpoint" {
  description = "RDS endpoint for internal CNAME record (without port)"
  type        = string
  default     = ""
}

# ALB Lookup configuration
variable "enable_alb_lookup" {
  description = "Enable ALB lookup by tags (set to true after Helm deploys Ingress)"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "EKS cluster name for ALB tag lookup"
  type        = string
  default     = ""
}
