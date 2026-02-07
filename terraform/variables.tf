variable "aws_region" {
  type    = string
  default = "il-central-1"
}

variable "project_name" {
  description = "Project name prefix for all resources. Use format 'lab-commit-vX' for version tracking."
  type        = string
  default     = "lab-commit-v1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["il-central-1a", "il-central-1b"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

# =============================================================================
# Self-Managed EC2 Worker Node Variables
# =============================================================================
variable "worker_instance_type" {
  description = "Default EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_types" {
  description = "List of instance types for mixed instances policy"
  type        = list(string)
  default     = ["t3.small", "t3.medium", "t3a.small", "t3a.medium"]
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
  description = "Maximum number of worker nodes"
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
  description = "Percentage of on-demand instances above base capacity"
  type        = number
  default     = 50
}

# =============================================================================
# Windows EC2 Variables
# =============================================================================
variable "windows_instance_type" {
  description = "EC2 instance type for Windows bastion"
  type        = string
  default     = "t3.medium"
}

variable "windows_root_volume_size" {
  description = "Root volume size in GB for Windows EC2"
  type        = number
  default     = 50
}

# =============================================================================
# RDS Variables
# =============================================================================
variable "db_engine" {
  description = "Database engine (mysql or postgres)"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "labcommit"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

# =============================================================================
# Route53 ALB Lookup
# =============================================================================
variable "enable_alb_lookup" {
  description = "Enable ALB lookup for Route53 record (set to true after Helm deploys Ingress)"
  type        = bool
  default     = false
}
