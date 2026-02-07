variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the certificate"
  type        = string
  default     = "lab-commit-v1.internal"
}
