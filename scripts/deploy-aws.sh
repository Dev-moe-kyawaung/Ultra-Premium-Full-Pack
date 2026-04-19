#!/bin/bash

set -e

echo "☁️  AWS DEPLOYMENT SCRIPT"
echo "========================\n"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"
ENVIRONMENT="${1:-production}"
VERSION="${2:-$(git describe --tags --always)}"
S3_BUCKET="android-dev-roadmap-builds"
CLOUDFRONT_DIST_ID="${CLOUDFRONT_DIST_ID:-E123456789ABC}"
BUILD_DIR="build"

echo -e "${CYAN}📊 AWS Deployment Configuration${NC}"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"
echo "Version: $VERSION"
echo "S3 Bucket: $S3_BUCKET"
echo "CloudFront Distribution: $CLOUDFRONT_DIST_ID\n"

# ==================== VALIDATION ====================

echo -e "${BLUE}🔍 Pre-deployment Validation${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo "Install: https://aws.amazon.com/cli/"
    exit 1
fi
echo -e "${GREEN}✅ AWS CLI $(aws --version | cut -d' ' -f1,2)${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity --profile $AWS_PROFILE &>/dev/null; then
    echo -e "${RED}❌ AWS credentials invalid${NC}"
    echo "Configure: aws configure --profile $AWS_PROFILE"
    exit 1
fi
echo -e "${GREEN}✅ AWS credentials valid${NC}"

# Check S3 bucket exists
if ! aws s3 ls "s3://${S3_BUCKET}" --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
    echo -e "${RED}❌ S3 bucket not found: ${S3_BUCKET}${NC}"
    exit 1
fi
echo -e "${GREEN}✅ S3 bucket accessible${NC}\n"

# ==================== BUILD PREPARATION ====================

echo -e "${BLUE}📦 Build Preparation${NC}"

# Create build directory structure
mkdir -p "${BUILD_DIR}/aws"
echo "Build directory created: ${BUILD_DIR}/aws"

# Prepare APK for upload
if [ -f "app/build/outputs/apk/release/app-release.apk" ]; then
    echo "Preparing APK for upload..."
    cp app/build/outputs/apk/release/app-release.apk \
       "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.apk"
    echo -e "${GREEN}✅ APK prepared${NC}"
fi

# Prepare AAB for upload
if [ -f "app/build/outputs/bundle/release/app-release.aab" ]; then
    echo "Preparing AAB for upload..."
    cp app/build/outputs/bundle/release/app-release.aab \
       "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.aab"
    echo -e "${GREEN}✅ AAB prepared${NC}"
fi

# Create checksums
echo "Creating checksums..."
cd "${BUILD_DIR}/aws"
sha256sum *.apk *.aab > checksums.sha256 2>/dev/null || true
cd ../../
echo -e "${GREEN}✅ Checksums created${NC}\n"

# ==================== AWS UPLOAD ====================

echo -e "${BLUE}📤 Uploading to AWS S3${NC}"

# Create S3 directory structure
S3_PREFIX="builds/${ENVIRONMENT}/${VERSION}"

# Upload APK
if [ -f "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.apk" ]; then
    echo "Uploading APK..."
    aws s3 cp "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.apk" \
            "s3://${S3_BUCKET}/${S3_PREFIX}/app-release.apk" \
            --region $AWS_REGION \
            --profile $AWS_PROFILE \
            --storage-class STANDARD \
            --metadata "version=${VERSION},build-date=$(date),environment=${ENVIRONMENT}" \
            --cache-control "max-age=31536000,public"
    echo -e "${GREEN}✅ APK uploaded${NC}"
    APK_URL="https://${CLOUDFRONT_DIST_ID}.cloudfront.net/${S3_PREFIX}/app-release.apk"
fi

# Upload AAB
if [ -f "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.aab" ]; then
    echo "Uploading AAB..."
    aws s3 cp "${BUILD_DIR}/aws/android-dev-roadmap-${VERSION}-release.aab" \
            "s3://${S3_BUCKET}/${S3_PREFIX}/app-release.aab" \
            --region $AWS_REGION \
            --profile $AWS_PROFILE \
            --storage-class STANDARD \
            --metadata "version=${VERSION},build-date=$(date),environment=${ENVIRONMENT}" \
            --cache-control "max-age=31536000,public"
    echo -e "${GREEN}✅ AAB uploaded${NC}"
    AAB_URL="https://${CLOUDFRONT_DIST_ID}.cloudfront.net/${S3_PREFIX}/app-release.aab"
