#!/usr/bin/env bash
# (Re)generate CLAUDE_CODE_OAUTH_TOKEN in ../../.env. Launches a real, headed Chrome
# on this host (macOS or Linux), drives the claude.ai OAuth login, and asks for the
# code claude.com emails you. Headed because claude.ai's Cloudflare blocks
# headless/synthetic browsers.
#
#   ./get-token.sh                         # prompts for your email (hidden)
#   OAUTH_EMAIL=you@x.com ./get-token.sh   # or pass it via env (not argv)
set -euo pipefail
cd "$(dirname "$0")"

PORT="${CHROME_PORT:-9223}"
PROFILE="${CHROME_PROFILE:-$HOME/.cache/oauth-token-chrome}"
CDP="http://127.0.0.1:${PORT}"

# Email: prefer arg/env, else prompt hidden (kept out of argv, history and logs).
EMAIL="${1:-${OAUTH_EMAIL:-}}"
if [ -z "$EMAIL" ]; then
  read -rsp "claude.ai email (hidden): " EMAIL || true
  echo
fi
[ -n "$EMAIL" ] || { echo "email required (pass it or set OAUTH_EMAIL)" >&2; exit 1; }

if [ ! -d node_modules/playwright-core ]; then
  echo "· installing playwright-core…"
  npm install --no-audit --no-fund --silent
fi

# Chrome launcher for this OS (macOS .app, Linux flatpak, or a Linux binary).
if [ "$(uname -s)" = Darwin ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    [ -x "$c" ] && CHROME=("$c") && break
  done
elif flatpak info com.google.Chrome >/dev/null 2>&1; then
  CHROME=(flatpak run --filesystem="$PROFILE" com.google.Chrome)
else
  for c in google-chrome-stable google-chrome chromium chromium-browser; do
    command -v "$c" >/dev/null 2>&1 && CHROME=("$c") && break
  done
fi
[ "${CHROME:-}" ] || { echo "No Chrome/Chromium found on this host." >&2; exit 1; }
CHROME+=(--user-data-dir="$PROFILE" --remote-debugging-port="$PORT"
         --remote-debugging-address=127.0.0.1 --no-first-run
         --no-default-browser-check --disable-session-crashed-bubble about:blank)

# Linux without a display: run under a virtual one (xvfb). macOS always has a GUI.
PREFIX=()
if [ "$(uname -s)" != Darwin ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  command -v xvfb-run >/dev/null 2>&1 || {
    echo "No display and no xvfb-run. Install xvfb (dnf install xorg-x11-server-Xvfb) or use a display." >&2
    exit 1; }
  PREFIX=(xvfb-run -a)
fi

rm -rf "$PROFILE"; mkdir -p "$PROFILE"
"${PREFIX[@]}" "${CHROME[@]}" >/tmp/oauth-token-chrome.log 2>&1 &
CHROME_PID=$!
trap 'kill "$CHROME_PID" 2>/dev/null || true' EXIT

echo "· starting Chrome…"
for _ in $(seq 1 60); do curl -sf "$CDP/json/version" >/dev/null 2>&1 && break; sleep 0.5; done
curl -sf "$CDP/json/version" >/dev/null 2>&1 || {
  echo "Chrome CDP never came up (see /tmp/oauth-token-chrome.log)" >&2; exit 1; }

# Email via env (never argv), so it stays out of `ps`.
CHROME_CDP="$CDP" OAUTH_EMAIL="$EMAIL" node login.mjs
