#!/usr/bin/env bash
# Check the host is ready to build: docker, .env, uid/gid, mounts, credentials.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"
errors=0
warns=0

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
yell() { printf '\033[33m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }

err()  { red  "  ERROR  $*"; errors=$((errors + 1)); }
warn() { yell "  WARN   $*"; warns=$((warns + 1)); }
ok()   { grn  "  ok     $*"; }

echo "preflight: $OS, repo at $REPO"
echo

# --- .env exists --------------------------------------------------------------
ENV_FILE="$REPO/.env"
if [ ! -f "$ENV_FILE" ]; then
  err ".env missing — run: cp .env.example .env, fill it in, then rerun preflight"
  echo
  red "preflight failed: $errors error(s)"
  exit 1
fi

# Not a dotenv parser: last raw assignment wins, and an exported shell variable
# takes precedence over .env — the order Compose itself uses.
best_effort_value() {
  local key="$1"
  if printenv "$key" >/dev/null 2>&1; then
    printenv "$key"
    return
  fi
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "=" {
      sub("^[[:space:]]*" key "=", "")
      value = $0
    }
    END { if (value != "") printf "%s", value }
  ' "$ENV_FILE"
}

yaml_value() {
  local section="$1" indent="$2" key="$3"
  awk -v section="$section" -v indent="$indent" -v key="$key" '
    $0 == section { inside = 1; next }
    inside && index($0, indent) != 1 { exit }
    inside && index($0, indent key ":") == 1 {
      sub("^" indent key ":[[:space:]]*", "")
      if ($0 ~ /^".*"$/) { sub(/^"/, ""); sub(/"$/, "") }
      else if ($0 ~ /^\047.*\047$/) {
        sub(/^\047/, ""); sub(/\047$/, ""); gsub(/\047\047/, "\047")
      }
      print
      exit
    }
  '
}

load_best_effort_values() {
  E_UID="$(best_effort_value HOST_UID)"
  E_GID="$(best_effort_value HOST_GID)"
  E_USER="$(best_effort_value USERNAME)"
  TOKEN="$(best_effort_value CLAUDE_CODE_OAUTH_TOKEN)"
  GH_TOKEN_VALUE="$(best_effort_value GH_TOKEN)"
  GIT_EMAIL_VALUE="$(best_effort_value GIT_USER_EMAIL)"
}

# --- docker reachable + Compose's effective configuration --------------------
compose_ready=0
if ! command -v docker >/dev/null 2>&1; then
  err "docker not on PATH"
elif ! docker info >/dev/null 2>&1; then
  err "docker daemon not reachable (is Docker Desktop / the service running?)"
else
  ok "docker daemon reachable"
  compose_ready=1
fi

values_authoritative=0
if [ "$compose_ready" -eq 1 ]; then
  if COMPOSE_JSON="$(docker compose config --format json 2>/dev/null)"; then
    if command -v jq >/dev/null 2>&1; then
      if E_UID="$(printf '%s' "$COMPOSE_JSON" | jq -er '.services.sandbox.build.args.HOST_UID | tostring')" &&
         E_GID="$(printf '%s' "$COMPOSE_JSON" | jq -er '.services.sandbox.build.args.HOST_GID | tostring')" &&
         E_USER="$(printf '%s' "$COMPOSE_JSON" | jq -er '.services.sandbox.build.args.USERNAME | tostring')" &&
         TOKEN="$(printf '%s' "$COMPOSE_JSON" | jq -r '.services.sandbox.environment.CLAUDE_CODE_OAUTH_TOKEN // "" | tostring')" &&
         GH_TOKEN_VALUE="$(printf '%s' "$COMPOSE_JSON" | jq -r '.services.sandbox.environment.GH_TOKEN // "" | tostring')" &&
         GIT_EMAIL_VALUE="$(printf '%s' "$COMPOSE_JSON" | jq -r '.services.sandbox.environment.GIT_USER_EMAIL // "" | tostring')"; then
        values_authoritative=1
      else
        err "could not read sandbox build args from Compose's rendered configuration"
      fi
    elif COMPOSE_TEXT="$(docker compose config 2>/dev/null)"; then
      E_UID="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '      args:' '        ' HOST_UID)"
      E_GID="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '      args:' '        ' HOST_GID)"
      E_USER="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '      args:' '        ' USERNAME)"
      TOKEN="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '    environment:' '      ' CLAUDE_CODE_OAUTH_TOKEN)"
      GH_TOKEN_VALUE="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '    environment:' '      ' GH_TOKEN)"
      GIT_EMAIL_VALUE="$(printf '%s\n' "$COMPOSE_TEXT" | yaml_value '    environment:' '      ' GIT_USER_EMAIL)"
      values_authoritative=1
      warn "jq not found; read effective values from Compose's rendered YAML"
    else
      err "docker compose config rendered JSON but its text fallback failed"
    fi
  else
    err "docker compose config could not resolve the environment — fill HOST_UID, HOST_GID, and USERNAME, then rerun preflight"
  fi
fi

if [ "$values_authoritative" -eq 0 ]; then
  load_best_effort_values
  warn "using a best-effort .env read with exported shell-variable precedence; Compose values could not be verified"
else
  ok "effective values resolved by docker compose config"
fi

# --- required build args ------------------------------------------------------
for pair in "HOST_UID:$E_UID" "HOST_GID:$E_GID" "USERNAME:$E_USER"; do
  k="${pair%%:*}"; v="${pair#*:}"
  [ -n "$v" ] || err "$k is unset — set it in .env or export it in the shell"
done

for pair in "HOST_UID:$E_UID" "HOST_GID:$E_GID"; do
  k="${pair%%:*}"; v="${pair#*:}"
  if [ -n "$v" ] && ! [[ "$v" =~ ^[0-9]+$ ]]; then
    err "$k='$v' is not numeric"
  fi
done

if [ -n "$E_UID" ] && [ -n "$E_GID" ] && [ -n "$E_USER" ]; then
  ok "configured container user: HOST_UID=$E_UID HOST_GID=$E_GID USERNAME=$E_USER"
fi

# --- ids actually match the host ----------------------------------------------
H_UID="$(id -u)"; H_GID="$(id -g)"; H_USER="$(id -un)"

# An unset var already errored above; skip it here rather than report it twice.
case "$OS" in
  Linux)
    # Native docker: these ids own whatever the container writes into a bind mount.
    [ -z "$E_UID" ] || [ "$E_UID" = "$H_UID" ] || err "HOST_UID=$E_UID but you are uid $H_UID — bind-mounted files will be owned by uid $E_UID"
    [ -z "$E_GID" ] || [ "$E_GID" = "$H_GID" ] || err "HOST_GID=$E_GID but you are gid $H_GID — bind-mounted files will be owned by gid $E_GID"
    ;;
  Darwin)
    # Docker Desktop remaps mount ownership, so a mismatch only costs portability.
    [ -z "$E_UID" ] || [ "$E_UID" = "$H_UID" ] || warn "HOST_UID=$E_UID but you are uid $H_UID (Docker Desktop remaps bind-mount ownership)"
    [ -z "$E_GID" ] || [ "$E_GID" = "$H_GID" ] || warn "HOST_GID=$E_GID but you are gid $H_GID (Docker Desktop remaps bind-mount ownership)"
    ;;
  *)
    [ -z "$E_UID" ] || [ "$E_UID" = "$H_UID" ] || warn "HOST_UID=$E_UID but you are uid $H_UID — ownership behavior is unknown on $OS"
    [ -z "$E_GID" ] || [ "$E_GID" = "$H_GID" ] || warn "HOST_GID=$E_GID but you are gid $H_GID — ownership behavior is unknown on $OS"
    ;;
