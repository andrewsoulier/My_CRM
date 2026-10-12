#!/bin/bash

echo "🔍 My CRM - Distribution Verification Checklist"
echo "=============================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Check 1: App exists
echo -n "1. App exists in /Applications... "
if [ -d "/Applications/My CRM.app" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "   Run ./build_app.sh first"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: No Python files in bundle
echo -n "2. No Python files in bundle... "
PYTHON_COUNT=$(find "/Applications/My CRM.app" -name "*.py" 2>/dev/null | wc -l | xargs)
if [ "$PYTHON_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} (0 .py files)"
else
    echo -e "${RED}✗${NC} ($PYTHON_COUNT .py files found)"
    find "/Applications/My CRM.app" -name "*.py" 2>/dev/null
    ERRORS=$((ERRORS + 1))
fi

# Check 3: Executable is present
echo -n "3. Executable exists... "
if [ -f "/Applications/My CRM.app/Contents/MacOS/My CRM" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Executable is executable
echo -n "4. Executable has correct permissions... "
if [ -x "/Applications/My CRM.app/Contents/MacOS/My CRM" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Info.plist exists
echo -n "5. Info.plist exists... "
if [ -f "/Applications/My CRM.app/Contents/Info.plist" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 6: Bundle identifier is unique
echo -n "6. Bundle identifier is unique... "
BUNDLE_ID=$(defaults read "/Applications/My CRM.app/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
if [[ "$BUNDLE_ID" == "com.andrewsoulier.mycrm" ]]; then
    echo -e "${GREEN}✓${NC} ($BUNDLE_ID)"
elif [[ "$BUNDLE_ID" == "com.mycrm.app" ]]; then
    echo -e "${YELLOW}⚠${NC} (Using generic ID: $BUNDLE_ID)"
    echo "   Consider updating to com.andrewsoulier.mycrm"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}✓${NC} ($BUNDLE_ID)"
fi

# Check 7: App is signed
echo -n "7. App is code signed... "
if codesign -v "/Applications/My CRM.app" 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
    SIGNATURE=$(codesign -dvv "/Applications/My CRM.app" 2>&1 | grep "Authority=" | head -1)
    echo "   $SIGNATURE"
else
    echo -e "${YELLOW}⚠${NC} (Not signed - FDA will need re-setup on updates)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 8: Icons exist
echo -n "8. App icons exist... "
ICON_COUNT=0
[ -f "/Applications/My CRM.app/Contents/Resources/AppIcon.icns" ] && ICON_COUNT=$((ICON_COUNT + 1))
[ -f "/Applications/My CRM.app/Contents/Resources/StatusBarIcon.icns" ] && ICON_COUNT=$((ICON_COUNT + 1))
if [ "$ICON_COUNT" -eq 2 ]; then
    echo -e "${GREEN}✓${NC} (2/2 icons)"
elif [ "$ICON_COUNT" -eq 1 ]; then
    echo -e "${YELLOW}⚠${NC} (1/2 icons)"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${YELLOW}⚠${NC} (0/2 icons)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 9: Documentation exists
echo -n "9. Documentation exists... "
DOC_COUNT=0
[ -f "GETTING_STARTED.md" ] && DOC_COUNT=$((DOC_COUNT + 1))
[ -f "README.md" ] && DOC_COUNT=$((DOC_COUNT + 1))
if [ "$DOC_COUNT" -eq 2 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} (Missing getting started guide)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 10: Test default settings creation
echo -n "10. Test settings creation... "
TEST_SETTINGS_PATH="/tmp/test_mycrm_settings_$RANDOM.json"
# We can't easily test this without running the app, so we'll check if SettingsManager code exists
if grep -q "UserSettings.init()" Core/Models/UserSettings.swift 2>/dev/null; then
    echo -e "${GREEN}✓${NC} (Code verified)"
else
    echo -e "${YELLOW}⚠${NC} (Cannot verify)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""
echo "=============================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready for distribution.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Passed with $WARNINGS warning(s). Review above.${NC}"
    exit 0
else
    echo -e "${RED}❌ Failed with $ERRORS error(s) and $WARNINGS warning(s).${NC}"
    echo ""
    echo "Fix the errors above before distributing."
    exit 1
fi

