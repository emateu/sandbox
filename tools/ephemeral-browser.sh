#!/usr/bin/env bash
# Headed Chrome in a fresh temp profile (macOS or Linux), deleted on exit. Opens
# about:blank by default.
#
#   ./ephemeral-browser.sh                 # about:blank
#   ./ephemeral-browser.sh https://x.com   # or a URL
set -euo pipefail

URL="${1:-about:blank}"

mkdir -p "$HOME/.cache"
PROFILE="$(mktemp -d "$HOME/.cache/ephemeral-chrome.XXXXXX")"
trap 'rm -rf "$PROFILE"' EXIT

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

# Linux needs a display for a headed window; macOS always has a GUI.
if [ "$(uname -s)" != Darwin ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  echo "No display found — this opens a real browser window and needs one." >&2
  exit 1
fi

CHROME+=(--user-data-dir="$PROFILE" --no-first-run --no-default-browser-check
         --disable-session-crashed-bubble "$URL")

echo "· ephemeral Chrome — $PROFILE"
# Foreground: on close the script returns and the EXIT trap removes the profile.
"${CHROME[@]}"
