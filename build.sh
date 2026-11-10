#!/bin/sh
# Builds the sideload package: dist/SBWatch.zip
set -e
cd "$(dirname "$0")"
mkdir -p dist
rm -f dist/SBWatch.zip
zip -qr dist/SBWatch.zip manifest source components images -x '*.DS_Store'
echo "Built dist/SBWatch.zip"
