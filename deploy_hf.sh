#!/usr/bin/env bash
# Usage: ./deploy_hf.sh ["optional commit message"]
set -e

MSG=${1:-"deploy: backend update $(date '+%Y-%m-%d %H:%M')"}

git add backend/ Dockerfile README.md
git diff --cached --quiet && echo "Nothing to deploy." && exit 0

git commit -m "$MSG"
git push hf main

echo ""
echo "Deployed → https://vatxzz-cachy.hf.space"
echo "(HF rebuilds Docker in ~2-3 min)"