esac
[ -z "$E_USER" ] || [ "$E_USER" = "$H_USER" ] || warn "USERNAME=$E_USER but you are '$H_USER' — container \$HOME will be /home/$E_USER"

# --- mount sources exist ------------------------------------------------------
# Docker creates a missing bind source as an empty root-owned dir, shadowing the path.
for d in "$HOME/Code" "$HOME/.claude/skills" "$HOME/.agents"; do
  if [ -e "$d" ]; then
    ok "mount source exists: $d"
  else
    warn "mount source missing: $d — docker will create it root-owned. mkdir -p '$d'"
  fi
done

# --- credentials --------------------------------------------------------------
STORE="$REPO/tools/oauth-token/.tokens.json"
if [ -z "$TOKEN" ] && [ ! -f "$STORE" ]; then
  warn "no CLAUDE_CODE_OAUTH_TOKEN and no oauth-token store — \`claude\` won't authenticate"
else
  ok "claude credentials present"
fi

[ -n "$GH_TOKEN_VALUE" ] || warn "GH_TOKEN unset — gh and git pushes to GitHub will fail"
[ -n "$GIT_EMAIL_VALUE" ] || warn "GIT_USER_EMAIL unset — commits from the sandbox will be unattributed"

# --- verdict ------------------------------------------------------------------
echo
if [ "$errors" -gt 0 ]; then
  red "preflight failed: $errors error(s), $warns warning(s)"
  exit 1
fi
if [ "$warns" -gt 0 ]; then
  yell "preflight passed with $warns warning(s)"
else
  grn "preflight passed"
fi
