# Shared shell config, sourced from both .bashrc and .zshrc.

# Some host terminals lack terminfo entries here; fall back to a known-good
# value only then — a real TERM (xterm-ghostty etc.) carries the graphics
# capabilities herdr keys off
command -v infocmp >/dev/null 2>&1 && infocmp "$TERM" >/dev/null 2>&1 || export TERM=xterm-256color
export COLORTERM=truecolor

# ssh sessions get a clean env; the entrypoint persists the container's here
[ -f "$HOME/.config/sandbox-env.sh" ] && . "$HOME/.config/sandbox-env.sh"

# fnm
export PATH="$HOME/.local/share/fnm:$PATH"
if [ -n "$ZSH_VERSION" ]; then
  eval "$(fnm env --use-on-cd --shell zsh)"
else
  eval "$(fnm env --use-on-cd --shell bash)"
fi

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Claude Code lives in ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# no nonessential Anthropic traffic: claude sessions stay off claude.ai (no
# artifacts/telemetry either); local --resume unaffected
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Unattended flags; token refreshed from the mounted store when present.
claude() {
  local _t
  if [ -n "$OAUTH_TOKEN_STORE" ] && [ -f "$OAUTH_TOKEN_STORE" ]; then
    _t="$(node "$(dirname "$OAUTH_TOKEN_STORE")/refresh.mjs" --print 2>/dev/null)" \
      && [ -n "$_t" ] && export CLAUDE_CODE_OAUTH_TOKEN="$_t"
  fi
  IS_DEMO=0 command claude --dangerously-skip-permissions --effort high "$@"
}

# [hostname] prompt tag — the instance name under multi-tenant setups
# (zsh only; after the theme has set PROMPT)
if [ -n "$ZSH_VERSION" ] && [ -f /.dockerenv ]; then
  PROMPT="%F{243}[%m]%f ${PROMPT}"
fi
