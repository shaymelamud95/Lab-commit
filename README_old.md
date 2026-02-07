# Lab-Commit - AWS EKS Infrastructure

Production-grade AWS infrastructure with EKS 1.30, Self-Managed EC2 Worker Nodes, Prometheus/Grafana monitoring, ArgoCD GitOps, and a full-stack application deployed via Helm.

## Architecture Overview

- **VPC**: Custom VPC (`10.0.0.0/16`) with 2 private subnets + NAT Gateway
- **EKS 1.30**: Self-Managed EC2 Worker Nodes with Auto Scaling Group
- **Monitoring**: Prometheus + Grafana (kube-prometheus-stack)
- **Load Balancer**: Internal AWS ALB with ACM SSL termination
- **GitOps**: ArgoCD for continuous deployment
- **Database**: RDS MySQL in private subnet
- **Access**: Windows EC2 via SSM Session Manager (no SSH keys)
- **DNS**: Route53 Private Hosted Zone (`lab-commit-v1.internal`)
- **IaC**: 100% Terraform managed
- **State**: S3 backend with DynamoDB locking

## Application Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                    Windows EC2 (SSM Access)                      │
│                         ↓ (Browser)                              │
├─────────────────────────────────────────────────────────────────┤
│              Internal ALB (HTTPS:443 → HTTP:80)                  │
│                    lab-commit-task.lab-commit-v1.internal        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Kubernetes (EKS)                        │   │
│  │  ┌─────────────┐         ┌─────────────┐                  │   │
│  │  │  Frontend   │ ──/api→ │   Backend   │                  │   │
│  │  │  (nginx)    │         │  (Python)   │                  │   │
│  │  │  Port 80    │         │  Port 8080  │                  │   │
│  │  └─────────────┘         └──────┬──────┘                  │   │
│  │                                  │                          │   │
│  │                          ┌──────▼──────┐                   │   │
│  │                          │  RDS MySQL  │                   │   │
│  │                          │  Port 3306  │                   │   │
│  │                          └─────────────┘                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Application Features
- **Frontend**: HTML/CSS/JS displaying "Hello Lab-commit \<version\>"
- **Backend**: Python Flask API querying RDS for version number
- **Polling**: Frontend polls backend every 5 seconds for live updates
- **HTTPS**: SSL termination at ALB with self-signed ACM certificate

---

## Prerequisites

- AWS CLI v2.32+ configured
- Terraform v1.14+
- kubectl v1.30+
- Helm v3.0+
- Docker (for building images)
- Git

---

## Quick Start - Complete Deployment Guide

### Phase 1: Infrastructure Setup

#### Step 1: AWS Configuration

```bash
# Configure AWS CLI
aws configure --profile lab-commit
export AWS_PROFILE=lab-commit

# Verify connection
aws sts get-caller-identity
```

#### Step 2: Delete Default VPC

```bash
cd scripts
./delete-default-vpc.sh --force
```

> **Why?** Lab requires clean custom VPC only. Default VPC has public subnets which violates requirements.

#### Step 3: Setup Terraform Backend

```bash
cd scripts
./setup-terraform-backend.sh
```

Creates:
- **S3 Bucket**: `tfstate-lab-commit-923337630273` (state storage with versioning)
- **DynamoDB Table**: `terraform-state-lock` (state locking)

#### Step 4: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

**Resources Created:**
- VPC with 2 private subnets + NAT Gateway
- EKS cluster with 2 worker nodes
- RDS MySQL database
- Windows EC2 instance (SSM access)
- Route53 Private Hosted Zone
- ECR repositories for Docker images
- ACM certificate (self-signed for internal domain)

---

### Phase 2: Kubernetes Components Installation

#### Step 5: Configure kubectl

```bash
aws eks update-kubeconfig --name lab-commit-v1-cluster --region il-central-1
kubectl get nodes
```

#### Step 6: Install AWS Load Balancer Controller

```bash
# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install ALB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=lab-commit-v1-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw eks_alb_controller_role_arn)

# Verify
kubectl get pods -n kube-system | grep aws-load-balancer
```

