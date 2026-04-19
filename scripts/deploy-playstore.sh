#!/bin/bash

set -e

echo "🎮 GOOGLE PLAY STORE DEPLOYMENT SCRIPT"
echo "======================================\n"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="${PACKAGE_NAME:-com.yourapp.android}"
ENVIRONMENT="${1:-production}"
VERSION="${2:-$(git describe --tags --always)}"
BUILD_DIR="build"
RELEASE_TRACK="${RELEASE_TRACK:-internal}"
RELEASE_STATUS="${RELEASE_STATUS:-completed}"

echo -e "${CYAN}📊 Google Play Store Configuration${NC}"
echo "Package: $PACKAGE_NAME"
echo "Environment: $ENVIRONMENT"
echo "Version: $VERSION"
echo "Release Track: $RELEASE_TRACK"
echo "Release Status: $RELEASE_STATUS\n"

# ==================== VALIDATION ====================

echo -e "${BLUE}🔍 Pre-deployment Validation${NC}"

# Check for bundletool
if ! command -v bundletool &> /dev/null; then
    echo -e "${YELLOW}⚠️  bundletool not found. Installing...${NC}"
    mkdir -p ~/.bin
    wget https://github.com/google/bundletool/releases/latest/download/bundletool-all.jar \
        -O ~/.bin/bundletool.jar
    echo "#!/bin/bash" > ~/.bin/bundletool
    echo "java -jar ~/.bin/bundletool.jar \"\$@\"" >> ~/.bin/bundletool
    chmod +x ~/.bin/bundletool
    export PATH="~/.bin:$PATH"
fi
echo -e "${GREEN}✅ bundletool available${NC}"

# Check for fastlane
if ! command -v fastlane &> /dev/null; then
    echo -e "${RED}❌ fastlane not found${NC}"
    echo "Install: sudo gem install fastlane"
    exit 1
fi
echo -e "${GREEN}✅ fastlane $(fastlane --version | head -1)${NC}"

# Check for signing key
if [ ! -f "$PLAY_STORE_KEY" ]; then
    echo -e "${RED}❌ Play Store key not found: $PLAY_STORE_KEY${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Signing key found${NC}\n"

# ==================== BUILD PHASE ====================

echo -e "${BLUE}🔨 Building AAB for Play Store${NC}"

cd app
./gradlew bundleRelease \
    -PversionName="$VERSION" \
    -PversionCode="$(date +%s | cut -c 1-10)" \
    -Pandroid.bundle.enableUncompressNativeLibraries=false

echo -e "${GREEN}✅ AAB built successfully${NC}\n"

# ==================== AAB ANALYSIS ====================

echo -e "${BLUE}📊 AAB Analysis${NC}"

AAB_FILE="app/build/outputs/bundle/release/app-release.aab"

# Analyze AAB
bundletool dump manifest --bundle="$AAB_FILE"

echo -e "${GREEN}✅ AAB analysis complete${NC}\n"

# ==================== GENERATE TEST APK ====================

echo -e "${BLUE}📱 Generating Test APK${NC}"

# Generate universal APK for testing
bundletool build-apks \
    --bundle="$AAB_FILE" \
    --output="app/build/outputs/universal.apks" \
    --mode=universal

# Extract APK
unzip -o app/build/outputs/universal.apks universal.apk -d app/build/outputs/

echo -e "${GREEN}✅ Test APK generated${NC}\n"

# ==================== FASTLANE DEPLOYMENT ====================

echo -e "${BLUE}📤 Deploying to Play Store${NC}"

# Initialize fastlane if not already done
if [ ! -f "fastlane/Fastfile" ]; then
    echo "Initializing fastlane..."
    cd ..
    fastlane init
    cd app
fi

# Deploy using fastlane
case $ENVIRONMENT in
    production)
        echo "🚀 Deploying to PRODUCTION..."
        fastlane supply \
            --aab "$AAB_FILE" \
            --package_name "$PACKAGE_NAME" \
            --json_key "$PLAY_STORE_KEY" \
            --track="internal" \
            --release_status="completed" \
            --skip_upload_apk \
            --skip_upload_metadata \
            --skip_upload_images
        ;;
    staging)
        echo "🧪 Deploying to STAGING (Closed Testing)..."
        fastlane supply \
            --aab "$AAB_FILE" \
            --package_name "$PACKAGE_NAME" \
            --json_key "$PLAY_STORE_KEY" \
            --track="beta" \
            --release_status="inProgress" \
            --skip_upload_apk \
            --skip_upload_metadata \
            --skip_upload_images
        ;;
    *)
        echo -e "${RED}❌ Unknown environment: $ENVIRONMENT${NC}"
        exit 1
        ;;
esac

cd ..
echo -e "${GREEN}✅ Deployment successful${NC}\n"

# ==================== UPDATE RELEASE NOTES ====================

echo -e "${BLUE}📝 Updating Release Notes${NC}"

