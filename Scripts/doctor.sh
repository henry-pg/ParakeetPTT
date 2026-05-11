#!/usr/bin/env bash
set -euo pipefail

echo "Swift:"
swift --version

echo
echo "SwiftPM:"
swift package --version

echo
echo "Foundation import:"
if swift -e 'import Foundation; print("ok")' >/tmp/parakeet-ptt-foundation-check.log 2>&1; then
  cat /tmp/parakeet-ptt-foundation-check.log
else
  cat /tmp/parakeet-ptt-foundation-check.log
  echo
  echo "Swift cannot import Foundation. Reinstall or update Xcode Command Line Tools before building."
  exit 1
fi

echo
echo "Package manifest:"
swift package describe >/tmp/parakeet-ptt-package-check.log
cat /tmp/parakeet-ptt-package-check.log
