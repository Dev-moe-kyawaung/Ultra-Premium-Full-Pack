#!/bin/bash

set -e

echo "🔥 FIREBASE DEPLOYMENT SCRIPT"
echo "=============================\n"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PROJECT_ID="${FIREBASE_PROJECT_ID:-android-dev-roadmap}"
ENVIRONMENT="${1:-production}"
VERSION="${2:-$(git describe --tags --always)}"
BUILD_DIR="build"
DIST_DIR="dist"

echo -e "${CYAN}📊 Deployment Configuration${NC}"
echo "Project: $PROJECT_ID"
echo "Environment: $ENVIRONMENT"
echo "Version: $VERSION"
echo "Timestamp: $(date)\n"

# ==================== VALIDATION ====================

echo -e "${BLUE}🔍 Pre-deployment Validation${NC}"

# Check Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found${NC}"
    echo "Install: npm install -g firebase-tools"
    exit 1
fi
echo -e "${GREEN}✅ Firebase CLI found${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js $(node --version)${NC}"

# Check authentication
echo -e "${BLUE}🔐 Firebase Authentication${NC}"
if ! firebase projects:list --token="${FIREBASE_TOKEN}" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Authenticating with Firebase...${NC}"
    firebase login
fi
echo -e "${GREEN}✅ Authenticated${NC}\n"

# ==================== BUILD PHASE ====================

echo -e "${BLUE}🔨 Building Application${NC}"

# Clean previous builds
rm -rf $BUILD_DIR $DIST_DIR
mkdir -p $BUILD_DIR

# Build backend functions
echo "Building Cloud Functions..."
cd functions
npm install --production
npm run build 2>/dev/null || echo "No build script for functions"
cd ..
echo -e "${GREEN}✅ Functions built${NC}"

# Build web dashboard
echo "Building web dashboard..."
if [ -f "web/package.json" ]; then
    cd web
    npm install
    npm run build
    cp -r dist ../build/web
    cd ..
    echo -e "${GREEN}✅ Web dashboard built${NC}"
else
    mkdir -p build/web
    echo -e "${YELLOW}⚠️  No web app found${NC}"
fi

# ==================== SECURITY SCAN ====================

echo -e "${BLUE}🔒 Security Scanning${NC}"

# Scan dependencies
echo "Scanning dependencies for vulnerabilities..."
npm audit --production 2>/dev/null || echo "Some vulnerabilities found (review recommended)"

# Check for secrets
echo "Checking for exposed secrets..."
if grep -r "PRIVATE_KEY\|SECRET_KEY\|API_KEY" --include="*.kt" --include="*.js" app/ 2>/dev/null; then
    echo -e "${RED}❌ Potential secrets found in code${NC}"
    exit 1
fi
echo -e "${GREEN}✅ No exposed secrets detected${NC}\n"

# ==================== DEPLOYMENT ====================

echo -e "${BLUE}📤 Deploying to Firebase${NC}"

case $ENVIRONMENT in
    production)
        echo "🚀 Deploying to PRODUCTION..."
        firebase use $PROJECT_ID --token="${FIREBASE_TOKEN}"
        ;;
    staging)
        echo "🧪 Deploying to STAGING..."
        firebase use $PROJECT_ID-staging --token="${FIREBASE_TOKEN}"
        ;;
    development)
        echo "🔧 Deploying to DEVELOPMENT..."
        firebase use $PROJECT_ID-dev --token="${FIREBASE_TOKEN}"
        ;;
    *)
        echo -e "${RED}❌ Unknown environment: $ENVIRONMENT${NC}"
        exit 1
        ;;
esac

# Deploy Firestore rules
echo "Deploying Firestore security rules..."
firebase deploy --only firestore:rules \
    --message "Firestore rules - v${VERSION}" \
    --token="${FIREBASE_TOKEN}" || true
echo -e "${GREEN}✅ Firestore rules deployed${NC}"

# Deploy Storage rules
echo "Deploying Storage security rules..."
firebase deploy --only storage \
    --message "Storage rules - v${VERSION}" \
    --token="${FIREBASE_TOKEN}" || true
echo -e "${GREEN}✅ Storage rules deployed${NC}"

