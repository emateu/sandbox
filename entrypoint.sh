#!/bin/bash
set -e

# Git identity from .env
if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Seed repos into ~/Code, copy-if-absent: restarts keep work in progress,
# recreating the container starts from a fresh copy
if [ -n "${SANDBOX_REPOS:-}" ] && [ -d /mnt/seed ]; then
  for repo in $SANDBOX_REPOS; do
    src="/mnt/seed/$repo"
    dest="$HOME/Code/$repo"
    if [ ! -d "$src" ]; then
      echo "seed: ~/Code/$repo not found on the host — check SANDBOX_REPOS" >&2
      continue
    fi
    [ -e "$dest" ] && continue
    excludes=()
    for x in ${SANDBOX_COPY_EXCLUDES:-}; do
      excludes+=("--exclude=$x")
    done
    # Stage + rename: a copy killed halfway is retried on the next start
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest.seeding"
    rsync -a "${excludes[@]}" "$src/" "$dest.seeding/"
    mv "$dest.seeding" "$dest"
    echo "seed: copied $repo"
    # Multi-account ssh aliases (git@github.com-work:...) have no key in here;
    # rewrite to https so gh's PAT credential helper applies
    if [ -e "$dest/.git" ]; then
      for remote in $(git -C "$dest" remote); do
        url="$(git -C "$dest" remote get-url "$remote")"
        case "$url" in
          git@github.com-*:*)
            git -C "$dest" remote set-url "$remote" "https://github.com/${url#git@github.com-*:}"
            echo "seed: $repo remote '$remote' rewritten to https"
            ;;
        esac
      done
    fi
  done
fi

# Seed skills, copy-if-missing: host-mounted first — they win name conflicts —
# then baked (-L: dangling links may be valid on host)
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"
for src_root in /mnt/skills /usr/share/claude-skills; do
  [ -d "$src_root" ] || continue
  for s in "$src_root"/*/; do
    [ -d "$s" ] || continue
    dest="$SKILLS_DIR/$(basename "$s")"
    [ -e "$dest" ] || [ -L "$dest" ] || cp -r "$s" "$dest"
  done
done

exec "$@"
