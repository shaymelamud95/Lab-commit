#!/bin/bash
# =============================================================================
# Upload Helm to S3 for Private VPC Windows EC2
# =============================================================================
# Only helm needs to be uploaded - AWS CLI is pre-installed on Windows AMI
# and kubectl is downloaded from Amazon's public amazon-eks S3 bucket
# =============================================================================

set -e

# Configuration
REGION="${AWS_REGION:-il-central-1}"
TOOLS_DIR="/tmp/windows-tools"
HELM_VERSION="v3.14.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Helm Upload Script for Private VPC ===${NC}"
echo ""
echo "Note: AWS CLI is pre-installed on Windows Server 2022 AMI"
echo "Note: kubectl is downloaded from amazon-eks public S3 bucket"
echo ""

# Get bucket name from Terraform output or parameter
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <bucket-name>${NC}"
    echo ""
    echo "Getting bucket name from Terraform output..."
    cd "$(dirname "$0")/../terraform"
    BUCKET_NAME=$(terraform output -raw tools_bucket_name 2>/dev/null || echo "")
    cd - > /dev/null
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${RED}ERROR: Could not get bucket name from Terraform output.${NC}"
        echo "Please run 'terraform apply' first or provide bucket name as argument."
        exit 1
    fi
else
    BUCKET_NAME="$1"
fi

echo -e "${GREEN}Target S3 bucket: ${BUCKET_NAME}${NC}"
echo -e "${GREEN}Region: ${REGION}${NC}"
echo ""

# Create temp directory
rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

# Download helm for Windows
echo -e "${YELLOW}Downloading helm ${HELM_VERSION} for Windows...${NC}"
curl -sLO "https://get.helm.sh/helm-${HELM_VERSION}-windows-amd64.zip"
unzip -q "helm-${HELM_VERSION}-windows-amd64.zip"
mv "windows-amd64/helm.exe" .
rm -rf "windows-amd64" "helm-${HELM_VERSION}-windows-amd64.zip"
if [ ! -f "helm.exe" ]; then
    echo -e "${RED}ERROR: Failed to download helm${NC}"
    exit 1
fi
echo -e "${GREEN}✓ helm.exe downloaded ($(du -h helm.exe | cut -f1))${NC}"

echo ""
echo -e "${YELLOW}Uploading helm to S3 bucket: s3://${BUCKET_NAME}/tools/${NC}"

# Upload to S3
aws s3 cp helm.exe "s3://${BUCKET_NAME}/tools/helm.exe" --region "$REGION"
echo -e "${GREEN}✓ Uploaded helm.exe${NC}"

echo ""
echo -e "${GREEN}=== Upload Complete ===${NC}"
echo ""
echo "Helm uploaded to: s3://${BUCKET_NAME}/tools/helm.exe"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Replace the Windows EC2 instance to re-run user_data:"
echo "   cd terraform && terraform apply -replace=\"module.ec2.aws_instance.windows\""
echo ""
echo "2. Wait for instance to start, then connect via SSM:"
echo "   aws ssm start-session --target \$(terraform output -raw windows_instance_id)"
echo ""
echo "3. Verify tools on Windows:"
echo "   aws --version"
echo "   C:\\tools\\kubectl.exe version --client"
echo "   C:\\tools\\helm.exe version"
echo ""

# Cleanup
cd /
rm -rf "$TOOLS_DIR"
