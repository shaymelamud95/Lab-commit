# =============================================================================
# Route53 Private Hosted Zone for lab-commit-v1.internal
# =============================================================================
# Creates a private hosted zone in our VPC (il-central-1)
# DNS records will be added after ALB is created by Ingress
# =============================================================================

# Create Private Hosted Zone
resource "aws_route53_zone" "private" {
  name    = var.private_zone_name
  comment = "Private hosted zone for ${var.project_name} in il-central-1"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name        = "${var.project_name}-private-zone"
    Project     = var.project_name
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Internal CNAME record for RDS (db.lab-commit-v1.internal)
resource "aws_route53_record" "rds" {
  count = var.rds_endpoint != "" ? 1 : 0

  zone_id = aws_route53_zone.private.zone_id
  name    = "db"
  type    = "CNAME"
  ttl     = 300
  records = [var.rds_endpoint]
}

# =============================================================================
# ALB Lookup - Find ALB created by Ingress Controller
# =============================================================================
# The ALB is created dynamically by AWS Load Balancer Controller
# We look it up by tag to create the Route53 alias record

data "aws_lb" "ingress_alb" {
  count = var.enable_alb_lookup ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
  }
}

# Application A record pointing to ALB
resource "aws_route53_record" "app" {
  count = var.enable_alb_lookup && length(data.aws_lb.ingress_alb) > 0 ? 1 : 0

  zone_id = aws_route53_zone.private.zone_id
  name    = var.record_name # lab-commit-task
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress_alb[0].dns_name
    zone_id                = data.aws_lb.ingress_alb[0].zone_id
    evaluate_target_health = true
  }
}

