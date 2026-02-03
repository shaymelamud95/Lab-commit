#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Default VPC Deletion Script ===${NC}"
echo ""

# Parse arguments
FORCE=false
VPC_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--force)
      FORCE=true
      shift
      ;;
    *)
      VPC_ID="$1"
      shift
      ;;
  esac
done

# Get VPC ID if not provided
if [ -n "$VPC_ID" ]; then
  echo -e "${YELLOW}Using provided VPC ID: $VPC_ID${NC}"
else
  echo "Checking for default VPC..."
  VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --region il-central-1 \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)
fi

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo -e "${GREEN}✓ No default VPC found - account is clean${NC}"
  exit 0
fi

echo -e "${YELLOW}Found VPC: $VPC_ID${NC}"
echo ""

# Confirm deletion unless --force
if [ "$FORCE" = false ]; then
  read -p "Delete VPC $VPC_ID? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Deletion cancelled"
    exit 0
  fi
fi

echo ""
echo -e "${YELLOW}=== Starting deletion process ===${NC}"

# 1. Delete Internet Gateway
echo "Step 1: Deleting Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[0].InternetGatewayId' \
  --output text 2>/dev/null)

if [ "$IGW_ID" != "None" ] && [ -n "$IGW_ID" ]; then
  echo "  Detaching IGW: $IGW_ID"
  aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
  echo "  Deleting IGW: $IGW_ID"
  aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
  echo -e "  ${GREEN}✓ Internet Gateway deleted${NC}"
else
  echo "  No Internet Gateway found"
fi

# 2. Delete Subnets
echo "Step 2: Deleting Subnets..."
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' \
  --output text | tr '\t' '\n' | while read subnet; do
    if [ -n "$subnet" ]; then
      echo "  Deleting subnet: $subnet"
      aws ec2 delete-subnet --subnet-id $subnet
    fi
done
echo -e "  ${GREEN}✓ Subnets deleted${NC}"

# 3. Delete Security Groups
echo "Step 3: Deleting Security Groups..."
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text | tr '\t' '\n' | while read sg; do
    if [ -n "$sg" ]; then
      echo "  Deleting SG: $sg"
      aws ec2 delete-security-group --group-id $sg 2>/dev/null || echo "  (skipped)"
    fi
done
echo -e "  ${GREEN}✓ Security groups processed${NC}"

# 4. Delete Network ACLs
echo "Step 4: Deleting Network ACLs..."
aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' \
  --output text | tr '\t' '\n' | while read nacl; do
    if [ -n "$nacl" ]; then
      echo "  Deleting NACL: $nacl"
      aws ec2 delete-network-acl --network-acl-id $nacl 2>/dev/null || echo "  (skipped)"
    fi
done
echo -e "  ${GREEN}✓ Network ACLs processed${NC}"

# 5. Delete VPC
echo "Step 5: Deleting VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID
echo -e "${GREEN}✓ VPC $VPC_ID deleted${NC}"

echo ""
echo -e "${GREEN}=== VPC deleted successfully! ===${NC}"
echo ""
echo "Remaining VPCs in account:"
aws ec2 describe-vpcs --region il-central-1 --query 'Vpcs[*].[VpcId,IsDefault,CidrBlock]' --output table
