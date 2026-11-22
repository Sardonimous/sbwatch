#!/bin/sh
# Prints release notes (Markdown) for everything committed since the latest tag.
# Each commit becomes a "###" heading (its subject) followed by its description.
cd "$(dirname "$0")/.."
prev=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -n "$prev" ]; then range="$prev..HEAD"; else range="HEAD"; fi

echo "## What's new"
echo
git log --reverse --no-merges --format='%H' $range | while read -r h; do
    echo "### $(git log -1 --format=%s "$h")"
    git log -1 --format=%b "$h" | grep -v '^Co-Authored-By' | sed '/^[[:space:]]*$/d'
    echo
done

# link to the full comparison on GitHub, when the remote is a GitHub URL
url=$(git remote get-url origin 2>/dev/null | sed -e 's#git@github.com:#https://github.com/#' -e 's#\.git$##')
case "$url" in
    https://github.com/*)
        if [ -n "$prev" ]; then echo "**Full changelog:** $url/compare/$prev...${1:-HEAD}"; fi ;;
esac
