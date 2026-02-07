# Lab-Commit EKS Project - Terraform Modules Tasks

> **Region**: `il-central-1` | **Account**: `923337630273` | **EKS**: `1.30` | **Self-Managed EC2 + Karpenter**

## ✅ Phase 1: Infrastructure Foundation (COMPLETED)

- [x] Terraform Backend (S3 + DynamoDB)
  - Bucket: `tfstate-lab-commit-923337630273`
  - Table: `terraform-state-lock`
- [x] VPC Module
  - [x] VPC: `10.0.0.0/16` (vpc-017976ad561b95d9e)
  - [x] Private Subnets: `10.0.1.0/24` (il-central-1a), `10.0.2.0/24` (il-central-1b)
  - [x] 11 VPC Endpoints (S3, ECR API/DKR, EC2, SSM/SSMMessages/EC2Messages, EKS, STS, Logs, ELB)
  - [x] Security group for endpoints (HTTPS 443 from VPC CIDR)
  - [x] Route tables (NO internet routes - verified)
  - [x] **NO NAT Gateway** ✓
  - [x] **NO Internet Gateway** ✓

---

## 🚧 Phase 2: Terraform Modules (IN PROGRESS)

### Task 1: EKS Module (`modules/eks/`)

#### 1.1 Directory Structure
```
modules/eks/
├── main.tf          # EKS cluster, Launch Template, ASG, Karpenter IRSA
├── iam.tf           # IAM roles (cluster, worker nodes, Karpenter)
├── security.tf      # Security groups (cluster, worker nodes)
├── variables.tf     # Input variables (including worker node config)
├── outputs.tf       # Module outputs
└── templates/
    └── userdata.sh.tpl  # Bootstrap script to join nodes to cluster
```

#### 1.2 IAM Roles (Complete Definitions)

**EKS Cluster Role:**
```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"  # lab-commit-v1-eks-cluster-role
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# Attach these managed policies:
# - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

**Worker Node IAM Role:**
```hcl
resource "aws_iam_role" "worker_node" {
  name = "${var.project_name}-worker-node-role"  # lab-commit-v1-worker-node-role
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach these managed policies:
# - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
# - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
# - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
# - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

**ALB Controller Role (IRSA):**
```hcl
resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-alb-controller-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Create custom policy from: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json
# Save as: alb_controller_policy.json
```

#### 1.3 EKS Cluster Configuration
```hcl
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = "1.30"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false  # CRITICAL: Must be false
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}
```

#### 1.4 OIDC Provider (Required for IRSA)
```hcl
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

#### 1.5 Self-Managed EC2 Worker Nodes

**Launch Template:**
```hcl
resource "aws_launch_template" "workers" {
  name_prefix   = "${var.project_name}-worker-"
  image_id      = data.aws_ssm_parameter.eks_ami.value  # EKS optimized AMI
  instance_type = var.worker_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.worker_node.arn
  }

  network_interfaces {
    associate_public_ip_address = false  # Private subnets only
    security_groups             = [aws_security_group.worker_nodes.id]
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cluster_name                  = aws_eks_cluster.main.name
    cluster_endpoint              = aws_eks_cluster.main.endpoint
    cluster_certificate_authority = aws_eks_cluster.main.certificate_authority[0].data
  }))
}
```

**Auto Scaling Group:**
```hcl
resource "aws_autoscaling_group" "workers" {
  name                = "${var.project_name}-workers-asg"
  desired_capacity    = var.worker_desired_capacity  # Default: 2
  min_size            = var.worker_min_size          # Default: 1
  max_size            = var.worker_max_size          # Default: 10
  vpc_zone_identifier = var.private_subnet_ids

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.workers.id
        version            = "$Latest"
      }
    }
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "karpenter.sh/discovery"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}
```

#### 1.6 Security Groups
**Cluster Security Group:**
| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Ingress | TCP | 443 | VPC CIDR (10.0.0.0/16) | API Server access |
| Ingress | TCP | 443 | Worker Nodes SG | Worker to API |
| Egress | All | All | 0.0.0.0/0 | Outbound (via VPC endpoints) |

**Worker Nodes Security Group:**
| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Ingress | TCP | 1025-65535 | VPC CIDR | Control plane to workers |
| Ingress | All | All | Self | Pod-to-pod networking |
| Ingress | TCP | 10250 | VPC CIDR | Kubelet API (Prometheus) |
| Ingress | TCP | 9100 | VPC CIDR | Node Exporter (Prometheus) |
| Ingress | TCP | 30000-32767 | VPC CIDR | NodePort services |
| Egress | All | All | 0.0.0.0/0 | Outbound (via VPC endpoints) |

#### 1.7 Karpenter Setup (Post-Apply)
After infrastructure is deployed, install Karpenter for intelligent autoscaling:
```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_ROLE_ARN} \
  --set settings.clusterName=${CLUSTER_NAME} \
  --set settings.clusterEndpoint=${CLUSTER_ENDPOINT}
