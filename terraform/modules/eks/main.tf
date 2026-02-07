# =============================================================================
# CloudWatch Log Group for EKS (MUST be created BEFORE EKS cluster)
# EKS automatically uses this log group if it exists, otherwise creates its own
# =============================================================================
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-eks-logs"
  }
}

# =============================================================================
# EKS Cluster
# =============================================================================
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true # Enabled for WSL/local access
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # API authentication mode required for aws_eks_access_entry resources
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  # Ensure IAM role AND log group are created before cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks
  ]

  tags = {
    Name = var.cluster_name
  }
}

# =============================================================================
# EKS Add-ons (Required for Self-Managed EC2 Nodes)
# =============================================================================

# VPC CNI - Pod networking via AWS VPC
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-vpc-cni"
  }
}

# CoreDNS - DNS resolution inside cluster
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS needs worker nodes to schedule pods
  depends_on = [aws_autoscaling_group.workers]

  tags = {
    Name = "${var.project_name}-coredns"
  }
}

# kube-proxy - Service network proxy
resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = var.kube_proxy_version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${var.project_name}-kube-proxy"
  }
}

# =============================================================================
# OIDC Provider for IRSA (IAM Roles for Service Accounts)
# =============================================================================
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc-provider"
  }
}

# =============================================================================
# EKS Access Entry for Worker Nodes (allows nodes to join cluster)
# =============================================================================
resource "aws_eks_access_entry" "worker_nodes" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.worker_node.arn
  type          = "EC2_LINUX"

  depends_on = [aws_eks_cluster.main]
}

# =============================================================================
# Self-Managed EC2 Worker Nodes - Launch Template
# =============================================================================
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2/recommended/image_id"
}

resource "aws_launch_template" "workers" {
  name_prefix   = "${var.project_name}-worker-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = var.worker_instance_type

  # IAM Instance Profile for worker nodes
  iam_instance_profile {
    arn = aws_iam_instance_profile.worker_node.arn
  }

  # Network configuration
  network_interfaces {
    associate_public_ip_address = false # Private subnets only
    security_groups             = [aws_security_group.worker_nodes.id]
    delete_on_termination       = true
  }

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.worker_root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # User data script - Bootstrap node to join EKS cluster
  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cluster_name                  = aws_eks_cluster.main.name
    cluster_endpoint              = aws_eks_cluster.main.endpoint
    cluster_certificate_authority = aws_eks_cluster.main.certificate_authority[0].data
    bootstrap_extra_args          = var.bootstrap_extra_args
    kubelet_extra_args            = var.kubelet_extra_args
  }))

  # Instance metadata options (IMDSv2 required for security)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  # Enable detailed monitoring for Prometheus scraping
  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                        = "${var.project_name}-worker"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-worker-volume"
    }
  }

  tags = {
    Name = "${var.project_name}-worker-launch-template"
  }

  # Ensure cluster exists before creating launch template
  depends_on = [aws_eks_cluster.main]
}

# =============================================================================
# Self-Managed EC2 Worker Nodes - Auto Scaling Group
# =============================================================================
resource "aws_autoscaling_group" "workers" {
  name                = "${var.project_name}-workers-asg"
  desired_capacity    = var.worker_desired_capacity
  min_size            = var.worker_min_size
  max_size            = var.worker_max_size
  vpc_zone_identifier = var.private_subnet_ids

  # Use mixed instances policy for cost optimization (optional spot)
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.workers.id
        version            = "$Latest"
      }

      # Override instance types for flexibility
      dynamic "override" {
        for_each = var.worker_instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_allocation_strategy                 = "capacity-optimized"
    }
  }

  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # Tags required for Kubernetes cluster-autoscaler and Karpenter discovery
  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  # Karpenter discovery tags (for future migration)
  tag {
    key                 = "karpenter.sh/discovery"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  depends_on = [
    aws_launch_template.workers,
    aws_iam_role_policy_attachment.worker_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.worker_node_AmazonSSMManagedInstanceCore,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity] # Allow external scaling (Karpenter/CA)
  }
}

# =============================================================================
# Karpenter IAM Role (IRSA) - Prepared for future deployment
# =============================================================================
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.project_name}-karpenter-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-karpenter-controller-role"
  }
}

# Karpenter Controller Policy
resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.project_name}-karpenter-controller-policy"
  description = "IAM policy for Karpenter controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Karpenter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Sid      = "ConditionalEC2Termination"
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "PassNodeIAMRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.worker_node.arn
      },
      {
        Sid      = "EKSClusterEndpointLookup"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.main.arn
      },
      {
        Sid    = "AllowScopedInstanceProfileCreationActions"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Action   = "iam:TagInstanceProfile"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Action   = "iam:GetInstanceProfile"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-karpenter-controller-policy"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}
