#!/bin/bash
set -e

# Seed baked skills, copy-if-missing (-L: dangling links may be valid on host)
SKILLS_DIR=/var/lib/claude-ephemeral/.claude/skills
if [ -d /usr/share/claude-skills ] && [ -w "$SKILLS_DIR" ]; then
  for s in /usr/share/claude-skills/*/; do
    [ -d "$s" ] || continue
    dest="$SKILLS_DIR/$(basename "$s")"
    [ -e "$dest" ] || [ -L "$dest" ] || cp -r "$s" "$dest"
  done
fi

exec "$@"
