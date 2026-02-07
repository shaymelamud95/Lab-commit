terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# =============================================================================
# NOTE: Kubernetes/Helm providers NOT used here
# =============================================================================
# EKS cluster is PRIVATE-ONLY (no public endpoint) as per exam requirements.
# kubectl/helm commands must be run from Windows EC2 inside the VPC via SSM.
# See README.md for post-deployment steps.
# =============================================================================
