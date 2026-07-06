#!/bin/bash
set -e

# Git identity from .env
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Seed baked skills, copy-if-missing (-L: dangling links may be valid on host)
SKILLS_DIR="$HOME/.claude/skills"
if [ -d /usr/share/claude-skills ] && [ -w "$SKILLS_DIR" ]; then
  for s in /usr/share/claude-skills/*/; do
    [ -d "$s" ] || continue
    dest="$SKILLS_DIR/$(basename "$s")"
    [ -e "$dest" ] || [ -L "$dest" ] || cp -r "$s" "$dest"
  done
fi

exec "$@"
