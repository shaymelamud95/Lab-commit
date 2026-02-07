# Lab-Commit Copilot Instructions

## ⚠️ CRITICAL: SHARED AWS ACCOUNT - READ FIRST ⚠️

**This AWS account (923337630273) is shared by MULTIPLE teams and users.**

### ABSOLUTE RULES - NEVER VIOLATE:

1. **NEVER DELETE RESOURCES NOT IN TERRAFORM STATE**
   - If `terraform apply` fails with "EntityAlreadyExists" or "ResourceAlreadyExists", **DO NOT delete the existing resource**
   - That resource likely belongs to another team/user
   - Instead: Change YOUR resource name to be unique

2. **NEVER RUN DESTRUCTIVE AWS CLI COMMANDS** like:
   ```bash
   # FORBIDDEN - These can delete other people's resources!
   aws iam delete-role --role-name <any-role>
   aws iam delete-policy --policy-arn <any-policy>
   aws iam delete-instance-profile --instance-profile-name <any-profile>
   aws ec2 delete-* 
   ```

3. **ALWAYS USE UNIQUE PREFIXES** - Every resource MUST include `${var.project_name}` which defaults to `lab-commit-v1`
   - If conflicts occur, increment version: `lab-commit-v2`, `lab-commit-v3`, etc.
   - Check for existing resources BEFORE creating: `aws iam list-roles --query "Roles[?contains(RoleName, 'lab-commit-v1')]"`

4. **ONLY DESTROY WHAT YOU CREATED**
   - Only use `terraform destroy` - never manual AWS CLI deletions
   - Terraform state tracks what WE created; only those resources should be touched

### What To Do If Resource Name Conflicts:
```bash
# 1. Check if resource exists
aws iam get-role --role-name lab-commit-v1-eks-cluster-role 2>/dev/null && echo "EXISTS" || echo "AVAILABLE"

# 2. If EXISTS, increment YOUR version number in terraform.tfvars:
project_name = "lab-commit-v2"  # Changed from v1 to v2

# 3. Re-run terraform plan/apply with new unique names
```

### Incident History (DO NOT REPEAT):
- **Date**: Previous deployment
- **Error**: `Role with name lab-commit-eks-cluster-role already exists`
- **WRONG action taken**: Deleted 7 IAM roles that belonged to OTHER users
- **Impact**: Broke other teams' infrastructure
- **Correct action**: Should have changed our prefix from `lab-commit` to `lab-commit-v1`

---

## Role & Context

You are a **Senior DevOps Engineer** working on **AWS Lab 8 – EKS Services & Pipeline**.

- **Region**: `il-central-1` (Israel Central)
- **Account**: 923337630273
- **Project Path**: `~/projects/Lab-commit/`
- **Philosophy**: 100% Infrastructure as Code - **NO UI clicks, all Terraform**

## Architecture Overview

This is a **fully private AWS EKS infrastructure** with zero public network exposure:
- **VPC**: Custom VPC (`10.0.0.0/16`) with 2 private subnets only - **NO NAT Gateway, NO Internet Gateway**
- **EKS 1.30**: EC2 with autoscaling (no node groups) with private API endpoint
- **Connectivity**: VPC Endpoints for all AWS service communication (S3, ECR, SSM, EKS, STS, ELB, CloudWatch)
- **Access**: Windows EC2 2019/2022 via SSM Session Manager only (no SSH keys)
- **State**: S3 backend (`tfstate-lab-commit-923337630273`) with DynamoDB locking, AES256 encrypted
- **Load Balancer**: AWS ALB with SSL termination using ACM certificate
- **Database**: RDS MySQL/PostgreSQL in private subnet
- **DNS**: Route53 record `lab-commit-task.<hosted-zone>`
- **Monitoring**: Prometheus + Grafana (CloudWatch Agent NOT allowed)
- **GitOps**: ArgoCD for continuous deployment
- **CI/CD**: CodePipeline with CodeCommit repository

