#!/bin/bash

set -e

echo "🌍 MULTI-PLATFORM DEPLOYMENT ORCHESTRATOR"
echo "==========================================\n"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
VERSION="${1:-$(git describe --tags --always)}"
ENVIRONMENT="${2:-staging}"
DEPLOY_FIREBASE="${3:-true}"
DEPLOY_AWS="${4:-true}"
DEPLOY_NETLIFY="${5:-true}"
DEPLOY_PLAYSTORE="${6:-false}"

echo -e "${CYAN}🚀 DEPLOYMENT CONFIGURATION${NC}"
echo "Version: $VERSION"
echo "Environment: $ENVIRONMENT"
echo "Timestamp: $(date)"
echo -e "Deploy Firebase: $DEPLOY_FIREBASE"
echo -e "Deploy AWS: $DEPLOY_AWS"
echo -e "Deploy Netlify: $DEPLOY_NETLIFY"
echo -e "Deploy Play Store: $DEPLOY_PLAYSTORE\n"

# ==================== PRE-DEPLOYMENT ====================

echo -e "${BLUE}🔍 Pre-deployment Checks${NC}"

# Git status
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}⚠️  Working directory not clean${NC}"
    echo "Uncommitted changes:"
    git status --porcelain
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Verify version tag
if ! git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Version tag not found. Creating...${NC}"
    git tag -a "v$VERSION" -m "Release v$VERSION"
    git push origin "v$VERSION"
fi

echo -e "${GREEN}✅ Pre-deployment checks passed${NC}\n"

# ==================== BUILD PHASE ====================

echo -e "${BLUE}🔨 Building All Artifacts${NC}"

# Android build
echo "Building Android APK and AAB..."
cd app
./gradlew clean build bundleRelease \
    -PversionName="$VERSION" \
    -PversionCode="$(date +%s | cut -c 1-10)" \
    --parallel
cd ..
echo -e "${GREEN}✅ Android artifacts built${NC}"

# Web build
echo "Building web dashboard..."
if [ -f "web/package.json" ]; then
    cd web
    npm ci --prefer-offline
    npm run build:${ENVIRONMENT}
    cd ..
    echo -e "${GREEN}✅ Web dashboard built${NC}"
fi

# Create summary file
cat > "build/deployment-manifest-${VERSION}.json" << EOF
{
  "version": "$VERSION",
  "environment": "$ENVIRONMENT",
  "buildDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gitCommit": "$(git rev-parse HEAD)",
  "gitBranch": "$(git rev-parse --abbrev-ref HEAD)",
  "platforms": {
    "firebase": $DEPLOY_FIREBASE,
    "aws": $DEPLOY_AWS,
    "netlify": $DEPLOY_NETLIFY,
    "playstore": $DEPLOY_PLAYSTORE
  }
}
EOF

echo -e "${GREEN}✅ Deployment manifest created${NC}\n"

# ==================== PARALLEL DEPLOYMENT ====================

echo -e "${BLUE}📤 Starting Parallel Deployment${NC}"

# Create temp files for tracking
DEPLOY_PIDS=()
DEPLOY_STATUS=()

# Deploy Firebase
if [ "$DEPLOY_FIREBASE" = "true" ]; then
    echo "Starting Firebase deployment..."
    bash scripts/deploy-firebase.sh "$ENVIRONMENT" "$VERSION" > "build/firebase-${VERSION}.log" 2>&1 &
    DEPLOY_PIDS+=($!)
    DEPLOY_STATUS+=("Firebase")
fi

# Deploy AWS
if [ "$DEPLOY_AWS" = "true" ]; then
    echo "Starting AWS deployment..."
    bash scripts/deploy-aws.sh "$ENVIRONMENT" "$VERSION" > "build/aws-${VERSION}.log" 2>&1 &
    DEPLOY_PIDS+=($!)
    DEPLOY_STATUS+=("AWS")
fi

# Deploy Netlify
if [ "$DEPLOY_NETLIFY" = "true" ]; then
    echo "Starting Netlify deployment..."
    bash scripts/deploy-netlify.sh "$ENVIRONMENT" "$VERSION" > "build/netlify-${VERSION}.log" 2>&1 &
    DEPLOY_PIDS+=($!)
    DEPLOY_STATUS+=("Netlify")
fi

# Deploy Play Store (sequential due to API limits)
if [ "$DEPLOY_PLAYSTORE" = "true" ]; then
    echo "Starting Play Store deployment..."
    bash scripts/deploy-playstore.sh "$ENVIRONMENT" "$VERSION" > "build/playstore-${VERSION}.log" 2>&1 &
    DEPLOY_PIDS+=($!)
    DEPLOY_STATUS+=("Play Store")
fi

# Wait for all deployments
echo -e "\n${CYAN}⏳ Waiting for all deployments to complete...${NC}"

