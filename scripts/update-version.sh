#!/bin/bash
# Update application version manually to test version updates

NEW_VERSION="1.0.1"

cd ~/projects/Lab-commit

#------------------------------------------------------------------------------
# Update backend environment variable
#------------------------------------------------------------------------------
# Backend reads version from APP_VERSION environment variable
kubectl set env deployment/backend -n lab-commit APP_VERSION=${NEW_VERSION}

# Wait for rollout
kubectl rollout status deployment/backend -n lab-commit --timeout=120s

echo "Backend updated to version ${NEW_VERSION}"
kubectl get pods -n lab-commit -l app=backend

#------------------------------------------------------------------------------
# Alternative: Update database value (if using database source)
#------------------------------------------------------------------------------
# Get RDS endpoint
RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint | cut -d: -f1)
RDS_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "lab-commit-v1-db-password" \
  --region il-central-1 \
  --query 'SecretString' \
  --output text)

# Update version in database
kubectl run mysql-client --rm -i --restart=Never --image=mysql:8.0 \
  --namespace lab-commit -- \
  mysql -h ${RDS_ENDPOINT} -u labcommit -p${RDS_PASSWORD} labcommitdb \
  -e "UPDATE app_version SET version='${NEW_VERSION}', updated_at=NOW() WHERE id=1;"

echo "Version updated to ${NEW_VERSION} in database"
echo "Refresh browser to see changes (polls every 5 seconds)"
