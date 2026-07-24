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
    # Init hook: repos shipping .sandbox-init.sh (committed or not — the copy
    # takes the working tree as-is) run it once per fresh copy, non-fatal
    if [ -f "$dest/.sandbox-init.sh" ]; then
      if (cd "$dest" && bash -c '. "$HOME/.config/shellrc.sh"; bash .sandbox-init.sh') \
           > "$dest/.sandbox-init.log" 2>&1 </dev/null; then
        echo "seed: init $repo ok"
      else
        echo "seed: init $repo failed — see .sandbox-init.log in the repo copy" >&2
      fi
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

# Skills installed on the fly via the skills CLI (-a/-g/-y make it unattended);
# one run per line — `add` takes a single source repo, so skills from different
# repos can't share an invocation. Seeding above ran first, so a host skill
# with the same name overrides by claiming it. skills.sh exits 0 even when
# nothing installs — verify the file landed. Non-fatal: no network, no skill.
while read -r repo skill; do
  [ -e "$SKILLS_DIR/$skill" ] && continue
  if bash -c '. "$HOME/.config/shellrc.sh"
        npx -y skills@latest add "$1" --skill "$2" -a claude-code -g -y' \
       _ "$repo" "$skill" >/dev/null 2>&1 </dev/null \
     && [ -f "$SKILLS_DIR/$skill/SKILL.md" ]; then
    echo "skills: $skill installed from $repo"
  else
    echo "skills: $skill install failed — run \`npx skills add $repo --skill $skill\` manually" >&2
  fi
done <<'EOF'
https://github.com/ogulcancelik/herdr herdr
https://github.com/wshobson/agents typescript-advanced-types
EOF

# herdr headless server with a workspace per seeded repo; restarts restore
# from session.json, so only missing ones are created
if [ -n "${SANDBOX_REPOS:-}" ] && command -v herdr >/dev/null 2>&1; then
  if ! herdr workspace list >/dev/null 2>&1; then
    (herdr server >/dev/null 2>&1 &)
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      herdr workspace list >/dev/null 2>&1 && break
      sleep 0.5
    done
  fi
  existing="$(herdr workspace list 2>/dev/null || true)"
  for repo in $SANDBOX_REPOS; do
    [ -d "$HOME/Code/$repo" ] || continue
    case "$existing" in *"\"label\":\"$repo\""*) continue ;; esac
    herdr workspace create --cwd "$HOME/Code/$repo" --label "$repo" >/dev/null 2>&1 \
      && echo "herdr: workspace $repo" \
      || echo "herdr: workspace create failed for $repo" >&2
  done
fi

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