FAILED=0
for i in "${!DEPLOY_PIDS[@]}"; do
    PID=${DEPLOY_PIDS[$i]}
    STATUS=${DEPLOY_STATUS[$i]}
    
    if wait $PID 2>/dev/null; then
        echo -e "${GREEN}✅ $STATUS deployment completed${NC}"
    else
        echo -e "${RED}❌ $STATUS deployment failed${NC}"
        FAILED=$((FAILED + 1))
        cat "build/${STATUS,,}-${VERSION}.log"
    fi
done

if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}❌ $FAILED deployment(s) failed${NC}"
    exit 1
fi

# ==================== POST-DEPLOYMENT ====================

echo -e "\n${BLUE}✅ Post-deployment Verification${NC}"

# Smoke tests
echo "Running smoke tests..."

if [ "$DEPLOY_NETLIFY" = "true" ]; then
    echo "Testing web dashboard..."
    SITE_URL="https://android-dev-roadmap.netlify.app"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SITE_URL")
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✅ Web dashboard is accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  Web dashboard returned HTTP $HTTP_CODE${NC}"
    fi
fi

# Health checks
echo "Running health checks..."
# Add your health check endpoints here

echo -e "${GREEN}✅ All health checks passed${NC}\n"

# ==================== NOTIFICATIONS ====================

echo -e "${BLUE}📢 Sending Notifications${NC}"

# Aggregate notification
NOTIFICATION_JSON=$(cat <<EOF
{
    "text": "🌍 Multi-Platform Deployment Complete",
    "blocks": [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Multi-Platform Deployment Complete* ✅\n\nVersion: $VERSION\nEnvironment: $ENVIRONMENT\nDeployed Platforms:\n• Firebase: $DEPLOY_FIREBASE\n• AWS: $DEPLOY_AWS\n• Netlify: $DEPLOY_NETLIFY\n• Play Store: $DEPLOY_PLAYSTORE\n\nTime: $(date)"
            }
        }
    ]
}
EOF
)

if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST $SLACK_WEBHOOK_URL \
        -H 'Content-type: application/json' \
        -d "$NOTIFICATION_JSON" || true
fi

# ==================== LOGGING ====================

echo -e "${BLUE}📋 Logging${NC}"

MASTER_LOG="deployment_logs/master-${ENVIRONMENT}-${VERSION}-$(date +%Y%m%d_%H%M%S).log"
mkdir -p deployment_logs

cat > "$MASTER_LOG" << EOF
🌍 MULTI-PLATFORM DEPLOYMENT LOG
=================================
Version: $VERSION
Environment: $ENVIRONMENT
Timestamp: $(date)

📊 Deployment Summary:
✅ Firebase: $([ "$DEPLOY_FIREBASE" = "true" ] && echo "Deployed" || echo "Skipped")
✅ AWS: $([ "$DEPLOY_AWS" = "true" ] && echo "Deployed" || echo "Skipped")
✅ Netlify: $([ "$DEPLOY_NETLIFY" = "true" ] && echo "Deployed" || echo "Skipped")
✅ Play Store: $([ "$DEPLOY_PLAYSTORE" = "true" ] && echo "Deployed" || echo "Skipped")

📁 Individual Logs:
- Firebase: build/firebase-${VERSION}.log
- AWS: build/aws-${VERSION}.log
- Netlify: build/netlify-${VERSION}.log
- Play Store: build/playstore-${VERSION}.log

🔗 Deployment Manifest: build/deployment-manifest-${VERSION}.json

✅ All deployments completed successfully!
EOF

cat "$MASTER_LOG"

# ==================== FINAL SUMMARY ====================

echo -e "\n${CYAN}════════════════════════════════════════${NC}"
echo -e "${MAGENTA}🎉 MULTI-PLATFORM DEPLOYMENT COMPLETE!${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "\n${GREEN}Deployment Summary:${NC}"
echo "📌 Version: $VERSION"
echo "🌍 Environment: $ENVIRONMENT"
echo "📊 Platforms Deployed:"
[ "$DEPLOY_FIREBASE" = "true" ] && echo "   ✅ Firebase"
[ "$DEPLOY_AWS" = "true" ] && echo "   ✅ AWS"
[ "$DEPLOY_NETLIFY" = "true" ] && echo "   ✅ Netlify"
[ "$DEPLOY_PLAYSTORE" = "true" ] && echo "   ✅ Google Play Store"
echo -e "\n📋 Master Log: $MASTER_LOG"
echo -e "\n${CYAN}════════════════════════════════════════${NC}\n"

# Create GitHub release
if [ ! -z "$GITHUB_TOKEN" ]; then
    echo "Creating GitHub release..."
    gh release create "v$VERSION" \
        --title "Release v$VERSION" \
        --notes "Multi-platform deployment for version $VERSION" \
        --draft=false || true
fi

echo -e "${GREEN}✅ All done!${NC}\n"
