# IAM Role outputs (existing)
output "role_arn" {
  value = aws_iam_role.argocd_codecommit.arn
}

# IAM User + SSH outputs (new)
output "iam_user_name" {
  value = aws_iam_user.argocd_codecommit.name
}

output "ssh_user_id" {
  value = aws_iam_user_ssh_key.argocd_codecommit.ssh_public_key_id
}

output "ssh_key_secret_arn" {
  value = aws_secretsmanager_secret.argocd_ssh_key.arn
}

output "codecommit_ssh_url" {
  value = "ssh://${aws_iam_user_ssh_key.argocd_codecommit.ssh_public_key_id}@git-codecommit.${var.aws_region}.amazonaws.com/v1/repos/${var.project_name}-app"
}
