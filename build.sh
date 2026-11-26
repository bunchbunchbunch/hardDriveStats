#!/bin/bash
# Builds Drive Stats.app into build/. With --install, also copies it to /Applications.
# Set DRIVESTATS_TEAM to your Apple Developer team ID to sign with your Apple Development
# certificate, so a Full Disk Access grant survives rebuilds. Otherwise it signs ad hoc.
set -euo pipefail
cd "$(dirname "$0")"
SIGNING=()
if [ -n "${DRIVESTATS_TEAM:-}" ]; then
  SIGNING=(DEVELOPMENT_TEAM="$DRIVESTATS_TEAM" CODE_SIGN_IDENTITY="Apple Development")
fi
xcodegen generate >/dev/null
xcodebuild -project DriveStats.xcodeproj -scheme DriveStats -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/dd ${SIGNING[@]+"${SIGNING[@]}"} build 2>&1 \
  | grep -E 'error:|warning: |\*\* BUILD' || true
APP="build/dd/Build/Products/Release/Drive Stats.app"
[ -d "$APP" ] || { echo "Build failed"; exit 1; }
rm -rf "build/Drive Stats.app"
cp -R "$APP" build/
echo "Built: $PWD/build/Drive Stats.app"
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Drive Stats.app"
  cp -R "build/Drive Stats.app" /Applications/
  echo "Installed: /Applications/Drive Stats.app"
fi
