output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.cert.arn
}

output "certificate_domain" {
  description = "Domain name of the certificate"
  value       = aws_acm_certificate.cert.domain_name
}
