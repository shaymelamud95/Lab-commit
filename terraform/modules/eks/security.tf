# =============================================================================
# EKS Cluster Security Group
# =============================================================================
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  # Ingress: Allow HTTPS (443) from VPC CIDR for API server access
  ingress {
    description = "HTTPS from VPC for kubectl and internal services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress: Allow communication from worker nodes
  ingress {
    description     = "Allow worker nodes to communicate with cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.worker_nodes.id]
  }

  # Egress: Allow all outbound (via VPC endpoints)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

# =============================================================================
# Self-Managed EC2 Worker Nodes Security Group
# =============================================================================
resource "aws_security_group" "worker_nodes" {
  name        = "${var.project_name}-worker-nodes-sg"
  description = "Security group for EKS self-managed worker nodes"
  vpc_id      = var.vpc_id

  # Ingress: Allow all traffic from control plane
  ingress {
    description = "Allow cluster control plane to communicate with worker nodes"
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress: Allow worker-to-worker communication (pod networking)
  ingress {
    description = "Allow worker nodes to communicate with each other"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Ingress: Allow kubelet API from VPC (for metrics scraping by Prometheus)
  ingress {
    description = "Kubelet API for Prometheus metrics scraping"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress: Node Exporter port for Prometheus
  ingress {
    description = "Node Exporter for Prometheus"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress: Allow NodePort services range
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress: CoreDNS
  ingress {
    description = "CoreDNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "CoreDNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress: Allow all outbound (via VPC endpoints)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                        = "${var.project_name}-worker-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# =============================================================================
# Security Group Rule: ALB to Worker Nodes (for Ingress on port 80)
# =============================================================================
resource "aws_security_group_rule" "alb_to_workers_80" {
  count = var.alb_security_group_id != "" ? 1 : 0

  description              = "Allow ALB to access worker nodes on port 80 (frontend pods)"
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  security_group_id        = aws_security_group.worker_nodes.id
}


# =============================================================================
# Security Group Rule: Cluster to Worker Nodes (added separately to avoid cycle)
# =============================================================================
resource "aws_security_group_rule" "cluster_to_workers" {
  description              = "Allow cluster control plane to communicate with worker kubelet"
  type                     = "egress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
}
