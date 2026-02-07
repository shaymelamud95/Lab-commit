# =============================================================================
# ACM Certificate for Lab-commit Application
# =============================================================================
# Since this is a private hosted zone, we create a self-signed certificate
# and import it to ACM

# Generate private key
resource "tls_private_key" "cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate
resource "tls_self_signed_cert" "cert" {
  private_key_pem = tls_private_key.cert.private_key_pem

  subject {
    common_name  = "lab-commit-task.${var.domain_name}"
    organization = "Lab-Commit"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    "lab-commit-task.${var.domain_name}",
    "*.${var.domain_name}",
    var.domain_name
  ]
}

# Import certificate to ACM
resource "aws_acm_certificate" "cert" {
  private_key      = tls_private_key.cert.private_key_pem
  certificate_body = tls_self_signed_cert.cert.cert_pem

  tags = {
    Name        = "${var.project_name}-certificate"
    Domain      = var.domain_name
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}
