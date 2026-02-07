output "zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "zone_name" {
  description = "Route53 private hosted zone name"
  value       = aws_route53_zone.private.name
}

output "zone_arn" {
  description = "Route53 private hosted zone ARN"
  value       = aws_route53_zone.private.arn
}

output "name_servers" {
  description = "Name servers for the private hosted zone"
  value       = aws_route53_zone.private.name_servers
}

output "rds_fqdn" {
  description = "Fully qualified domain name for RDS"
  value       = var.rds_endpoint != "" ? aws_route53_record.rds[0].fqdn : null
}

output "app_fqdn" {
  description = "Fully qualified domain name for the application"
  value       = var.enable_alb_lookup && length(aws_route53_record.app) > 0 ? aws_route53_record.app[0].fqdn : null
}

output "alb_dns_name" {
  description = "ALB DNS name (if lookup enabled)"
  value       = var.enable_alb_lookup && length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].dns_name : null
}
