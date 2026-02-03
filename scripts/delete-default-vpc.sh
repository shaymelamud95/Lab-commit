#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Default VPC Deletion Script ===${NC}"
echo ""

# Check for default VPC
echo "Checking for default VPC..."
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --region il-central-1 \
  --query 'Vpcs[0].VpcId' \
  --output text 2>/dev/null)

if [ "$DEFAULT_VPC_ID" == "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
  echo -e "${GREEN}✓ No default VPC found - account is clean${NC}"
  exit 0
fi

echo -e "${YELLOW}Found default VPC: $DEFAULT_VPC_ID${NC}"
echo ""

# Confirm deletion
read -p "Delete default VPC $DEFAULT_VPC_ID? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Deletion cancelled"
  exit 0
fi

echo ""
echo -e "${YELLOW}=== Starting deletion process ===${NC}"

# 1. Delete Internet Gateway
echo "Step 1: Deleting Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$DEFAULT_VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' \
  --output text 2>/dev/null)

if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
  echo "  Detaching IGW: $IGW_ID"
  aws ec2 detach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $DEFAULT_VPC_ID
  echo "  Deleting IGW: $IGW_ID"
  aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
  echo -e "  ${GREEN}✓ Internet Gateway deleted${NC}"
else
  echo "  No Internet Gateway found"
fi

# 2. Delete Subnets
echo "Step 2: Deleting Subnets..."
SUBNET_COUNT=0
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
  --query 'Subnets[*].SubnetId' \
  --output text | tr '\t' '\n' | while read subnet; do
    if [ -n "$subnet" ]; then
      echo "  Deleting subnet: $subnet"
      aws ec2 delete-subnet --subnet-id $subnet
      SUBNET_COUNT=$((SUBNET_COUNT + 1))
    fi
done
echo -e "  ${GREEN}✓ Subnets deleted${NC}"

# 3. Delete Security Groups (non-default)
echo "Step 3: Deleting Security Groups..."
SG_COUNT=0
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text | tr '\t' '\n' | while read sg; do
    if [ -n "$sg" ]; then
      echo "  Deleting SG: $sg"
      aws ec2 delete-security-group --group-id $sg 2>/dev/null || echo "  (skipped - may have dependencies)"
      SG_COUNT=$((SG_COUNT + 1))
    fi
done
if [ $SG_COUNT -eq 0 ]; then
  echo "  No custom security groups found"
else
  echo -e "  ${GREEN}✓ Security groups deleted${NC}"
fi

# 4. Delete Network ACLs (non-default)
echo "Step 4: Deleting Network ACLs..."
NACL_COUNT=0
aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
  --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' \
  --output text | tr '\t' '\n' | while read nacl; do
    if [ -n "$nacl" ]; then
      echo "  Deleting NACL: $nacl"
      aws ec2 delete-network-acl --network-acl-id $nacl 2>/dev/null || echo "  (skipped)"
      NACL_COUNT=$((NACL_COUNT + 1))
    fi
done
if [ $NACL_COUNT -eq 0 ]; then
  echo "  No custom NACLs found"
else
  echo -e "  ${GREEN}✓ Network ACLs deleted${NC}"
fi

# 5. Delete VPC
echo "Step 5: Deleting VPC..."
aws ec2 delete-vpc --vpc-id $DEFAULT_VPC_ID
echo -e "${GREEN}✓ VPC $DEFAULT_VPC_ID deleted${NC}"

echo ""
echo -e "${GREEN}=== Default VPC deleted successfully! ===${NC}"
echo ""

# Verification
echo "Current VPCs in account:"
aws ec2 describe-vpcs --region il-central-1 --output table
