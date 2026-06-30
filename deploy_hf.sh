#!/usr/bin/env bash
# Usage: ./deploy_hf.sh ["optional commit message"]
# Builds Flutter web locally then pushes backend + web to HF Spaces.
set -e

MSG=${1:-"deploy: update $(date '+%Y-%m-%d %H:%M')"}

# 1. Build Flutter web (empty CACHY_API_BASE = relative URLs = same-origin API)
echo "Building Flutter web..."
cd app
flutter build web --release --dart-define=CACHY_API_BASE= 2>&1
cd ..

# 2. Sync build output into web_dist/
rm -rf web_dist
cp -r app/build/web web_dist

# 3. Stage files:
#    - plain git add for tracked dirs (gitignore still protects .env / .venv)
#    - unstage then re-add web_dist so git-lfs picks up binaries correctly
git add backend/ Dockerfile README.md
git rm -r --cached web_dist/ 2>/dev/null || true
git add -f web_dist/

git diff --cached --quiet && echo "Nothing to deploy." && exit 0

git commit -m "$MSG"

# Push ONLY to HF (GitHub stays free of built assets)
git push hf main

echo ""
echo "Deployed → https://vatxzz-cachy.hf.space"
echo "(HF rebuilds Docker in ~2-3 min)"
