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
helm repo add eks https://aws.github.io/eks-charts
helm repo update

cd terraform
ALB_ROLE_ARN=$(terraform output -raw eks_alb_controller_role_arn)
cd ..

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=lab-commit-v1-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ALB_ROLE_ARN}" \
  --wait --timeout=300s

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -n kube-system --timeout=300s

kubectl get pods -n kube-system | grep aws-load-balancer-controller

#------------------------------------------------------------------------------
# Step 3: Install Prometheus + Grafana monitoring stack
#------------------------------------------------------------------------------
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=ClusterIP \
  --set prometheus.service.type=ClusterIP \
  --wait --timeout=600s

echo "Grafana password:"
kubectl get secret monitoring-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo

#------------------------------------------------------------------------------
# Step 4: Install ArgoCD for GitOps
#------------------------------------------------------------------------------
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --wait --timeout=600s

echo "ArgoCD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

#------------------------------------------------------------------------------
# Step 5: Build and push Docker images to ECR
#------------------------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="il-central-1"
ECR_BACKEND="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/lab-commit-v1-backend"
ECR_FRONTEND="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/lab-commit-v1-frontend"

aws ecr get-login-password --region ${REGION} | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

cd app/backend
docker build -t ${ECR_BACKEND}:latest -t ${ECR_BACKEND}:v1.0.0 .
docker push ${ECR_BACKEND}:latest
docker push ${ECR_BACKEND}:v1.0.0
cd ../..

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
kubectl create namespace lab-commit --dry-run=client -o yaml | kubectl apply -f -

RDS_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "lab-commit-v1-db-password" \
  --region il-central-1 \
  --query 'SecretString' \
  --output text)

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
# Step 9: Configure ArgoCD SSH Access to CodeCommit
#------------------------------------------------------------------------------
echo "=== Configuring ArgoCD SSH access to CodeCommit ==="

cd terraform
SSH_USER=$(terraform output -raw argocd_ssh_user_id)
SSH_SECRET=$(terraform output -raw argocd_ssh_key_secret_arn)
SSH_URL=$(terraform output -raw argocd_codecommit_ssh_url)
cd ..

echo "SSH User: ${SSH_USER}"
echo "SSH URL: ${SSH_URL}"

# Get private key from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id "${SSH_SECRET}" \
  --query 'SecretString' \
  --output text > /tmp/argocd-ssh-key

chmod 600 /tmp/argocd-ssh-key

# Create Kubernetes secret with SSH key
kubectl create secret generic argocd-codecommit-ssh \
  -n argocd \
  --from-file=sshPrivateKey=/tmp/argocd-ssh-key \
  --dry-run=client -o yaml | kubectl apply -f -

# Label for ArgoCD recognition
kubectl label secret argocd-codecommit-ssh \
  -n argocd \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

rm -f /tmp/argocd-ssh-key

echo "✅ ArgoCD SSH Secret created"

#------------------------------------------------------------------------------
# Step 10: Deploy ArgoCD Applications with SSH URLs
#------------------------------------------------------------------------------
echo "=== Deploying ArgoCD Applications ==="

# Update frontend-app.yaml with SSH URL
cat > argocd-apps/frontend-app.yaml << APPEOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: frontend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${SSH_URL}
    targetRevision: main
    path: helm/frontend
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: lab-commit
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
APPEOF

# Update backend-app.yaml with SSH URL
cat > argocd-apps/backend-app.yaml << APPEOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${SSH_URL}
    targetRevision: main
    path: helm/backend
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: lab-commit
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
APPEOF

# Apply ArgoCD resources
kubectl apply -f argocd-apps/argocd-ingress.yaml
kubectl apply -f argocd-apps/frontend-app.yaml
kubectl apply -f argocd-apps/backend-app.yaml

sleep 10

# Check ArgoCD Applications status
echo "ArgoCD Applications:"
kubectl get applications -n argocd

echo "✅ ArgoCD Applications deployed"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Deployment Complete!"
echo "======================================================================"
echo ""
echo "Access ArgoCD:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  URL: https://localhost:8080"
echo "  User: admin"
echo "  Password: (see above)"
echo ""
echo "Access Grafana:"
echo "  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "  URL: http://localhost:3000"
echo "  User: admin"
echo "  Password: (see above)"
echo ""
echo "Test Application from Windows EC2:"
echo "  aws ssm start-session --target $(cd terraform && terraform output -raw windows_instance_id)"
echo "  curl https://lab-commit-task.lab-commit-v1.internal"
echo ""
