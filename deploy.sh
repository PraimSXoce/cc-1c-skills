#!/bin/bash
# Deploy 1C skills from repo to ~/.claude/skills/
# Copies only skills that exist in this repo, does not touch other skills.
#
# Usage:
#   ./deploy.sh          — copy repo → ~/.claude/skills/
#   ./deploy.sh --dry    — show what would be copied without doing it

REPO_SKILLS="$(cd "$(dirname "$0")" && pwd)/.claude/skills"
TARGET="$HOME/.claude/skills"
DRY=false

[[ "$1" == "--dry" ]] && DRY=true

if [ ! -d "$REPO_SKILLS" ]; then
  echo "ERROR: $REPO_SKILLS not found"
  exit 1
fi

mkdir -p "$TARGET"

updated=0
for dir in "$REPO_SKILLS"/*/; do
  name=$(basename "$dir")
  if $DRY; then
    echo "  $name/"
  else
    mkdir -p "$TARGET/$name"
    cp -r "$dir"* "$TARGET/$name/"
  fi
  ((updated++))
done

if $DRY; then
  echo "--- DRY RUN: $updated skills would be deployed to $TARGET"
else
  echo "Deployed $updated skills to $TARGET"
fi
