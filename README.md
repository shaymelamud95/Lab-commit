# Lab-Commit - AWS EKS Infrastructure

Production-grade AWS infrastructure with EKS 1.30, Fargate, ArgoCD, and full CI/CD pipeline.

## Architecture Overview

- **VPC**: Custom VPC with 2 private subnets (no NAT/IGW)
- **EKS 1.30**: Fargate profiles (no node groups)
- **Load Balancer**: AWS ALB with ACM SSL termination
- **CD Tool**: ArgoCD for GitOps deployments
- **Monitoring**: Prometheus + Grafana (no CloudWatch agent)
- **Database**: RDS MySQL in private subnet
- **Access**: Windows EC2 via SSM (no key-pairs)
- **IaC**: 100% Terraform managed
- **State**: S3 backend with DynamoDB locking

---

## Prerequisites

- AWS CLI v2.32+ configured
- Terraform v1.14+
- kubectl v1.30+
- Helm v3.0+
- Git

---

## Quick Start

### Step 1: AWS Configuration

```bash
# Configure AWS CLI
aws configure --profile lab-commit
export AWS_PROFILE=lab-commit

# Verify connection
aws sts get-caller-identity
Step 2: Delete Default VPC
Run the automated script to delete the default VPC (required for lab).

bash
cd scripts
./delete-default-vpc.sh --force
Why?

Lab requires clean custom VPC only

Default VPC has public subnets (violates requirements)

Prevents accidental deployment in wrong VPC

Step 3: Setup Terraform Backend
Run the automated script to create S3 bucket and DynamoDB table.

bash
cd scripts
./setup-terraform-backend.sh
What it configures:

S3 Bucket: State storage with versioning enabled

Encryption: AES256 at rest for secrets protection

Public Block: Defense in depth against exposure

DynamoDB Table: State locking to prevent corruption

Step 4: Deploy Infrastructure
bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan
Project Structure
text
Lab-commit/
├── scripts/
│   ├── delete-default-vpc.sh        # Automated default VPC deletion
│   └── setup-terraform-backend.sh   # Automated backend setup
├── terraform/
│   ├── modules/
│   │   ├── vpc/           # VPC with 2 private subnets + VPC endpoints
│   │   ├── eks/           # EKS 1.30 (Fargate only)
│   │   ├── rds/           # MySQL (private)
│   │   ├── alb/           # ALB + ACM
│   │   ├── ec2/           # Windows (SSM)
│   │   └── route53/       # DNS
│   ├── backend.tf         # S3 + DynamoDB backend config
│   ├── provider.tf        # AWS provider
│   ├── main.tf            # Module orchestration
│   ├── variables.tf       # Input variables
│   ├── terraform.tfvars   # Variable values
│   └── outputs.tf         # Outputs
├── helm/
│   ├── frontend/          # Custom app Helm chart
│   ├── argocd/            # ArgoCD CD tool
│   └── monitoring/        # Prometheus + Grafana
└── app/
    ├── frontend/          # Application code
    └── backend/           # Backend service
Security Features
✅ No default VPC - custom VPC only
✅ No public subnets - private network only
✅ No NAT/IGW - VPC endpoints for AWS services
✅ No SSH keys - SSM Session Manager only
✅ No CloudWatch agent - Prometheus/Grafana
✅ Encrypted state - AES256 at rest
✅ State locking - DynamoDB prevents corruption
✅ SSL/TLS - ACM certificates on ALB
✅ Private RDS - not internet-accessible

Deployment Progress
 AWS CLI configuration

 Default VPC deletion

 S3 + DynamoDB backend

 VPC module (2 private subnets)

 EKS 1.30 (Fargate)

 ALB + ACM

 ArgoCD

 App + Helm chart

 RDS MySQL

 Windows EC2 + SSM

 Prometheus + Grafana

 Route53 DNS

 CodePipeline CI/CD

Manual Commands Reference
Connect to Windows Instance (SSM)
bash
INSTANCE_ID=$(terraform output -raw windows_instance_id)
aws ssm start-session --target ${INSTANCE_ID}
Access Kubernetes Cluster
bash
aws eks update-kubeconfig --name lab-commit-cluster --region il-central-1
kubectl get nodes
kubectl get pods -A
Troubleshooting
Terraform State Locked

bash
# View lock
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"tfstate-lab-commit-923337630273/lab-commit/terraform.tfstate"}}'

# Force unlock (caution!)
terraform force-unlock <lock-id>
Reset Infrastructure

bash
cd terraform
terraform destroy -auto-approve
Author
Candidate05
Account: 923337630273
Region: il-central-1
Repository: https://github.com/shaymelamud95/Lab-commit
