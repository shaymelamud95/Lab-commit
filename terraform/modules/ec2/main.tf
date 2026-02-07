# =============================================================================
# Windows EC2 Instance for accessing Private EKS Cluster
# =============================================================================
# This Windows instance is used to:
# 1. Access the private EKS cluster (kubectl, helm)
# 2. Install ALB Controller, ArgoCD, Prometheus via Helm
# 3. Browse the application via Chrome
# Access via SSM Session Manager (no SSH key-pair as per exam requirements)
# =============================================================================

# Get latest Windows Server 2022 AMI
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# =============================================================================
# IAM Role for Windows EC2 (SSM access + EKS access)
# =============================================================================
resource "aws_iam_role" "windows_ssm" {
  name = "${var.project_name}-windows-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-windows-ssm-role"
  }
}

# SSM Managed Instance Core - Required for SSM Session Manager
resource "aws_iam_role_policy_attachment" "windows_ssm_core" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EKS Describe Cluster - Required for aws eks update-kubeconfig
resource "aws_iam_role_policy_attachment" "windows_eks_readonly" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Custom policy for EKS access and ECR pull (for helm charts)
resource "aws_iam_policy" "windows_eks_access" {
  name        = "${var.project_name}-windows-eks-access-policy"
  description = "Allow Windows EC2 to access EKS cluster and ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "STSGetToken"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3EKSAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::amazon-eks",
          "arn:aws:s3:::amazon-eks/*"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-windows-eks-access-policy"
  }
}

resource "aws_iam_role_policy_attachment" "windows_eks_access" {
  role       = aws_iam_role.windows_ssm.name
  policy_arn = aws_iam_policy.windows_eks_access.arn
}

# Instance Profile
resource "aws_iam_instance_profile" "windows_ssm" {
  name = "${var.project_name}-windows-ssm-profile"
  role = aws_iam_role.windows_ssm.name

  tags = {
    Name = "${var.project_name}-windows-ssm-profile"
  }
}

# =============================================================================
# Security Group for Windows EC2
# =============================================================================
resource "aws_security_group" "windows" {
  name        = "${var.project_name}-windows-sg"
  description = "Security group for Windows EC2 instance"
  vpc_id      = var.vpc_id

  # Egress: Allow all outbound (needed for SSM, AWS APIs, EKS API)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # No ingress rules needed - access via SSM only (no SSH/RDP from internet)

  tags = {
    Name = "${var.project_name}-windows-sg"
  }
}

# =============================================================================
# Windows EC2 Instance
# =============================================================================
resource "aws_instance" "windows" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.windows_ssm.name
  vpc_security_group_ids = [aws_security_group.windows.id]

  # No key pair - access via SSM only (exam requirement)
  key_name = null

  # Root volume
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-windows-root"
    }
  }

  # User data - Private VPC bootstrap (no internet access)
  # AWS CLI & PowerShell module are PRE-INSTALLED on Windows Server 2022 AMI
  # kubectl is downloaded from Amazon's public EKS S3 bucket via VPC endpoint
  user_data = base64encode(<<-EOF
    <powershell>
    # =============================================================================
    # Windows EC2 Bootstrap Script - Private VPC (No NAT Gateway)
    # =============================================================================
    # - AWS CLI v2: Pre-installed on Amazon Windows Server 2022 AMI
    # - AWS PowerShell: Pre-installed (Read-S3Object cmdlet)
    # - kubectl: Downloaded from amazon-eks S3 bucket via S3 VPC endpoint

    $ErrorActionPreference = "Continue"
    Start-Transcript -Path "C:\tools-install.log" -Append

    Write-Host "=== Windows EC2 Bootstrap - Private VPC ==="
    Write-Host "Date: $(Get-Date)"
    
    # Download and install Google Chrome (silent)
    Write-Host "Installing Google Chrome..."
    Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile "$env:TEMP\chrome_installer.exe"
    Start-Process "$env:TEMP\chrome_installer.exe" -ArgumentList "/silent /install" -Wait
    Remove-Item "$env:TEMP\chrome_installer.exe"
    Write-Host "Google Chrome installed."

    # Create tools directory and add to PATH
    Write-Host "Creating tools directory..."
    New-Item -ItemType Directory -Force -Path "C:\tools"
    $currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*C:\tools*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;C:\tools", [EnvironmentVariableTarget]::Machine)
    }
    $env:Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)

    # Verify AWS CLI is pre-installed
    Write-Host "Checking AWS CLI..."
    $awsVersion = & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "AWS CLI already installed: $awsVersion"
    } else {
        Write-Host "WARNING: AWS CLI not found at expected path"
    }

    # Download kubectl from Amazon EKS public S3 bucket
    # This bucket is publicly accessible via S3 VPC endpoint
    Write-Host "Downloading kubectl from Amazon EKS S3 bucket..."
    $kubectlVersion = "1.30.0"
    $kubectlDate = "2024-05-12"
    try {
        Read-S3Object -BucketName "amazon-eks" -Key "$kubectlVersion/$kubectlDate/bin/windows/amd64/kubectl.exe" -File "C:\tools\kubectl.exe" -Region "us-west-2"
        Write-Host "kubectl downloaded successfully"
    } catch {
        Write-Host "ERROR downloading kubectl: $_"
        # Fallback: try copy from another region
        try {
            Copy-S3Object -BucketName "amazon-eks" -Key "$kubectlVersion/$kubectlDate/bin/windows/amd64/kubectl.exe" -LocalFile "C:\tools\kubectl.exe" -Region "us-east-1"
            Write-Host "kubectl downloaded from us-east-1"
        } catch {
            Write-Host "FAILED to download kubectl: $_"
        }
    }

    # Refresh PATH
    $env:Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)

    # Create setup script for EKS access
    @"
# Run this after connecting via SSM to configure kubectl
`$env:Path = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region}
kubectl get nodes
"@ | Out-File -FilePath "C:\tools\setup-eks.ps1" -Encoding UTF8

    Write-Host ""
    Write-Host "=== Bootstrap Complete ==="
    Write-Host "Tools installed:"
    Write-Host "  - AWS CLI: Pre-installed at C:\Program Files\Amazon\AWSCLIV2\"
    Write-Host "  - kubectl: C:\tools\kubectl.exe"
    Write-Host ""
    Write-Host "Next: Run C:\tools\setup-eks.ps1 to configure kubectl"
    
    Stop-Transcript
    </powershell>
    EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 required
    http_put_response_hop_limit = 2
  }

  tags = {
    Name = "${var.project_name}-windows"
  }

  # Prevent replacement when AMI updates - only replace manually when needed
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ami]
  }
}

# =============================================================================
# EKS Access Entry for Windows EC2 Role
# =============================================================================
# This allows the Windows EC2 instance to access the EKS cluster
resource "aws_eks_access_entry" "windows" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.windows_ssm.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "windows_admin" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.windows_ssm.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.windows]
}