#### Step 7: Install Prometheus + Grafana

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword="$(openssl rand -base64 32)"

# Verify
kubectl get pods -n monitoring
```

**Access Grafana** (from local machine):
```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# Open http://localhost:3000
# User: admin, Password: (from installation output)
```

#### Step 8: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --namespace argocd

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Verify
kubectl get pods -n argocd
```

**Access ArgoCD** (from local machine):
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Open https://localhost:8080
# User: admin, Password: (from command above)
```

---

### Phase 3: Application Deployment

#### Step 9: Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region il-central-1 | docker login --username AWS --password-stdin 923337630273.dkr.ecr.il-central-1.amazonaws.com

# Build Backend
cd app/backend
docker build -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:latest .
docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend:latest

# Build Frontend
cd ../frontend
docker build -t 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:latest .
docker push 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend:latest
```

#### Step 10: Deploy Application with Helm

```bash
# Create namespace
kubectl create namespace lab-commit

# Get RDS password from Secrets Manager
RDS_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "lab-commit-v1-db-password" \
  --region il-central-1 \
  --query 'SecretString' --output text | jq -r '.password')

# Deploy Backend
helm upgrade --install backend ./helm/backend \
  --namespace lab-commit \
  --set database.password="${RDS_PASSWORD}" \
  --set replicaCount=1

# Deploy Frontend (with Ingress for ALB)
helm upgrade --install frontend ./helm/frontend \
  --namespace lab-commit \
  --set replicaCount=1

# Verify
kubectl get pods,svc,ingress -n lab-commit
```

#### Step 11: Create Route53 Record (after ALB is created)

```bash
# Enable ALB lookup and create Route53 record
cd terraform
terraform apply -var="enable_alb_lookup=true"
```

This creates an A record: `lab-commit-task.lab-commit-v1.internal` → ALB

---

### Phase 4: Testing the Application

#### Step 12: Connect to Windows EC2 via SSM

```bash
# Get Windows instance ID
INSTANCE_ID=$(terraform output -raw windows_instance_id)

# Connect via SSM Session Manager
aws ssm start-session --target ${INSTANCE_ID}
```

#### Step 13: Test Application from Windows EC2

**Option A: PowerShell Command Line**
```powershell
# Test Frontend via ALB (HTTP)
Invoke-WebRequest -Uri http://internal-k8s-labcommi-frontend-d96276f890-497072400.il-central-1.elb.amazonaws.com -UseBasicParsing

# Test Frontend via DNS (HTTPS)
Invoke-WebRequest -Uri https://lab-commit-task.lab-commit-v1.internal -UseBasicParsing -SkipCertificateCheck

# View content
(Invoke-WebRequest -Uri http://internal-k8s-labcommi-frontend-d96276f890-497072400.il-central-1.elb.amazonaws.com -UseBasicParsing).Content
```

**Option B: RDP + Chrome Browser**
1. Set Administrator password:
   ```powershell
   net user Administrator "LabCommit2026!"
   ```

2. From local machine, start RDP port forward:
   ```bash
   aws ssm start-session --target i-09eac4ed880150ab0 \
     --document-name AWS-StartPortForwardingSession \
     --parameters "portNumber=3389,localPortNumber=33389"
   ```

3. Connect RDP client to `localhost:33389`
   - **User**: Administrator
   - **Password**: LabCommit2026!

4. Open Chrome and navigate to:
   - `http://internal-k8s-labcommi-frontend-d96276f890-497072400.il-central-1.elb.amazonaws.com`
   - or `https://lab-commit-task.lab-commit-v1.internal`

#### Expected Result

You should see:
- **Title**: "Hello Lab-commit"
- **Version**: "1.0.0" (blue, large font)
- **Status**: Green dot with "Connected to backend"
- **Source**: "environment" or "database"
- **Last updated**: Current time (updates every 5 seconds)

---

## Project Structure

