#!/bin/sh
# Publishes a GitHub release for the version in the manifest:
#   builds the zip, generates release notes from the commits since the last tag,
#   tags the commit, pushes, and creates the release with the zip attached.
#
# Needs the GitHub CLI, logged in once with:   gh auth login
# Usage:  tools/release.sh        (bump major/minor/build_version in `manifest` and commit first)
set -e
cd "$(dirname "$0")/.."

major=$(grep '^major_version=' manifest | cut -d= -f2)
minor=$(grep '^minor_version=' manifest | cut -d= -f2)
build=$(grep '^build_version=' manifest | cut -d= -f2 | sed 's/^0*//')
ver="v${major}.${minor}.${build}"

if [ -n "$(git status --porcelain)" ]; then echo "Commit your changes first."; exit 1; fi
if git rev-parse -q --verify "refs/tags/$ver" >/dev/null; then
    echo "Tag $ver already exists - bump the version in the manifest and commit."; exit 1
fi

./build.sh
tools/release-notes.sh "$ver" > dist/RELEASE_NOTES.md
echo "---- release notes ----"; cat dist/RELEASE_NOTES.md; echo "-----------------------"

git tag -a "$ver" -m "SBWatch $ver"
git push origin HEAD "$ver"
gh release create "$ver" "dist/SBWatch-$ver.zip" --title "SBWatch $ver" --notes-file dist/RELEASE_NOTES.md
echo "Released $ver"