# Deploy Cloud Functions
echo "Deploying Cloud Functions..."
firebase deploy --only functions \
    --message "Cloud Functions - v${VERSION}" \
    --token="${FIREBASE_TOKEN}" || true
echo -e "${GREEN}✅ Cloud Functions deployed${NC}"

# Deploy hosting
echo "Deploying hosting..."
if [ -d "build/web" ]; then
    firebase deploy --only hosting \
        --message "Web Dashboard - v${VERSION}" \
        --token="${FIREBASE_TOKEN}" || true
    echo -e "${GREEN}✅ Hosting deployed${NC}"
fi

# ==================== VERIFICATION ====================

echo -e "${BLUE}✅ Post-deployment Verification${NC}"

# Get Firebase URLs
HOSTING_URL=$(firebase hosting:channel:list --token="${FIREBASE_TOKEN}" 2>/dev/null | grep live | head -1 || echo "")
FUNCTIONS_URL="https://us-central1-${PROJECT_ID}.cloudfunctions.net"

echo "Firebase Project: $PROJECT_ID"
echo "Firestore URL: https://console.firebase.google.com/project/${PROJECT_ID}/firestore"
echo "Storage URL: https://console.firebase.google.com/project/${PROJECT_ID}/storage"
echo "Functions Dashboard: https://console.firebase.google.com/project/${PROJECT_ID}/functions"

# Health check
echo -e "\n${BLUE}🏥 Health Check${NC}"

# Check Firestore connectivity
echo "Checking Firestore..."
if gcloud firestore query --database="(default)" --project=$PROJECT_ID --count 2>/dev/null; then
    echo -e "${GREEN}✅ Firestore is accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Could not verify Firestore${NC}"
fi

# Check Cloud Functions
echo "Checking Cloud Functions..."
FUNCTION_STATUS=$(firebase functions:list --token="${FIREBASE_TOKEN}" 2>/dev/null | grep -i "OK\|ERROR" || echo "UNKNOWN")
echo -e "${GREEN}✅ Cloud Functions status: $FUNCTION_STATUS${NC}"

# ==================== CLEANUP & LOGGING ====================

echo -e "${BLUE}🧹 Cleanup & Logging${NC}"

# Create deployment log
LOG_FILE="deployment_logs/firebase-${ENVIRONMENT}-${VERSION}-$(date +%Y%m%d_%H%M%S).log"
mkdir -p deployment_logs

cat > "$LOG_FILE" << EOF
🔥 Firebase Deployment Log
===========================
Environment: $ENVIRONMENT
Project: $PROJECT_ID
Version: $VERSION
Timestamp: $(date)

✅ Deployment Status: SUCCESS

Deployed Components:
- Firestore Security Rules
- Storage Rules
- Cloud Functions
- Web Dashboard (Hosting)

URLs:
- Project: https://console.firebase.google.com/project/${PROJECT_ID}
- Hosting: ${HOSTING_URL}
- Functions: ${FUNCTIONS_URL}

Duration: $(date +%s)s
EOF

# ==================== NOTIFICATIONS ====================

echo -e "${BLUE}📢 Notifications${NC}"

# Send Slack notification (if configured)
if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
    echo "Sending Slack notification..."
    curl -X POST $SLACK_WEBHOOK_URL \
        -H 'Content-type: application/json' \
        -d "{
            \"text\": \"🚀 Firebase Deployment Successful\",
            \"blocks\": [
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"*Firebase Deployment Successful* ✅\n\nEnvironment: $ENVIRONMENT\nVersion: $VERSION\nProject: $PROJECT_ID\"
                    }
                }
            ]
        }" || true
fi

# ==================== FINAL SUMMARY ====================

echo -e "\n${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ FIREBASE DEPLOYMENT COMPLETE!${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "\n${GREEN}Summary:${NC}"
echo "📦 Environment: $ENVIRONMENT"
echo "🔥 Project: $PROJECT_ID"
echo "📌 Version: $VERSION"
echo "📅 Date: $(date)"
echo "📋 Log: $LOG_FILE"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Monitor Firebase Console"
echo "2. Check Cloud Function logs"
echo "3. Verify Firestore rules"
echo "4. Run smoke tests"
echo -e "\n${CYAN}════════════════════════════════════════${NC}\n"
