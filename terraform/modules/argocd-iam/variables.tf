variable "project_name" {
  type = string
}

variable "oidc_provider" {
  type        = string
  description = "OIDC provider URL (without https://)"
}

variable "aws_region" {
  type = string
}
