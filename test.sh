#!/bin/bash
# Unit tests for the scanner, recommender, Downloads review, Trash, and history store.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate >/dev/null
xcodebuild -project DriveStats.xcodeproj -scheme DriveStats -destination 'platform=macOS' \
  -derivedDataPath build/dd-test test 2>&1 \
  | grep -E 'error:|warning: |✔|✘|Test run|\*\* TEST'
