#!/bin/sh
# Builds the sideload package: dist/SBWatch-v<major>.<minor>.<build>.zip
set -e
cd "$(dirname "$0")"
major=$(grep '^major_version=' manifest | cut -d= -f2)
minor=$(grep '^minor_version=' manifest | cut -d= -f2)
build=$(grep '^build_version=' manifest | cut -d= -f2 | sed 's/^0*//')
name="SBWatch-v${major}.${minor}.${build}.zip"
mkdir -p dist
rm -f dist/SBWatch*.zip
zip -qr "dist/$name" manifest source components images fonts -x '*.DS_Store'
echo "Built dist/$name"