fi

# Upload checksums
if [ -f "${BUILD_DIR}/aws/checksums.sha256" ]; then
    echo "Uploading checksums..."
    aws s3 cp "${BUILD_DIR}/aws/checksums.sha256" \
            "s3://${S3_BUCKET}/${S3_PREFIX}/checksums.sha256" \
            --region $AWS_REGION \
            --profile $AWS_PROFILE
    echo -e "${GREEN}✅ Checksums uploaded${NC}"
fi

# Upload manifest (metadata)
echo "Uploading metadata..."
cat > "${BUILD_DIR}/aws/manifest.json" << EOF
{
  "version": "$VERSION",
  "environment": "$ENVIRONMENT",
  "buildDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gitCommit": "$(git rev-parse HEAD)",
  "gitBranch": "$(git rev-parse --abbrev-ref HEAD)",
  "files": {
    "apk": "app-release.apk",
    "aab": "app-release.aab",
    "checksums": "checksums.sha256"
  },
  "urls": {
    "apk": "$APK_URL",
    "aab": "$AAB_URL"
  },
  "releaseNotes": "$(git log -1 --pretty=%B)"
}
EOF

aws s3 cp "${BUILD_DIR}/aws/manifest.json" \
        "s3://${S3_BUCKET}/${S3_PREFIX}/manifest.json" \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        --content-type "application/json"
echo -e "${GREEN}✅ Metadata uploaded${NC}\n"

# ==================== CLOUDFRONT INVALIDATION ====================

echo -e "${BLUE}🔄 CloudFront Invalidation${NC}"

