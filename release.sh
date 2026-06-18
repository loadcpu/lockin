#!/bin/bash
set -e

APP="Lock In"
ZIP="LockIn.zip"
BOLD='\033[1m'; GREEN='\033[0;32m'; RESET='\033[0m'

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version>   e.g. ./release.sh 1.0.0"
    exit 1
fi
BUILD_NUMBER="${2:-${VERSION}}"

echo "${BOLD}Building…${RESET}"
LOCKIN_VERSION="$VERSION" LOCKIN_BUILD="$BUILD_NUMBER" ./build.sh

echo "${BOLD}Packaging zip…${RESET}"
rm -f "$ZIP"
(cd .build && zip -qr "../$ZIP" "${APP}.app")

SIZE=$(du -sh "$ZIP" | cut -f1)
echo "  $ZIP ready ($SIZE)"

echo "${BOLD}Creating GitHub release v${VERSION}…${RESET}"
gh release create "v${VERSION}" "$ZIP" \
    --title "v${VERSION}" \
    --notes "Download the attached \`LockIn.zip\` or install with: \`curl -fsSL https://raw.githubusercontent.com/loadcpu/screen-blocker/main/install.sh | bash\`"

rm -f "$ZIP"

echo ""
echo "${GREEN}✓ v${VERSION} published.${RESET}"
echo "  Users can now install with:"
echo "  curl -fsSL https://raw.githubusercontent.com/loadcpu/screen-blocker/main/install.sh | bash"