```

#### 1.8 Required Outputs
```hcl
output "cluster_name" { value = aws_eks_cluster.main.name }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_arn" { value = aws_eks_cluster.main.arn }
output "cluster_certificate_authority" { value = aws_eks_cluster.main.certificate_authority[0].data }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.eks.arn }
output "worker_node_role_arn" { value = aws_iam_role.worker_node.arn }
output "worker_asg_name" { value = aws_autoscaling_group.workers.name }
output "karpenter_controller_role_arn" { value = aws_iam_role.karpenter_controller.arn }
output "alb_controller_role_arn" { value = aws_iam_role.alb_controller.arn }
output "cluster_security_group_id" { value = aws_security_group.eks_cluster.id }
output "worker_nodes_security_group_id" { value = aws_security_group.worker_nodes.id }
```

#### 1.9 Validation
```bash
cd ~/projects/Lab-commit/terraform
terraform validate
terraform plan -out=tfplan

# Verify these constraints:
grep -A5 "endpoint_public_access" tfplan | grep "false"  # Must be false
grep "aws_autoscaling_group.workers" tfplan && echo "OK: Self-managed nodes" || echo "ERROR"

terraform apply tfplan

# Post-apply verification:
kubectl get nodes  # Should show worker nodes
aws eks describe-cluster --name lab-commit-cluster --region il-central-1 \
  --query 'cluster.resourcesVpcConfig.endpointPublicAccess'
# Expected: false
```

---

### Task 2: RDS Module (`modules/rds/`)

#### 2.1 Directory Structure
```
modules/rds/
├── main.tf          # RDS instance, subnet group
├── security.tf      # Security group
├── secrets.tf       # Secrets Manager
├── variables.tf
└── outputs.tf
```

#### 2.2 Configuration Specifications
| Setting | Value | Reason |
|---------|-------|--------|
| Engine | `mysql` | Lab requirement |
| Engine Version | `8.0.35` | Latest stable |
| Instance Class | `db.t3.micro` | Cost-effective for dev |
| Storage | `20` GB, `gp3` | Minimum required |
| Multi-AZ | `false` | Dev environment |
| Publicly Accessible | `false` | **CRITICAL** |
| Database Name | `labcommit` | Application DB |
| Port | `3306` | MySQL default |
| Backup Retention | `7` days | Recovery capability |
| Delete Protection | `false` | Allow terraform destroy |

#### 2.3 Security Group Rules
| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Ingress | TCP | 3306 | VPC CIDR (10.0.0.0/16) | MySQL from EKS pods |
| Egress | None | - | - | No outbound needed |

#### 2.4 Secrets Manager
```hcl
resource "random_password" "rds_password" {
  length  = 16
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name = "${var.project_name}-rds-credentials"
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.rds_password.result
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = "labcommit"
  })
}
```

#### 2.5 Required Outputs
```hcl
output "db_endpoint" { value = aws_db_instance.main.address }
output "db_port" { value = aws_db_instance.main.port }
output "db_name" { value = aws_db_instance.main.db_name }
output "db_security_group_id" { value = aws_security_group.rds.id }
output "secret_arn" { value = aws_secretsmanager_secret.rds_credentials.arn }
output "db_instance_id" { value = aws_db_instance.main.id }
```

#### 2.6 Validation
```bash
terraform plan -out=tfplan

# Verify public access is disabled:
terraform show tfplan | grep "publicly_accessible" | grep "false"

terraform apply tfplan

# Verify:
aws rds describe-db-instances --db-instance-identifier lab-commit-rds \
  --query 'DBInstances[0].PubliclyAccessible' --region il-central-1
