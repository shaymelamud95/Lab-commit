variable "aws_region" {
  type    = string
  default = "il-central-1"
}

variable "project_name" {
  type    = string
  default = "lab-commit"
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
