#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Terraform State Backend Setup ===${NC}"
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="il-central-1"
BUCKET_NAME="tfstate-lab-commit-${ACCOUNT_ID}"
TABLE_NAME="terraform-state-lock"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Account ID: $ACCOUNT_ID"
echo "  Region: $REGION"
echo "  Bucket Name: $BUCKET_NAME"
echo "  DynamoDB Table: $TABLE_NAME"
echo ""

# Check if bucket already exists
if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
  echo -e "${GREEN}✓ S3 bucket already exists: $BUCKET_NAME${NC}"
else
  echo "Step 1: Creating S3 bucket..."
  aws s3api create-bucket \
    --bucket ${BUCKET_NAME} \
    --region ${REGION} \
    --create-bucket-configuration LocationConstraint=${REGION}
  echo -e "${GREEN}✓ S3 bucket created${NC}"
fi

# Enable versioning
echo "Step 2: Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket ${BUCKET_NAME} \
  --versioning-configuration Status=Enabled
echo -e "${GREEN}✓ Versioning enabled (state recovery capability)${NC}"

# Enable encryption
echo "Step 3: Enabling encryption..."
aws s3api put-bucket-encryption \
  --bucket ${BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
echo -e "${GREEN}✓ Encryption enabled (AES256 at rest)${NC}"

# Block public access
echo "Step 4: Blocking public access..."
aws s3api put-public-access-block \
  --bucket ${BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo -e "${GREEN}✓ Public access blocked (defense in depth)${NC}"

# Check if DynamoDB table exists
if aws dynamodb describe-table --table-name ${TABLE_NAME} --region ${REGION} 2>/dev/null > /dev/null; then
  echo -e "${GREEN}✓ DynamoDB table already exists: $TABLE_NAME${NC}"
else
  echo "Step 5: Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name ${TABLE_NAME} \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region ${REGION} > /dev/null
  
  echo "  Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name ${TABLE_NAME} --region ${REGION}
  echo -e "${GREEN}✓ DynamoDB table created (state locking)${NC}"
fi

echo ""
echo -e "${GREEN}=== Backend Setup Complete! ===${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  S3 Bucket: ${BUCKET_NAME}"
echo "  - Versioning: Enabled"
echo "  - Encryption: AES256"
echo "  - Public Access: Blocked"
echo ""
echo "  DynamoDB Table: ${TABLE_NAME}"
echo "  - Billing Mode: PAY_PER_REQUEST"
echo "  - Primary Key: LockID (String)"
echo ""
echo -e "${BLUE}Next step: cd ../terraform && terraform init${NC}"
