#!/usr/bin/env bash
# Usage: ./deploy_hf.sh ["optional commit message"]
# Builds Flutter web locally then pushes backend + web to HF Spaces.
set -e

MSG=${1:-"deploy: update $(date '+%Y-%m-%d %H:%M')"}

# 1. Build Flutter web (empty CACHY_API_BASE = relative URLs = same-origin API)
echo "Building Flutter web..."
cd app
# --no-tree-shake-icons: keep full icon fonts so runtime-selected icons (e.g. the
# presenter glyph) render on the deploy instead of showing as blank boxes.
flutter build web --release --no-tree-shake-icons --dart-define=CACHY_API_BASE= 2>&1
cd ..

# 2. Sync build output into web_dist/
rm -rf web_dist
cp -r app/build/web web_dist

# 3. Create detached deployment commit so main stays clean
BRANCH=$(git branch --show-current)
trap 'git checkout --quiet "$BRANCH" 2>/dev/null || true' EXIT

git checkout --detach --quiet

git add backend/ Dockerfile README.md
git rm -r --cached web_dist/ 2>/dev/null || true
git add -f web_dist/

git diff --cached --quiet && echo "Nothing to deploy." && exit 0

git commit -m "$MSG"

# Push ONLY to HF using detached HEAD (GitHub stays free of built assets)
git push --force hf HEAD:main

echo ""
echo "Deployed → https://vatxzz-cachy.hf.space"
echo "(HF rebuilds Docker in ~2-3 min)"
