variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block for NAT Gateway"
  type        = string
  default     = "10.0.100.0/24"
}

variable "cluster_name" {
  description = "EKS cluster name for subnet tagging"
  type        = string
}