## Project Conventions

### Terraform Structure
- **Root module**: `terraform/` orchestrates all child modules via `main.tf`
- **Reusable modules**: `terraform/modules/{vpc,eks,rds,alb,ec2,route53}/` - each has `main.tf`, `variables.tf`, `outputs.tf`
- **Naming convention**: All resources use `${var.project_name}-<resource>` pattern (e.g., `lab-commit-v1-vpc`)
- **Version tracking**: `project_name` includes version suffix (e.g., `lab-commit-v1`, `lab-commit-v2`) to track deployment generations
- **Default region**: `il-central-1` (Israel) with AZs `il-central-1a`, `il-central-1b`

### Tagging Strategy
All resources require these tags (enforced via `default_tags` in provider):
```hcl
Project     = var.project_name   # "lab-commit-v1"
Environment = var.environment    # "dev"
ManagedBy   = "Terraform"
```
EKS subnets require additional Kubernetes tags:
```hcl
"kubernetes.io/role/internal-elb"           = "1"
"kubernetes.io/cluster/${var.cluster_name}" = "shared"
```

## Critical Terraform Requirements

### MUST WORK ON FIRST APPLY
This is a job interview test - Terraform must work **cleanly on first `terraform apply`**:
- **NO manual imports** - All resources must be created fresh
- **NO orphaned resources** - Use `terraform destroy` to clean up before re-testing
- **Dependency ordering** - Resources that AWS auto-creates must be created FIRST by Terraform:
  - CloudWatch Log Group `/aws/eks/{cluster}/cluster` MUST be created BEFORE EKS cluster
  - EKS uses existing log group instead of creating its own (avoiding ResourceAlreadyExistsException)

### Resource Naming Convention
All resources use `${var.project_name}` prefix (default: `lab-commit-v1`):
- Cluster: `lab-commit-v1-cluster`
- IAM roles: `lab-commit-v1-eks-cluster-role`, `lab-commit-v1-worker-node-role`
- Security groups: `lab-commit-v1-eks-cluster-sg`, `lab-commit-v1-worker-nodes-sg`

## Critical Workflows

### Initial Setup (run in order)
```bash
# 1. Configure AWS CLI
aws configure --profile lab-commit && export AWS_PROFILE=lab-commit

# 2. Delete default VPC (required - lab constraint)
./scripts/delete-default-vpc.sh --force

# 3. Create S3/DynamoDB backend
./scripts/setup-terraform-backend.sh

# 4. Deploy infrastructure
cd terraform && terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

### Terraform Commands (always run from `terraform/` directory)
```bash
terraform fmt -recursive    # Format all .tf files
terraform validate          # Syntax check before planning
terraform plan -out=tfplan  # Always save plan to file
terraform apply tfplan      # Apply saved plan only
```

### Access Windows EC2 Instance
```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw windows_instance_id)

# Connect via SSM Session Manager (no SSH keys)
aws ssm start-session --target ${INSTANCE_ID}
```

### Configure kubectl for EKS
```bash
# IMPORTANT: These commands must be run from Windows EC2 inside the VPC!
# EKS is private-only - no public API endpoint

# Update kubeconfig for private EKS cluster
aws eks update-kubeconfig --name lab-commit-v1-cluster --region il-central-1

