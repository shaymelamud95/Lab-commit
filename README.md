# Lab-Commit: AWS EKS Infrastructure

AWS EKS 1.30 cluster with self-managed EC2 workers, Prometheus/Grafana, ArgoCD, and full-stack application.

---

## Architecture

Windows EC2 (SSM) → Internal ALB (HTTPS) → EKS Cluster
├── Frontend (Nginx)
├── Backend (Python)
├── RDS MySQL
├── Prometheus + Grafana
└── ArgoCD

text

**Features:**
- 100% Terraform infrastructure
- Private subnets only (NAT Gateway for outbound)
- No SSH keys (SSM Session Manager)
- Self-signed SSL certificate
- Route53 Private Hosted Zone

---

## Prerequisites

```bash
aws-cli   >= 2.32
terraform >= 1.14
kubectl   >= 1.30
helm      >= 3.0
docker    >= 20.10
Deployment Steps
Phase 1: Infrastructure (~15 minutes)
bash
# Navigate to project
cd ~/projects/Lab-commit

# Configure AWS
aws configure --profile lab-commit
export AWS_PROFILE=lab-commit

# Delete default VPC (required by lab)
./scripts/delete-default-vpc.sh --force

# Create S3 backend for Terraform state
./scripts/setup-terraform-backend.sh

# Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
Note: Keep enable_alb_lookup = false in terraform.tfvars for now.

Phase 2: Kubernetes Components (~10 minutes)
bash
# Run deployment script
cd ~/projects/Lab-commit
./scripts/post-terraform-deploy.sh
This script installs:

AWS Load Balancer Controller

Prometheus + Grafana

ArgoCD

Backend application (Python Flask)

Frontend application (Nginx)

The script will output:

Grafana password

ArgoCD password

ALB hostname

Phase 3: Enable Route53 DNS
The ALB is created by Kubernetes Ingress Controller. Now we can create the DNS record.

bash
# Enable ALB lookup in Terraform
cd ~/projects/Lab-commit/terraform
sed -i 's/enable_alb_lookup = false/enable_alb_lookup = true/' terraform.tfvars

# Create Route53 record
terraform apply -auto-approve
This creates: lab-commit-task.lab-commit-v1.internal → ALB

Phase 4: Testing
Quick test (PowerShell)
bash
# Connect to Windows EC2
INSTANCE_ID=$(cd terraform && terraform output -raw windows_instance_id)
aws ssm start-session --target ${INSTANCE_ID}

# Test application (in PowerShell)
Invoke-WebRequest -Uri https://lab-commit-task.lab-commit-v1.internal -UseBasicParsing
Browser test (RDP + Chrome)
bash
# 1. Set Windows password (in SSM PowerShell)
net user Administrator "LabCommit2026!"

# 2. Forward RDP port (from local machine)
aws ssm start-session --target ${INSTANCE_ID} \
  --document-name AWS-StartPortForwardingSession \
  --parameters "portNumber=3389,localPortNumber=33389"

# 3. Connect RDP to localhost:33389
#    User: Administrator
#    Password: LabCommit2026!

# 4. Open Chrome and navigate to:
#    https://lab-commit-task.lab-commit-v1.internal
Expected result:

Title: "Hello Lab-commit"

Version: "1.0.0" (updates every 5 seconds)

Status: Green dot "Connected to backend"

Access Monitoring
From your local machine:

bash
# Grafana (http://localhost:3000)
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &

# ArgoCD (https://localhost:8080)
kubectl -n argocd port-forward svc/argocd-server 8080:443 &

# Get passwords
kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
Project Structure
text
Lab-commit/
├── app/
│   ├── backend/              # Python Flask API
│   └── frontend/             # Nginx HTML/JS
├── helm/
│   ├── backend/              # Backend Helm chart
│   └── frontend/             # Frontend Helm chart (includes Ingress)
├── scripts/
│   ├── delete-default-vpc.sh
│   ├── setup-terraform-backend.sh
│   └── post-terraform-deploy.sh    # Main deployment script
└── terraform/
    ├── modules/              # VPC, EKS, RDS, EC2, Route53, ECR, ACM
    ├── main.tf
    └── terraform.tfvars      # Set enable_alb_lookup=true in Phase 3
Important Outputs
bash
cd terraform

terraform output eks_cluster_name
terraform output windows_instance_id
terraform output rds_endpoint
terraform output ecr_backend_repository_url
terraform output route53_zone_name
Troubleshooting
Check pod status:

bash
kubectl get pods -A
kubectl logs <pod-name> -n lab-commit
Check Ingress:

bash
kubectl get ingress -n lab-commit
kubectl describe ingress -n lab-commit
Check ALB Controller logs:

bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
Reset everything:

bash
# Delete Kubernetes resources
helm uninstall frontend backend -n lab-commit
kubectl delete namespace lab-commit monitoring argocd

# Destroy infrastructure
cd terraform
terraform destroy -auto-approve
Deployment Checklist
 Phase 1: Deploy infrastructure (terraform apply)

 Phase 2: Run deployment script (./scripts/post-terraform-deploy.sh)

 Phase 3: Enable Route53 (enable_alb_lookup = true)

 Phase 4: Test from Windows EC2

Security Features
No default VPC

Private subnets only

NAT Gateway for outbound traffic

No SSH keys (SSM only)

Self-signed certificate

Private RDS

VPC Endpoints

Encrypted S3 backend

---
## Updating the Backend DB Password

The backend application requires the correct DB password to connect to RDS. The password is stored in AWS Secrets Manager.

**Workflow:**
1. Retrieve the DB password from AWS Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value --secret-id lab-commit-v1-db-password --query 'SecretString' --output text
   ```
2. Update the value in `helm/backend/values.yaml`:
   - Set the `dbPassword` field to the value retrieved above.
3. Redeploy the backend application:
   ```bash
   helm upgrade backend ./helm/backend --namespace lab-commit --set dbPassword=<new-password>
   ```
4. Verify pod status:
   ```bash
   kubectl get pods -n lab-commit -l app=backend
   kubectl logs <backend-pod> -n lab-commit
   ```
5. If pods are stuck, delete them and let Kubernetes recreate:
   ```bash
   kubectl delete pod -n lab-commit -l app=backend
   ```

**Note:** Always use the latest password from Secrets Manager. If the password changes in RDS, update it in both Secrets Manager and values.yaml, then redeploy.

Notes
Q: Why enable_alb_lookup = false initially?
A: The ALB is created by Kubernetes, not Terraform. We enable it after the Ingress creates the ALB.

Q: Where to run kubectl/helm?
A: From your local WSL. The EKS API is publicly accessible.

Q: Where are credentials?
A: RDS password in AWS Secrets Manager. Grafana/ArgoCD passwords in Kubernetes secrets.

Author
Account: 923337630273
Region: il-central-1
Repository: https://github.com/shaymelamud95/Lab-commit