```
Lab-commit/
├── app/
│   ├── backend/
│   │   ├── app.py              # Flask API (Python)
│   │   ├── requirements.txt    # Python dependencies
│   │   └── Dockerfile          # Backend container
│   └── frontend/
│       ├── index.html          # Frontend UI
│       ├── nginx.conf          # Nginx configuration
│       └── Dockerfile          # Frontend container
├── helm/
│   ├── backend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── secret.yaml
│   ├── frontend/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml    # ALB Ingress
│   ├── argocd/
│   └── monitoring/
├── scripts/
│   ├── delete-default-vpc.sh
│   └── setup-terraform-backend.sh
└── terraform/
    ├── modules/
    │   ├── vpc/        # VPC + Subnets + NAT + VPC Endpoints
    │   ├── eks/        # EKS Cluster + Worker Nodes + IAM
    │   ├── rds/        # RDS MySQL
    │   ├── ec2/        # Windows EC2 + SSM
    │   ├── route53/    # Private Hosted Zone + Records
    │   ├── ecr/        # Docker Repositories
    │   └── acm/        # SSL Certificate
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── backend.tf
    ├── provider.tf
    └── terraform.tfvars
```

---

## Infrastructure Outputs

After `terraform apply`, you'll get:

| Output | Example Value |
|--------|---------------|
| `eks_cluster_name` | lab-commit-v1-cluster |
| `eks_cluster_endpoint` | https://8F26F0DE4FDD93311595E212FC8FF186.gr7.il-central-1.eks.amazonaws.com |
| `rds_endpoint` | lab-commit-v1-db.cnwcoewq02vx.il-central-1.rds.amazonaws.com:3306 |
| `windows_instance_id` | i-09eac4ed880150ab0 |
| `windows_ssm_command` | aws ssm start-session --target i-09eac4ed880150ab0 |
| `ecr_backend_repository_url` | 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-backend |
| `ecr_frontend_repository_url` | 923337630273.dkr.ecr.il-central-1.amazonaws.com/lab-commit-v1-frontend |
| `acm_certificate_arn` | arn:aws:acm:il-central-1:923337630273:certificate/915b687d-1ac1-4ae3-a766-55922f79b8c9 |
| `route53_zone_name` | lab-commit-v1.internal |

---

## Security Features

✅ **No Default VPC** - Custom VPC only  
✅ **Private Subnets** - All workloads in private network  
✅ **NAT Gateway** - Outbound internet via NAT (no direct exposure)  
✅ **No SSH Keys** - SSM Session Manager only  
✅ **No CloudWatch Agent** - Prometheus/Grafana stack  
✅ **Encrypted State** - AES256 at rest  
✅ **State Locking** - DynamoDB prevents corruption  
✅ **SSL/TLS** - ACM certificate on ALB  
✅ **Private RDS** - Not internet-accessible  
✅ **VPC Endpoints** - Private AWS service access  

---

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n lab-commit
kubectl describe pod <pod-name> -n lab-commit
kubectl logs <pod-name> -n lab-commit
```

### Check Ingress/ALB
```bash
kubectl get ingress -n lab-commit
kubectl describe ingress frontend-frontend-ingress -n lab-commit
```

### Check ALB Controller Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Terraform State Locked
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Reset Everything
```bash
# Delete Helm releases
helm uninstall frontend -n lab-commit
helm uninstall backend -n lab-commit
kubectl delete namespace lab-commit

# Destroy Terraform
cd terraform
terraform destroy -auto-approve
```

---

## Deployment Checklist

- [x] AWS CLI configuration
- [x] Default VPC deletion
- [x] S3 + DynamoDB backend
- [x] VPC module (2 private subnets + NAT)
- [x] EKS 1.30 cluster with EC2 workers
- [x] Windows EC2 + SSM access
- [x] RDS MySQL
- [x] Route53 Private Hosted Zone
- [x] ECR Repositories
- [x] ACM Certificate
- [x] AWS Load Balancer Controller
- [x] Prometheus + Grafana
- [x] ArgoCD
- [x] Backend application (Helm)
- [x] Frontend application (Helm)
- [x] ALB Ingress with HTTPS
- [ ] CodePipeline CI/CD (optional)

---

## Author

**Candidate05**  
Account: 923337630273  
Region: il-central-1  
Repository: https://github.com/shaymelamud95/Lab-commit