# Verify connection
kubectl get nodes
kubectl get pods -A
```

## Private-Only Architecture (CRITICAL)

The EKS cluster has **NO public API endpoint** as per exam requirements:
- `endpoint_public_access = false`
- `endpoint_private_access = true`

### What this means:
1. **Terraform** - Can only create AWS resources (VPC, EKS, RDS, EC2, IAM, etc.)
2. **kubectl/helm** - Must be run FROM Windows EC2 inside the VPC via SSM
3. **No Helm/Kubernetes Terraform providers** - Can't reach private API from local machine

### Deployment Workflow:
1. `terraform apply` - Creates all AWS infrastructure
2. Connect to Windows EC2 via SSM Session Manager
3. Install kubectl, helm, AWS CLI on Windows EC2
4. Run kubectl/helm commands from Windows EC2 (see README.md)

### Post-Terraform Steps (run from Windows EC2):
```powershell
# Install AWS CLI, kubectl, helm on Windows (one-time setup)
# Then deploy ALB Controller, ArgoCD, Prometheus, etc.
# See README.md for detailed commands
```

## Lab Assignment Requirements

### Application Stack
- **Frontend**: Helm3 chart displaying `"Hello Lab-commit <version>"` where version comes from backend
- **Backend**: Service that queries RDS MySQL/PostgreSQL and returns version number
- **Communication**: Frontend polls backend every X seconds for updated value
- **Exposure**: HTTPS only via Route53 + ACM, accessible only from Windows EC2 (no public internet)
- **URL**: `https://lab-commit-task.<your-hosted-zone>`

### Infrastructure Components (ALL via Terraform)
1. Custom VPC with 2 private subnets (delete default VPC first)
2. EKS 1.30 cluster (EC2 with autoscaling - no node groups)
3. ALB Controller with SSL termination (ACM certificate)
4. RDS MySQL/PostgreSQL in private subnet
5. Windows EC2 2019/2022 with SSM access (no key-pairs)
6. Route53 DNS record for application
7. ArgoCD (or Octopus/Bamboo) for GitOps CD
8. Prometheus + Grafana for monitoring (exposed to Windows EC2)
9. CodeCommit repository + CodePipeline for CI/CD

### Security & Networking
- Security groups with minimal required ports
- No public internet exposure for services
- SSL termination at ALB layer
- Private DNS resolution via Route53 private hosted zone

## Key Constraints (DO NOT VIOLATE)

1. **SHARED ACCOUNT** - NEVER delete resources not in our Terraform state (see warning at top)
2. **Unique naming** - ALL resources MUST use `${var.project_name}` prefix (e.g., `lab-commit-v1-*`)
3. **No public subnets** - All subnets must be private with no route to IGW
4. **No NAT Gateway** - Use VPC Endpoints for AWS service access instead
5. **No SSH key pairs** - Use SSM Session Manager for EC2 access
6. **No CloudWatch Agent** - Use Prometheus + Grafana for monitoring
7. **EC2 with autoscaling** - No Fargate profiles or node groups in EKS cluster
8. **Backend bucket naming**: `tfstate-lab-commit-<account-id>` format required
9. **No UI clicks** - All infrastructure must be Terraform code
10. **Delete default VPC** - Required before creating custom VPC (only YOUR default VPC)

## VPC Endpoints Pattern

When adding new AWS service dependencies, create VPC endpoints following `terraform/modules/vpc/main.tf`:
```hcl
resource "aws_vpc_endpoint" "<service>" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.<service>"
  vpc_endpoint_type   = "Interface"  # or "Gateway" for S3/DynamoDB
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
```

## Helm Charts Location

- `helm/frontend/` - Application Helm chart
- `helm/argocd/` - ArgoCD GitOps configuration
- `helm/monitoring/` - Prometheus + Grafana stack

## Deployment Progress Checklist

- [ ] AWS CLI configuration & default VPC deletion
- [ ] S3 + DynamoDB backend setup
- [ ] VPC module (2 private subnets + VPC endpoints)
- [ ] EKS 1.30 cluster (EC2 with autoscaling - no node groups)
- [ ] ALB Controller + ACM certificate
- [ ] RDS MySQL/PostgreSQL in private subnet
- [ ] Windows EC2 2019/2022 with SSM access
- [ ] Route53 DNS record (`lab-commit-task.<zone>`)
- [ ] Frontend + Backend application with Helm charts
- [ ] ArgoCD GitOps deployment
- [ ] Prometheus + Grafana monitoring stack
- [ ] CodeCommit repository setup
- [ ] CodePipeline CI/CD for frontend updates
