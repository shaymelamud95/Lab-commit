#!/bin/bash
set -e

#==============================================================================
# Lab-Commit Post-Terraform Deployment
# Run after 'terraform apply' completes
#==============================================================================

cd ~/projects/Lab-commit

#------------------------------------------------------------------------------
# Step 1: Configure kubectl for EKS cluster
#------------------------------------------------------------------------------
aws eks update-kubeconfig --name lab-commit-v1-cluster --region il-central-1
kubectl get nodes

#------------------------------------------------------------------------------
# Step 2: Install AWS Load Balancer Controller
#------------------------------------------------------------------------------
# Add Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get IAM role ARN from Terraform output
cd terraform
ALB_ROLE_ARN=$(terraform output -raw eks_alb_controller_role_arn)
cd ..

# Install controller with IRSA (IAM Roles for Service Accounts)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=lab-commit-v1-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ALB_ROLE_ARN}" \
  --wait --timeout=300s

# Wait for controller pods to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -n kube-system --timeout=300s

kubectl get pods -n kube-system | grep aws-load-balancer-controller

#------------------------------------------------------------------------------
# Step 3: Install Prometheus + Grafana monitoring stack
#------------------------------------------------------------------------------
# Add Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install kube-prometheus-stack (includes Prometheus, Grafana, Alertmanager)
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=ClusterIP \
  --set prometheus.service.type=ClusterIP \
  --wait --timeout=600s

# Get Grafana admin password
echo "Grafana password:"
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo

#------------------------------------------------------------------------------
# Step 4: Install ArgoCD for GitOps
#------------------------------------------------------------------------------
# Add Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create ArgoCD namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --wait --timeout=600s

# Get ArgoCD admin password
echo "ArgoCD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

#------------------------------------------------------------------------------
# Step 5: Build and push Docker images to ECR
#------------------------------------------------------------------------------
# Get AWS account ID and ECR URLs
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="il-central-1"
ECR_BACKEND="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/lab-commit-v1-backend"
ECR_FRONTEND="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/lab-commit-v1-frontend"

# Login to ECR
aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build and push backend image
cd app/backend
docker build -t ${ECR_BACKEND}:latest -t ${ECR_BACKEND}:v1.0.0 .
docker push ${ECR_BACKEND}:latest
docker push ${ECR_BACKEND}:v1.0.0
cd ../..

# Build and push frontend image
cd app/frontend
docker build -t ${ECR_FRONTEND}:latest -t ${ECR_FRONTEND}:v1.0.0 .
docker push ${ECR_FRONTEND}:latest
docker push ${ECR_FRONTEND}:v1.0.0
cd ../..

echo "Images pushed:"
echo "  Backend:  ${ECR_BACKEND}:latest"
echo "  Frontend: ${ECR_FRONTEND}:latest"

#------------------------------------------------------------------------------
# Step 6: Deploy backend application with Helm
#------------------------------------------------------------------------------
# Create application namespace
kubectl create namespace lab-commit --dry-run=client -o yaml | kubectl apply -f -

# Get RDS password from AWS Secrets Manager
RDS_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "lab-commit-v1-db-password" \
  --region il-central-1 \
  --query 'SecretString' \
  --output text)

# Deploy backend with database configuration
helm upgrade --install backend ./helm/backend \
  --namespace lab-commit \
  --set database.password="${RDS_PASSWORD}" \
  --set replicaCount=1 \
  --wait --timeout=300s

kubectl get pods -n lab-commit -l app=backend

#------------------------------------------------------------------------------
# Step 7: Deploy frontend application with Helm (creates ALB via Ingress)
#------------------------------------------------------------------------------
helm upgrade --install frontend ./helm/frontend \
  --namespace lab-commit \
  --set replicaCount=1 \
  --wait --timeout=300s

kubectl get pods -n lab-commit -l app=frontend

#------------------------------------------------------------------------------
# Step 8: Wait for ALB to be provisioned
#------------------------------------------------------------------------------
echo "Waiting for ALB creation (takes 2-3 minutes)..."
sleep 30

# Poll for ALB hostname
for i in {1..20}; do
    ALB_HOSTNAME=$(kubectl get ingress -n lab-commit \
      -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ ! -z "$ALB_HOSTNAME" ]; then
        echo "ALB created: ${ALB_HOSTNAME}"
        break
    fi
    
    echo "Waiting... ($i/20)"
    sleep 15
done

kubectl get ingress -n lab-commit

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
echo "Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Enable Route53 DNS record:"
echo "       cd terraform"
echo "       sed -i 's/enable_alb_lookup = false/enable_alb_lookup = true/' terraform.tfvars"
echo "       terraform apply -auto-approve"
echo ""
echo "  2. Test from Windows EC2:"
echo "       INSTANCE_ID=\$(terraform output -raw windows_instance_id)"
echo "       aws ssm start-session --target \${INSTANCE_ID}"
echo ""
echo "  3. Access monitoring (from local machine):"
echo "       kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "       kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo ""