echo "Invalidating CloudFront cache..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id $CLOUDFRONT_DIST_ID \
    --paths "/${S3_PREFIX}/*" \
    --profile $AWS_PROFILE \
    --query 'Invalidation.Id' \
    --output text)

echo "Invalidation ID: $INVALIDATION_ID"

# Wait for invalidation to complete
echo "Waiting for cache invalidation..."
aws cloudfront wait invalidation-completed \
    --distribution-id $CLOUDFRONT_DIST_ID \
    --id $INVALIDATION_ID \
    --profile $AWS_PROFILE

echo -e "${GREEN}✅ CloudFront cache invalidated${NC}\n"

# ==================== DATABASE SYNC ====================

echo -e "${BLUE}💾 Database Sync${NC}"

# Update S3 metadata in DynamoDB (optional)
if [ ! -z "$DYNAMODB_TABLE" ]; then
    echo "Updating DynamoDB..."
    aws dynamodb put-item \
        --table-name $DYNAMODB_TABLE \
        --item "{
            \"buildId\": {\"S\": \"${VERSION}\"},
            \"version\": {\"S\": \"${VERSION}\"},
            \"environment\": {\"S\": \"${ENVIRONMENT}\"},
            \"s3Key\": {\"S\": \"${S3_PREFIX}\"},
            \"uploadDate\": {\"N\": \"$(date +%s)\"},
            \"gitCommit\": {\"S\": \"$(git rev-parse HEAD)\"}
        }" \
        --region $AWS_REGION \
        --profile $AWS_PROFILE
    echo -e "${GREEN}✅ DynamoDB updated${NC}"
fi

# ==================== VERIFICATION ====================

echo -e "${BLUE}✅ Post-deployment Verification${NC}"

# Verify APK upload
if [ ! -z "$APK_URL" ]; then
    echo "Verifying APK accessibility..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$APK_URL")
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✅ APK is accessible (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${YELLOW}⚠️  APK returned HTTP $HTTP_CODE${NC}"
    fi
fi

# Verify AAB upload
if [ ! -z "$AAB_URL" ]; then
    echo "Verifying AAB accessibility..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$AAB_URL")
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✅ AAB is accessible (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${YELLOW}⚠️  AAB returned HTTP $HTTP_CODE${NC}"
    fi
fi

# Get object sizes
echo -e "\n${BLUE}📊 Upload Statistics${NC}"
APK_SIZE=$(aws s3api head-object \
    --bucket $S3_BUCKET \
    --key "${S3_PREFIX}/app-release.apk" \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'ContentLength' \
    --output text 2>/dev/null || echo "0")

echo "APK Size: $(numfmt --to=iec $APK_SIZE 2>/dev/null || echo \"$APK_SIZE bytes\")"

# ==================== CLOUDWATCH MONITORING ====================

echo -e "${BLUE}📊 Setting up CloudWatch Monitoring${NC}"

# Put custom metric for deployment
aws cloudwatch put-metric-data \
    --namespace "AndroidApp" \
    --metric-name "DeploymentCount" \
    --value 1 \
    --unit Count \
    --dimensions Environment=$ENVIRONMENT Version=$VERSION \
    --region $AWS_REGION \
    --profile $AWS_PROFILE

echo -e "${GREEN}✅ CloudWatch metric recorded${NC}\n"

# ==================== NOTIFICATIONS ====================

echo -e "${BLUE}📢 Notifications${NC}"

# Send SNS notification (if configured)
if [ ! -z "$SNS_TOPIC_ARN" ]; then
    echo "Sending SNS notification..."
    aws sns publish \
        --topic-arn $SNS_TOPIC_ARN \
        --subject "Android App Deployment: $VERSION" \
        --message "Environment: $ENVIRONMENT\nVersion: $VERSION\nAPK: $APK_URL\nAAB: $AAB_URL\nTime: $(date)" \
        --region $AWS_REGION \
        --profile $AWS_PROFILE
    echo -e "${GREEN}✅ SNS notification sent${NC}"
fi

# Send Slack notification (if configured)
if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
    echo "Sending Slack notification..."
    curl -X POST $SLACK_WEBHOOK_URL \
        -H 'Content-type: application/json' \
        -d "{
            \"text\": \"☁️  AWS Deployment Successful\",
            \"blocks\": [
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"*AWS Deployment Successful* ✅\n\nEnvironment: $ENVIRONMENT\nVersion: $VERSION\nAPK: $APK_URL\nAAB: $AAB_URL\"
                    }
                }
            ]
        }" || true
fi

# ==================== LOGGING ====================

echo -e "${BLUE}📋 Logging${NC}"

LOG_FILE="deployment_logs/aws-${ENVIRONMENT}-${VERSION}-$(date +%Y%m%d_%H%M%S).log"
mkdir -p deployment_logs

cat > "$LOG_FILE" << EOF
☁️  AWS Deployment Log
======================
Environment: $ENVIRONMENT
Region: $AWS_REGION
Version: $VERSION
Timestamp: $(date)
S3 Bucket: $S3_BUCKET
S3 Prefix: $S3_PREFIX

✅ Deployment Status: SUCCESS

Uploaded Files:
- APK: $APK_URL
- AAB: $AAB_URL
- Checksums: s3://${S3_BUCKET}/${S3_PREFIX}/checksums.sha256
- Manifest: s3://${S3_BUCKET}/${S3_PREFIX}/manifest.json

CloudFront Invalidation: $INVALIDATION_ID
APK Size: $APK_SIZE bytes

Git Information:
- Commit: $(git rev-parse HEAD)
- Branch: $(git rev-parse --abbrev-ref HEAD)
- Author: $(git log -1 --format=%an)
EOF

# ==================== FINAL SUMMARY ====================

echo -e "\n${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ AWS DEPLOYMENT COMPLETE!${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "\n${GREEN}Summary:${NC}"
echo "📦 Environment: $ENVIRONMENT"
echo "🌍 Region: $AWS_REGION"
echo "📌 Version: $VERSION"
echo "🪣 S3 Bucket: $S3_BUCKET"
echo "📁 S3 Prefix: $S3_PREFIX"
echo -e "\n${YELLOW}Download URLs:${NC}"
[ ! -z "$APK_URL" ] && echo "📱 APK: $APK_URL"
[ ! -z "$AAB_URL" ] && echo "📦 AAB: $AAB_URL"
echo -e "\n${YELLOW}CDN URLs:${NC}"
echo "🚀 CloudFront: https://${CLOUDFRONT_DIST_ID}.cloudfront.net"
echo "📋 Log: $LOG_FILE"
echo -e "\n${CYAN}════════════════════════════════════════${NC}\n"
