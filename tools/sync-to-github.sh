#!/bin/sh
# Makes the GitHub repository (origin) an exact copy of this local repository:
# same history on the current branch, same tags. It OVERWRITES what is on GitHub.
#
#   1. create the repository on GitHub (empty or existing), then:
#        git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
#   2. run:  tools/sync-to-github.sh
#
# Anything that exists only on GitHub (commits made there, other branches, tags)
# is lost from the git side. GitHub Releases, issues and the wiki are not git data
# and are left alone (delete old releases with:  gh release delete TAG --yes).
set -e
cd "$(dirname "$0")/.."

origin=$(git remote get-url origin 2>/dev/null) || { echo "No 'origin' remote. Run: git remote add origin <url>"; exit 1; }
branch=$(git rev-parse --abbrev-ref HEAD)
echo "Local branch : $branch ($(git rev-parse --short HEAD))"
echo "GitHub remote: $origin"
echo

git fetch origin --prune --no-tags 2>/dev/null || echo "(could not fetch - the GitHub repository may be empty)"
if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
    echo "Differences between GitHub's $branch and this one:"
    git diff --stat "origin/$branch" "$branch" | tail -15
    echo
fi

printf "Overwrite GitHub with this repository? Type 'yes' to continue: "
read -r answer
[ "$answer" = "yes" ] || { echo "Cancelled."; exit 1; }

git push --force origin "$branch"
git push --force origin --tags

echo
echo "Remote branches and tags that are not in this repository (delete them if you do not want them):"
git ls-remote --heads --tags origin | awk '{print $2}' | grep -v '\^{}$' | while read -r ref; do
    git show-ref --verify --quiet "$ref" || echo "  git push origin --delete ${ref#refs/*/}    # $ref"
done
echo "Done."