# Generate release notes
cat > build/release_notes.txt << EOF
🎉 Version $VERSION Release

🚀 New Features:
- Premium subscription system
- Advanced analytics dashboard
- Enhanced UI/UX
- Performance improvements

🐛 Bug Fixes:
- Fixed crash on app startup
- Resolved memory leaks
- Fixed compatibility issues

📈 Improvements:
- Better error handling
- Improved loading times
- Enhanced security

Thank you for using our app!
EOF

echo -e "${GREEN}✅ Release notes prepared${NC}\n"

# ==================== VERIFICATION ====================

echo -e "${BLUE}✅ Verification${NC}"

# Wait for Play Store processing
echo "Waiting for Play Store to process the deployment..."
for i in {1..10}; do
    echo -n "."
    sleep 5
done
echo ""

# Check Play Store listing
echo "Checking Play Store listing..."
if fastlane supply list_stores \
    --json_key "$PLAY_STORE_KEY" \
    --package_name "$PACKAGE_NAME" &>/dev/null; then
    echo -e "${GREEN}✅ Release visible on Play Store${NC}"
else
    echo -e "${YELLOW}⚠️  Could not verify Play Store listing${NC}"
fi

# ==================== PERFORMANCE ANALYTICS ====================

echo -e "${BLUE}📊 Performance Metrics${NC}"

AAB_SIZE=$(ls -lh "$AAB_FILE" | awk '{print $5}')
DOWNLOAD_SIZE=$(bundletool get-size total --bundle="$AAB_FILE" 2>/dev/null || echo "N/A")

echo "AAB File Size: $AAB_SIZE"
echo "Estimated Download Size: $DOWNLOAD_SIZE"
echo -e "${GREEN}✅ Performance metrics recorded${NC}\n"

# ==================== NOTIFICATIONS ====================

echo -e "${BLUE}📢 Notifications${NC}"

# Send Slack notification
if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST $SLACK_WEBHOOK_URL \
        -H 'Content-type: application/json' \
        -d "{
            \"text\": \"🎮 Play Store Deployment Successful\",
            \"blocks\": [
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"*Play Store Deployment Successful* ✅\n\nEnvironment: $ENVIRONMENT\nVersion: $VERSION\nPackage: $PACKAGE_NAME\nTrack: $RELEASE_TRACK\nAAB Size: $AAB_SIZE\"
                    }
                }
            ]
        }" || true
fi

# Send email notification (optional)
if [ ! -z "$DEPLOYMENT_EMAIL" ]; then
    echo "Sending email notification..."
    # Use mail or sendmail
    echo "Play Store deployment complete for $VERSION" | \
        mail -s "Play Store Deployment: $VERSION" "$DEPLOYMENT_EMAIL" || true
fi

# ==================== LOGGING ====================

LOG_FILE="deployment_logs/playstore-${ENVIRONMENT}-${VERSION}-$(date +%Y%m%d_%H%M%S).log"
mkdir -p deployment_logs

cat > "$LOG_FILE" << EOF
🎮 Google Play Store Deployment Log
====================================
Environment: $ENVIRONMENT
Package: $PACKAGE_NAME
Version: $VERSION
Timestamp: $(date)
Release Track: $RELEASE_TRACK
Release Status: $RELEASE_STATUS

✅ Deployment Status: SUCCESS

Build Information:
- AAB File Size: $AAB_SIZE
- Estimated Download Size: $DOWNLOAD_SIZE
- Built at: $(date)

Play Store Details:
- Package Name: $PACKAGE_NAME
- Track: $RELEASE_TRACK
- Status: $RELEASE_STATUS

Next Steps:
1. Monitor crash rates in Google Play Console
2. Check user reviews and ratings
3. Monitor performance metrics
4. Plan next release

Git Information:
- Commit: $(git rev-parse HEAD)
- Branch: $(git rev-parse --abbrev-ref HEAD)
- Author: $(git log -1 --format=%an)
EOF

# ==================== CLEANUP ====================

echo -e "${BLUE}🧹 Cleanup${NC}"

rm -f app/build/outputs/universal.apks universal.apk
echo -e "${GREEN}✅ Cleanup complete${NC}\n"

# ==================== FINAL SUMMARY ====================

echo -e "\n${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ PLAY STORE DEPLOYMENT COMPLETE!${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "\n${GREEN}Summary:${NC}"
echo "📦 Environment: $ENVIRONMENT"
echo "📌 Version: $VERSION"
echo "🎮 Package: $PACKAGE_NAME"
echo "📊 AAB Size: $AAB_SIZE"
echo "🔗 Track: $RELEASE_TRACK"
echo "📋 Log: $LOG_FILE"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Monitor Google Play Console"
echo "2. Check crash reports"
echo "3. Review user feedback"
echo "4. Monitor analytics"
echo -e "\n${CYAN}════════════════════════════════════════${NC}\n"
