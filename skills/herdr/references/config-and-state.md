# herdr configuration & session-state details

Sources: https://herdr.dev/docs/configuration/ and https://herdr.dev/docs/session-state/ (re-fetch if an option seems missing — herdr moves fast).

## Config file

`~/.config/herdr/config.toml`. Get defaults with `herdr --default-config`. Apply most changes live with `herdr server reload-config` (some startup-only settings need pane recreation). Logs: `~/.config/herdr/herdr.log`, `herdr-client.log`, `herdr-server.log`.

```toml
onboarding = false            # skip first-run setup

[update]
channel = "stable"            # or "preview"
version_check = true
manifest_check = true         # remote agent-detection manifest updates

[terminal]
default_shell = "zsh"
shell_mode = "auto"           # auto | login | non_login
new_cwd = "follow"            # follow | home | current

[worktrees]
directory = "~/.herdr/worktrees"   # checkouts: <dir>/<repo>/<branch-slug>

[remote]
manage_ssh_config = true      # temp SSH config with keepalives

[keys]
prefix = "ctrl+b"
# new_tab = "prefix+c", focus_pane_left = "prefix+h", split_vertical = "prefix+v",
# copy_mode = "prefix+[", zoom = "prefix+z", etc.

[[keys.command]]              # custom command bindings
key = "prefix+alt+g"
type = "pane"                 # pane (temporary) | shell (detached) | plugin_action
command = "lazygit"
description = "run lazygit"
# receives HERDR_SOCKET_PATH, HERDR_ACTIVE_WORKSPACE_ID, HERDR_ACTIVE_PANE_ID, HERDR_ACTIVE_PANE_CWD

[theme]
name = "catppuccin"           # catppuccin tokyo-night dracula nord gruvbox one-dark
auto_switch = true            # solarized kanagawa rose-pine vesper
light_name = "catppuccin-latte"
dark_name = "catppuccin"
# [theme.custom] accent = "#a6e3a1"

[ui]
sidebar_width = 32
mouse_capture = true
confirm_close = true
pane_borders = true
agent_panel_sort = "priority" # "spaces" (default) | "priority" (attention-based)

[ui.toast]
delivery = "off"              # off | herdr (in-app) | terminal | system (OS notifications)
delay_seconds = 1             # agent must hold state this long before notifying

[ui.sound]
enabled = true
# done_path / request_path: custom mp3s
[ui.sound.agents]
claude = "on"                 # per-agent: default | on | off

[advanced]
scrollback_limit_bytes = 10485760

[experimental]
pane_history = false          # save pane contents to session-history.json across restarts
                              # SECURITY: pane output may contain secrets — off by default
allow_nested = false
kitty_graphics = false

[session]
resume_agents_on_restore = true   # native agent session auto-resume after server restart
```

## Session state: what survives what

| | Detach/reattach | Server restart (stop/reboot) | Update w/o handoff | Update w/ handoff |
|---|---|---|---|---|
| Processes | keep running | **die**, panes restart as fresh shells in saved cwd | may survive if compatible | best-effort survive |
| Layout (workspaces/tabs/panes/cwd/focus) | intact | restored from `session.json` | restored | from live terminal |
| Screen contents | intact | only with `pane_history = true` (`session-history.json`) | same | from live terminal |
| Agent conversations | intact (never stopped) | native auto-resume only | same | intact |

## Native agent session auto-resume

- Enabled by default (`[session] resume_agents_on_restore = true`).
- Requires the agent's **integration installed** with minimum versions (Claude Code ≥ v6, Pi ≥ v2, ...). Check: `herdr integration status`.
- The integration reports the session reference via lifecycle hooks. Consequence: installing the integration **mid-session** doesn't register the already-running session (its start hook already fired) — only sessions started after installation auto-resume. Fallback for Claude Code: `claude --resume` in the pane's cwd.
- Resume happens automatically once a client attaches and provides terminal context.

## Claude Code integration details

`herdr integration install claude`:
- writes `~/.claude/hooks/herdr-agent-state.sh` — herdr-managed and auto-updated; treat like installed software, don't version it in dotfiles
- registers a `SessionStart` hook in `~/.claude/settings.json` using a **machine-absolute path** (`/var/home/...` on Fedora, `/Users/...` on macOS) — another reason not to stow settings.json naively
- switches state detection from screen-scraping to authoritative hook reports (reliable working/blocked/done in the sidebar)

## Troubleshooting agent state detection

- Authority order: lifecycle hooks (if integration installed) > screen manifests (TOML matched against the terminal buffer).
- `blocked` via screen detection is deliberately strict: only when the visible bottom buffer matches a known approval/question/permission UI.
- Debug with `herdr agent explain <target> [--verbose]`.
- Local manifest overrides: `~/.config/herdr/agent-detection/<agent>.toml`, then `herdr server reload-agent-manifests`.
- Inside VMs/sandboxes that hide the process tree, set `HERDR_AGENT=<agent>` so detection knows what's running.
