# Shared shell config, sourced from both .bashrc and .zshrc.

# Some host terminals lack terminfo entries here; force known-good values.
export TERM=xterm-256color
export COLORTERM=truecolor

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

# Unattended flags; token refreshed from the mounted store when present.
claude() {
  local _t
  if [ -n "$OAUTH_TOKEN_STORE" ] && [ -f "$OAUTH_TOKEN_STORE" ]; then
    _t="$(node "$(dirname "$OAUTH_TOKEN_STORE")/refresh.mjs" --print 2>/dev/null)" \
      && [ -n "$_t" ] && export CLAUDE_CODE_OAUTH_TOKEN="$_t"
  fi
  IS_DEMO=0 command claude --dangerously-skip-permissions --effort max "$@"
}

# [sandbox] prompt tag (zsh only; after the theme has set PROMPT)
if [ -n "$ZSH_VERSION" ] && [ -f /.dockerenv ]; then
  PROMPT="%F{243}[sandbox]%f ${PROMPT}"
fi
