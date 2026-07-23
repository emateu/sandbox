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

# jira-cli config regenerated from .env each recreate; non-fatal, and
# </dev/null so an unexpected prompt fails instead of hanging the boot
if [ -n "${JIRA_API_TOKEN:-}" ] && [ -n "${JIRA_SERVER:-}" ] && [ -n "${JIRA_LOGIN:-}" ] \
   && [ -n "${SANDBOX_JIRA_PROJECT:-}" ] && [ ! -f "$HOME/.config/.jira/.config.yml" ]; then
  if jira init --installation cloud --server "$JIRA_SERVER" --login "$JIRA_LOGIN" \
       --auth-type basic --project "$SANDBOX_JIRA_PROJECT" --board "${SANDBOX_JIRA_BOARD:-None}" \
       --force >/dev/null 2>&1 </dev/null; then
    echo "jira: config generated for $JIRA_SERVER"
  else
    echo "jira: init failed — run \`jira init\` manually" >&2
  fi
fi

# ssh sessions start with a clean env; persist the container's for shellrc
printenv | grep -E '^(CLAUDE_CODE_OAUTH_TOKEN|OAUTH_TOKEN_STORE|GH_TOKEN|GIT_USER_NAME|GIT_USER_EMAIL|JIRA_API_TOKEN|JIRA_SERVER|JIRA_LOGIN|SANDBOX_)' \
  | while IFS='=' read -r k v; do printf 'export %s=%q\n' "$k" "$v"; done \
  > "$HOME/.config/sandbox-env.sh"

# sshd; host keys persist in the tools/ssh mount so fingerprints survive rebuilds
if [ -d /mnt/ssh-host ]; then
  sudo test -f /mnt/ssh-host/ssh_host_ed25519_key \
    || sudo ssh-keygen -q -t ed25519 -N '' -f /mnt/ssh-host/ssh_host_ed25519_key
  sudo /usr/sbin/sshd -h /mnt/ssh-host/ssh_host_ed25519_key \
    || echo "sshd failed to start" >&2
fi

exec "$@"
