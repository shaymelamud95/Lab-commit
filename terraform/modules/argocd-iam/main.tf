# IAM Role for ArgoCD to access CodeCommit
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "argocd_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.oidc_provider}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:argocd:argocd-repo-server"]
    }
  }
}

resource "aws_iam_role" "argocd_codecommit" {
  name               = "${var.project_name}-argocd-codecommit"
  assume_role_policy = data.aws_iam_policy_document.argocd_assume_role.json

  tags = {
    Name = "${var.project_name}-argocd-codecommit-role"
  }
}

resource "aws_iam_role_policy_attachment" "argocd_codecommit_readonly" {
  role       = aws_iam_role.argocd_codecommit.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitReadOnly"
}

# ============================================================================
# IAM User for ArgoCD CodeCommit SSH Access
# ============================================================================

resource "aws_iam_user" "argocd_codecommit" {
  name = "${var.project_name}-argocd-codecommit-user"

  tags = {
    Name = "${var.project_name}-argocd-codecommit-user"
  }
}

resource "aws_iam_user_policy_attachment" "argocd_codecommit_user_readonly" {
  user       = aws_iam_user.argocd_codecommit.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitReadOnly"
}

# Generate SSH key pair
resource "tls_private_key" "argocd_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload public key to IAM
resource "aws_iam_user_ssh_key" "argocd_codecommit" {
  username   = aws_iam_user.argocd_codecommit.name
  encoding   = "SSH"
  public_key = tls_private_key.argocd_ssh.public_key_openssh
}

# Store private key in Secrets Manager
resource "aws_secretsmanager_secret" "argocd_ssh_key" {
  name                    = "${var.project_name}-argocd-ssh-key"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-argocd-ssh-key"
  }
}

resource "aws_secretsmanager_secret_version" "argocd_ssh_key" {
  secret_id     = aws_secretsmanager_secret.argocd_ssh_key.id
  secret_string = tls_private_key.argocd_ssh.private_key_pem
}