# Expected: false
```

---

### Task 3: EC2 Windows Module (`modules/ec2/`)

#### 3.1 Directory Structure
```
modules/ec2/
├── main.tf          # EC2 instance
├── iam.tf           # IAM role, instance profile
├── security.tf      # Security group
├── variables.tf
└── outputs.tf
```

#### 3.2 Windows AMI Data Source
```hcl
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
```

#### 3.3 IAM Role for SSM
```hcl
resource "aws_iam_role" "windows_ssm" {
  name = "${var.project_name}-windows-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach these managed policies:
# - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
# - arn:aws:iam::aws:policy/AmazonSSMPatchAssociation
```

#### 3.4 EC2 Configuration
| Setting | Value | Reason |
|---------|-------|--------|
| Instance Type | `t3.medium` | Windows minimum |
| AMI | Windows Server 2022 | Lab requirement |
| Subnet | Private subnet 1 | No public access |
| Key Pair | **NONE** | SSM access only |
| Root Volume | 50 GB, gp3 | Windows requirement |
| Monitoring | `true` | Enhanced monitoring |

#### 3.5 Security Group Rules
| Rule | Type | Port | Source/Dest | Purpose |
|------|------|------|-------------|---------|
| Egress | TCP | 443 | 0.0.0.0/0 | HTTPS (SSM, app access) |
| Egress | TCP | 3306 | RDS SG | MySQL access |
| Egress | TCP | 80 | VPC CIDR | HTTP (internal) |

> ⚠️ **NO key_name argument** - SSM Session Manager only!

#### 3.6 Required Outputs
```hcl
output "instance_id" { value = aws_instance.windows.id }
output "private_ip" { value = aws_instance.windows.private_ip }
output "security_group_id" { value = aws_security_group.windows.id }
output "iam_role_arn" { value = aws_iam_role.windows_ssm.arn }
```

#### 3.7 Validation
```bash
terraform plan -out=tfplan

# Verify NO key pair:
terraform show tfplan | grep "key_name" && echo "ERROR: Remove key_name!" || echo "OK: No key pair"

terraform apply tfplan

# Test SSM connectivity:
INSTANCE_ID=$(terraform output -raw windows_instance_id)
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=${INSTANCE_ID}" --region il-central-1
# Expected: PingStatus = "Online"

# Connect:
aws ssm start-session --target ${INSTANCE_ID} --region il-central-1
```

---

### Task 4: Route53 Module (`modules/route53/`)

#### 4.1 Configuration
| Setting | Value | Purpose |
|---------|-------|---------|
| Zone Type | **Private** | Internal access only |
| Zone Name | Input variable | e.g., `lab-commit.internal` |
| VPC Association | Main VPC | DNS resolution in VPC |
| Record Name | `lab-commit-task` | Application endpoint |
| Record Type | A (Alias) | Points to ALB |

#### 4.2 Required Outputs
```hcl
output "zone_id" { value = aws_route53_zone.private.zone_id }
output "zone_name" { value = aws_route53_zone.private.name }
output "app_fqdn" { value = "${var.record_name}.${aws_route53_zone.private.name}" }
# ALB record output added after ALB is created
```

> **Note**: A-record for ALB will be added in Phase 3 after ALB Controller deploys the load balancer.

---

### Task 5: ACM + ALB Prep Module (`modules/alb/`)

#### 5.1 What Terraform Creates vs Kubernetes
| Component | Created By | When |
|-----------|------------|------|
| ACM Certificate | Terraform | Phase 2 |
| ALB Security Group | Terraform | Phase 2 |
| ALB Controller IAM Role | Terraform (EKS module) | Phase 2 |
| Actual ALB | Kubernetes Ingress | Phase 3 |
| Target Groups | ALB Controller | Phase 3 |

#### 5.2 ACM Certificate (Self-Signed Alternative)
Since the lab mentions self-signed, and ACM requires validation:
```hcl
# Option 1: ACM with DNS validation (if you have a public hosted zone)
resource "aws_acm_certificate" "app" {
  domain_name       = "lab-commit-task.${var.domain_name}"
  validation_method = "DNS"
}

# Option 2: For private-only, use self-signed via Kubernetes secret (Phase 3)
```

#### 5.3 ALB Security Group
| Rule | Type | Port | Source | Purpose |
|------|------|------|--------|---------|
| Ingress | TCP | 443 | VPC CIDR | HTTPS from Windows EC2 |
| Ingress | TCP | 80 | VPC CIDR | HTTP redirect |
| Egress | TCP | 8080 | VPC CIDR | To application pods |

#### 5.4 Required Outputs
```hcl
output "certificate_arn" { value = aws_acm_certificate.app.arn }  # If using ACM
output "alb_security_group_id" { value = aws_security_group.alb.id }
```

---

## 📋 Execution Order (STRICT)

```
1. ✅ VPC Module (DONE)
   └── vpc_id, subnet_ids, endpoint_sg_id

2. ⏭️ EKS Module (NEXT)
   ├── Depends on: VPC outputs
   └── Outputs: cluster_name, oidc_arn, alb_role_arn

3. ⏭️ RDS Module
   ├── Depends on: VPC outputs
   └── Outputs: db_endpoint, secret_arn

4. ⏭️ EC2 Windows Module
   ├── Depends on: VPC outputs
   └── Outputs: instance_id

5. ⏭️ Route53 Module
   ├── Depends on: VPC outputs
   └── Outputs: zone_id, fqdn

6. ⏭️ ALB Prep Module
   ├── Depends on: VPC outputs
   └── Outputs: alb_sg_id, cert_arn (if ACM)
```

---

## ⚠️ Pre-Apply Checklist

Before `terraform apply`, verify:

| Check | Command | Expected |
|-------|---------|----------|
| No NAT Gateway | `grep "aws_nat_gateway" *.tf` | No matches |
| No Internet Gateway | `grep "aws_internet_gateway" *.tf` | No matches |
| No Node Groups | `grep "aws_eks_node_group" *.tf` | No matches |
| EKS Private Only | Check `endpoint_public_access` | `false` |
| RDS Private | Check `publicly_accessible` | `false` |
| EC2 No Key | Check for `key_name` | Not present |
| Region | All resources | `il-central-1` |

---

## 📊 Progress Tracking

| Module | Status | Outputs Verified | Notes |
|--------|--------|------------------|-------|
| VPC | ✅ COMPLETE | ✅ | 11 endpoints created |
| EKS | ⬜ PENDING | - | Start here |
| RDS | ⬜ PENDING | - | After EKS |
| EC2 | ⬜ PENDING | - | After RDS |
| Route53 | ⬜ PENDING | - | After EC2 |
| ALB Prep | ⬜ PENDING | - | Last in Phase 2 |

---

## 🎯 Phase 3: Post-Terraform (DO NOT START UNTIL PHASE 2 COMPLETE)

| Task | Tool | Namespace | Depends On |
|------|------|-----------|------------|
| Deploy ALB Controller | Helm | kube-system | IRSA role |
| Deploy Karpenter | Helm | karpenter | IRSA role, worker nodes |
| Deploy ArgoCD | Helm | argocd | Worker nodes |
| Deploy Prometheus | Helm | monitoring | Worker nodes |
| Deploy Grafana | Helm | monitoring | Prometheus |
| Build App Image | Docker | - | ECR repo |
| Deploy Backend | Helm/ArgoCD | application | RDS, image |
| Deploy Frontend | Helm/ArgoCD | application | Backend |
| Create Ingress | kubectl | application | ALB Controller |
| Update Route53 | Terraform | - | ALB DNS |
| Setup CodeCommit | AWS CLI | - | - |
| Create CodePipeline | Terraform | - | CodeCommit |
| End-to-end Test | SSM + Chrome | - | All above |

---

## 📝 Git Workflow

```bash
# After each module completion:
git add terraform/modules/<module>/
git commit -m "feat(terraform): add <module> module"
git tag v0.X-<module>
git push origin main --tags
```

| Version | Module | Status |
|---------|--------|--------|
| v0.1-vpc | VPC | ✅ Tagged |
| v0.2-eks | EKS | ⬜ Pending |
| v0.3-rds | RDS | ⬜ Pending |
| v0.4-ec2 | EC2 | ⬜ Pending |
| v0.5-route53 | Route53 | ⬜ Pending |
| v0.6-alb | ALB Prep | ⬜ Pending |
