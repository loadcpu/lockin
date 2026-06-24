#!/bin/bash
set -e

APP="Lock In"
REPO="${LOCKIN_REPO:-loadcpu/screen-blocker}"
DIST_DIR=".build/dist"
STABLE_ZIP="$DIST_DIR/LockIn.zip"
BOLD='\033[1m'; GREEN='\033[0;32m'; RESET='\033[0m'

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>   e.g. ./release.sh 1"
    exit 1
fi
BUILD_NUMBER="${2:-${VERSION}}"
RELEASE_TAG="v${VERSION}"

echo "${BOLD}Building…${RESET}"
LOCKIN_VERSION="$VERSION" LOCKIN_BUILD="$BUILD_NUMBER" ./build.sh

echo "${BOLD}Packaging zip…${RESET}"
VERSIONED_ZIP="$DIST_DIR/LockIn-macOS-$RELEASE_TAG.zip"
mkdir -p "$DIST_DIR"
rm -f "$STABLE_ZIP" "$VERSIONED_ZIP"
ditto -c -k --sequesterRsrc --keepParent ".build/${APP}.app" "$STABLE_ZIP"
cp "$STABLE_ZIP" "$VERSIONED_ZIP"

SIZE=$(du -sh "$STABLE_ZIP" | cut -f1)
echo "  $(basename "$STABLE_ZIP") ready ($SIZE)"
echo "  $(basename "$VERSIONED_ZIP") ready"

echo "${BOLD}Creating GitHub release ${RELEASE_TAG}…${RESET}"
gh release create "$RELEASE_TAG" "$STABLE_ZIP" "$VERSIONED_ZIP" \
    --title "$RELEASE_TAG" \
    --notes "Download the attached \`LockIn.zip\` or install with: \`curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash\`"

echo ""
echo "${GREEN}✓ ${RELEASE_TAG} published.${RESET}"
echo "  Users can now install with:"
echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
